#!/usr/bin/env python3
"""Deterministic DOSBox/XTest full-playthrough parity runner.

The original Hexuma is driven through real XTest key events (DOSBox AUTOTYPE
cannot reliably feed Hexuma's BIOS keyboard reader). One DOSBox-X process stays
alive for the whole command sequence, a canonical screenshot is captured after
every command, and the Zig engine runs the exact same command file once with an
NDJSON state trace.

Semantic parity means state checkpoints and step-scoped response matching; it
does not mean pixel identity between the DOS GUI and the Zig X11 GUI.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from xtest_input import XTestClient  # noqa: E402

DEFAULT_GAME_DIR = Path("/home/bob/Downloads/Hexuma")
DEFAULT_SETUP = [
    {"id": "boot-1", "wait_ms": 10000, "tokens": ["enter"]},
    {"id": "boot-2", "wait_ms": 1000, "tokens": ["enter"]},
]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--sequence", help="JSON sequence file")
    p.add_argument("--commands-file", help="plain-text German command file")
    p.add_argument("--out", required=True, help="output directory")
    p.add_argument("--game-dir", default=str(DEFAULT_GAME_DIR))
    p.add_argument("--zig-bin", default=str(ROOT / "zig-out/bin/hexuma"))
    p.add_argument("--extracted", default=str(ROOT / "extracted"))
    p.add_argument("--dosbox", default="dosbox-x")
    p.add_argument("--display", default=os.environ.get("DISPLAY", ":1"))
    p.add_argument("--key-delay-ms", type=int, default=20)
    p.add_argument("--time-limit", type=int, default=0,
                   help="DOSBox-X time limit in seconds; 0 derives from command count")
    p.add_argument("--settle-interval-ms", type=int, default=120)
    p.add_argument("--settle-timeout-ms", type=int, default=5000)
    p.add_argument("--no-dosbox", action="store_true", help="engine trace only")
    p.add_argument("--no-engine", action="store_true", help="DOSBox captures only")
    p.add_argument("--no-ocr", action="store_true", help="skip step-scoped candidate OCR")
    return p.parse_args(args=None)


def load_sequence(args: argparse.Namespace) -> dict:
    if args.sequence:
        seq = json.loads(Path(args.sequence).read_text(encoding="utf-8"))
    elif args.commands_file:
        commands = []
        for i, line in enumerate(Path(args.commands_file).read_text(encoding="utf-8").splitlines(), 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            commands.append({"id": f"{i:04d}", "command": line,
                             "tokens": line.split() + ["enter"]})
        seq = {"name": "plain commands", "commands": commands}
    else:
        raise SystemExit("either --sequence or --commands-file is required")
    seq.setdefault("setup", DEFAULT_SETUP)
    seq.setdefault("commands", [])
    for i, item in enumerate(seq["commands"], 1):
        item.setdefault("id", f"{i:04d}")
        item.setdefault("command", " ".join(item.get("tokens", [])[:-1]))
        item.setdefault("tokens", item["command"].split() + ["enter"])
    return seq


def xprop_output(env: dict, args: list[str]) -> str:
    try:
        return subprocess.run(["xprop", *args], env=env, capture_output=True,
                              text=True, timeout=2).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def find_window(env: dict, pid: int) -> int | None:
    root = xprop_output(env, ["-root", "_NET_CLIENT_LIST"])
    ids = re.findall(r"0x[0-9a-fA-F]+", root)
    found = None
    for wid in ids:
        props = xprop_output(env, ["-id", wid, "WM_CLASS", "_NET_WM_PID", "_NET_WM_STATE"])
        if "DOSBox" not in props and "dosbox" not in props:
            continue
        if "_NET_WM_STATE_HIDDEN" in props:
            continue
        m = re.search(r"_NET_WM_PID.*?=\s*(\d+)", props)
        if not m or int(m.group(1)) != pid:
            continue
        try:
            info = subprocess.run(["xwininfo", "-id", wid], env=env, capture_output=True,
                                  text=True, timeout=2).stdout
        except (OSError, subprocess.SubprocessError):
            continue
        if "Map State: IsViewable" not in info:
            continue
        found = int(wid, 16)
    return found


def wait_window(env: dict, pid: int, timeout_ms: int = 20000) -> int:
    deadline = time.monotonic() + timeout_ms / 1000
    while time.monotonic() < deadline:
        wid = find_window(env, pid)
        if wid is not None:
            return wid
        time.sleep(0.2)
    raise RuntimeError("no viewable DOSBox window appeared")


def capture(env: dict, wid: int, path: Path) -> tuple[bytes, str] | None:
    try:
        result = subprocess.run(["import", "-silent", "-window", hex(wid), str(path)],
                                env=env, capture_output=True, timeout=5)
        if result.returncode != 0 or not path.is_file():
            return None
        raw = subprocess.run(["convert", str(path), "-depth", "8", "rgb:-"],
                             env=env, capture_output=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    return raw, hashlib.sha256(raw).hexdigest()


def stable_capture(env: dict, wid: int, path: Path, pre_hash: str | None,
                   interval_ms: int, timeout_ms: int) -> dict:
    deadline = time.monotonic() + timeout_ms / 1000
    previous_hash: str | None = None
    previous_raw: bytes | None = None
    changed = pre_hash is None
    stable = 0
    attempts = 0
    while time.monotonic() < deadline:
        attempts += 1
        shot = capture(env, wid, path)
        if shot is None:
            time.sleep(interval_ms / 1000)
            continue
        raw, digest = shot
        if pre_hash is not None and digest != pre_hash:
            changed = True
        if previous_hash == digest:
            stable += 1
        else:
            stable = 1
            previous_hash = digest
            previous_raw = raw
        if stable >= 2 and changed:
            return {"sha256": digest, "changed": changed, "attempts": attempts,
                    "stable": stable, "width": 320, "height": 200}
        time.sleep(interval_ms / 1000)
    # A command such as `warte` can be visually inert. Record the last stable
    # frame rather than failing the entire playthrough.
    if previous_hash is None:
        raise RuntimeError(f"window 0x{wid:x} could not be captured")
    return {"sha256": previous_hash, "changed": changed, "attempts": attempts,
            "stable": stable, "width": 320, "height": 200}


def write_config(path: Path, scratch: Path, log: Path, time_limit: int) -> None:
    path.write_text(f"""[sdl]
fullscreen=false
fullresolution=original
windowresolution=original
windowposition=10,10
output=surface
videodriver=x11
autolock=false
priority=normal,normal
showmenu=false
showbasic=false

[dosbox]
startbanner=false
fastbioslogo=true
quit warning=false
working directory option=noprompt

[render]
scaler=none
aspect=false
doublescan=false

[video]
scaler=none
aspect=false
doublescan=false

[cpu]
cycles=fixed 3000
core=normal

[vsync]
vsyncmode=off

[log]
logfile={log}

[autoexec]
mount c {scratch}
c:
hexuma.bat
""", encoding="utf-8")


def run_engine(args: argparse.Namespace, seq: dict, out: Path) -> dict:
    commands_file = out / "commands.txt"
    lines = []
    for item in seq["commands"]:
        command = item.get("command")
        if command:
            lines.append(command)
    commands_file.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
    trace_file = out / "engine-trace.ndjson"
    cmd = [args.zig_bin, "play", "--extracted", args.extracted,
           "--script", str(commands_file), "--trace-file", str(trace_file)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    (out / "engine-output.txt").write_text(result.stdout, encoding="utf-8")
    (out / "engine-stderr.txt").write_text(result.stderr, encoding="utf-8")
    trace = []
    for line in trace_file.read_text(encoding="utf-8").splitlines():
        if line.strip():
            trace.append(json.loads(line))
    by_step = {row["step"]: row for row in trace}
    checkpoints = []
    for index, item in enumerate(seq["commands"], 1):
        expected = item.get("checkpoints")
        if not expected:
            continue
        state = by_step.get(index, {}).get("state", {})
        ok = all(state.get(k) == v for k, v in expected.items())
        checkpoints.append({"step": index, "id": item["id"], "expected": expected,
                            "actual": {k: state.get(k) for k in expected}, "ok": ok})
    return {"returncode": result.returncode,
            "commands": len(lines),
            "checkpoints": checkpoints,
            "checkpoints_ok": all(row["ok"] for row in checkpoints),
            "final_state": trace[-1]["state"] if trace else None}


def run_dosbox(args: argparse.Namespace, seq: dict, out: Path) -> dict:
    steps_dir = out / "steps"
    steps_dir.mkdir(parents=True, exist_ok=True)
    scratch = out / "game"
    if not scratch.is_dir():
        shutil.copytree(args.game_dir, scratch, dirs_exist_ok=True)
    conf = out / "dosbox.conf"
    log = out / "dosbox.log"
    time_limit = args.time_limit or max(900, len(seq["commands"]) * 12)
    write_config(conf, scratch, log, time_limit)

    env = os.environ.copy()
    env["DISPLAY"] = args.display
    env["SDL_VIDEODRIVER"] = "x11"
    env["SDL_AUDIODRIVER"] = "dummy"
    proc = subprocess.Popen(
        [args.dosbox, "-conf", str(conf), "-time-limit", str(time_limit)],
        env=env, stdout=open(out / "dosbox-stdout.txt", "wb"),
        stderr=subprocess.STDOUT,
    )
    client = XTestClient(args.display)
    records = []
    previous_hash: str | None = None
    failure = None
    try:
        wid = wait_window(env, proc.pid)
        records.append({"id": "window", "kind": "setup", "window": hex(wid)})
        for i, action in enumerate(seq["setup"]):
            wait = int(action.get("wait_ms", 0)) / 1000
            if wait:
                time.sleep(wait)
            wid = wait_window(env, proc.pid)
            try:
                client.send_tokens(wid, action["tokens"], args.key_delay_ms)
            except Exception as exc:
                raise RuntimeError(f"setup action {action.get('id', i)} failed: {exc}") from exc
        ready = stable_capture(env, wid, steps_dir / "00-ready.png", None,
                               args.settle_interval_ms, args.settle_timeout_ms)
        previous_hash = ready["sha256"]
        records.append({"id": "00-ready", "kind": "setup", "frame": "steps/00-ready.png",
                        **ready, "window": hex(wid)})

        for idx, item in enumerate(seq["commands"], 1):
            wait = int(item.get("wait_ms", 0)) / 1000
            if wait:
                time.sleep(wait)
            wid = wait_window(env, proc.pid)
            if proc.poll() is not None:
                raise RuntimeError(f"DOSBox exited early before step {item['id']} (rc={proc.returncode})")
            try:
                client.send_tokens(wid, item["tokens"], args.key_delay_ms)
            except Exception as exc:
                frame = steps_dir / f"{item['id']}-input-failed.png"
                capture(env, wid, frame)
                raise RuntimeError(
                    f"input failed at step {idx}/{len(seq['commands'])} {item['id']} "
                    f"command={item.get('command','')!r}: {exc}; frame={frame}"
                ) from exc
            frame = steps_dir / f"{item['id']}.png"
            meta = stable_capture(env, wid, frame, previous_hash,
                                  args.settle_interval_ms, args.settle_timeout_ms)
            previous_hash = meta["sha256"]
            records.append({"id": item["id"], "kind": "command",
                            "command": item.get("command", ""),
                            "frame": f"steps/{item['id']}.png",
                            "window": hex(wid), **meta})
    except Exception as exc:
        failure = str(exc)
        # Capture final state for diagnosis.
        try:
            wid2 = find_window(env, proc.pid)
            if wid2 is not None:
                capture(env, wid2, out / "failure.png")
        except Exception:
            pass
    finally:
        client.close()
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)
    report = {"returncode": proc.returncode, "steps": records,
              "time_limit": time_limit, "log": str(log)}
    if failure:
        report["failure"] = failure
    return report


def run_ocr(args: argparse.Namespace, seq: dict, out: Path, report: dict) -> None:
    if args.no_ocr or "dosbox" not in report or "engine" not in report:
        return
    ocr_dir = out / "ocr"
    ocr_dir.mkdir(parents=True, exist_ok=True)
    trace_file = out / "engine-trace.ndjson"
    step_by_id = {item["id"]: i for i, item in enumerate(seq["commands"], 1)}
    for record in report["dosbox"]["steps"]:
        frame = out / record["frame"]
        if not frame.is_file():
            continue
        step = step_by_id.get(record["id"])
        if step is None:
            continue
        result_path = ocr_dir / f"{record['id']}.json"
        subprocess.run([
            sys.executable, str(HERE / "parity_ocr.py"), str(frame),
            "--candidates-json", str(trace_file), "--step", str(step),
            "--json", str(result_path),
        ], capture_output=True, text=True)
        if not result_path.is_file():
            continue
        data = json.loads(result_path.read_text(encoding="utf-8"))
        top = data["matches"][0] if data.get("matches") else {}
        record["ocr"] = {"confidence": top.get("confidence", 0.0),
                         "line": top.get("line", ""),
                         "y": top.get("y"), "x": top.get("x")}


def main() -> int:
    args = parse_args()
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    seq = load_sequence(args)
    (out / "sequence.json").write_text(
        json.dumps(seq, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    report: dict = {"name": seq.get("name", ""), "commands": len(seq["commands"])}
    if not args.no_engine:
        report["engine"] = run_engine(args, seq, out)
    if not args.no_dosbox:
        report["dosbox"] = run_dosbox(args, seq, out)
    run_ocr(args, seq, out, report)
    (out / "parity-report.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"full-playthrough report: {out / 'parity-report.json'}")
    ok = True
    if not args.no_engine and not report["engine"]["checkpoints_ok"]:
        print("engine checkpoint mismatch", file=sys.stderr)
        ok = False
    if not args.no_dosbox and report.get("dosbox", {}).get("failure"):
        print(f"dosbox failure: {report['dosbox']['failure']}", file=sys.stderr)
        ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"dosbox_parity.py: {exc}", file=sys.stderr)
        raise SystemExit(1)
