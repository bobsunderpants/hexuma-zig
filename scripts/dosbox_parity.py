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
import signal
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
    p.add_argument("--replay-commands-file",
                   help="verified prefix replayed in both DOSBox and the engine before --commands-file")
    p.add_argument("--engine-load",
                   help="portable engine state to load before commands (requires --no-dosbox)")
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
    p.add_argument("--auto-taste", action="store_true", help="advance detected -TASTE- prompts before command input (default behavior; flag kept for compatibility)")
    p.add_argument("--no-auto-taste", action="store_true", help="disable automatic -TASTE- advance (debug only)")
    p.add_argument("--verify-input", action="store_true", default=True, help="OCR-verify typed command before Enter and backspace-correct if wrong")
    p.add_argument("--no-verify-input", action="store_true", help="disable typed-command OCR verification")
    return p.parse_args(args=None)


PROFILE = bool(os.environ.get("HEXUMA_PROFILE"))
_last_t = 0.0
_PREFERRED_WINDOW: int | None = None

def prof(label: str) -> None:
    global _last_t
    if not PROFILE:
        return
    now = time.monotonic()
    print(f"PROFILE {label} {now - _last_t:.3f}", file=sys.stderr)
    _last_t = now


def command_tokens(command: str) -> list[str]:
    """Convert a command string to XTest tokens, preserving spaces as 'space'.

    DOSBox/Hexuma input must include literal spaces between words. Using the
    token name 'space' avoids comma/shell splitting issues in xtest_input.py.
    """
    tokens: list[str] = []
    for ch in command:
        if ch == " ":
            tokens.append("space")
        elif ch == "	":
            tokens.append("space")
        else:
            tokens.append(ch)
    tokens.append("enter")
    return tokens


def _parse_command_file(path: Path, prefix: str = "") -> list[dict]:
    commands = []
    for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        ident = f"{prefix}{i:04d}"
        if line.lower() in ("@taste", "@taste-enter", "@key space"):
            commands.append({"id": ident, "command": line, "tokens": ["space"]})
            continue
        if line.lower().startswith("@key "):
            toks = [t for t in line.split()[1:] if t]
            commands.append({"id": ident, "command": line, "tokens": toks})
            continue
        if line.lower().startswith("@wait "):
            try:
                ms = int(line.split()[1])
            except Exception:
                ms = 0
            commands.append({"id": ident, "command": line, "tokens": [], "wait_ms": ms})
            continue
        commands.append({"id": ident, "command": line,
                         "tokens": command_tokens(line)})
    return commands


def load_sequence(args: argparse.Namespace) -> dict:
    replay = []
    if args.replay_commands_file:
        replay = _parse_command_file(Path(args.replay_commands_file), "P")
    if args.sequence:
        seq = json.loads(Path(args.sequence).read_text(encoding="utf-8"))
    elif args.commands_file:
        seq = {"name": "plain commands",
               "commands": _parse_command_file(Path(args.commands_file))}
    else:
        raise SystemExit("either --sequence or --commands-file is required")
    seq.setdefault("setup", DEFAULT_SETUP)
    seq.setdefault("commands", [])
    if replay:
        seq["replay"] = replay
    for key in ("replay", "commands"):
        for i, item in enumerate(seq.get(key, []), 1):
            item.setdefault("id", f"{key[0].upper()}{i:04d}" if key == "replay" else f"{i:04d}")
            if "command" not in item:
                toks = item.get("tokens", [])
                if toks and toks[-1] == "enter":
                    toks = toks[:-1]
                item["command"] = " ".join(toks)
            if "tokens" not in item:
                item["tokens"] = command_tokens(item["command"])
    return seq


def xprop_output(env: dict, args: list[str]) -> str:
    try:
        return subprocess.run(["xprop", *args], env=env, capture_output=True,
                              text=True, timeout=2).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def _root_tree(env: dict) -> str:
    try:
        return subprocess.run(["xwininfo", "-root", "-tree"], env=env, capture_output=True,
                              text=True, timeout=2).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def xprop_window_ids(env: dict) -> list[str]:
    return re.findall(r"(0x[0-9a-fA-F]+)", _root_tree(env))


def _root_geometry_map(env: dict) -> dict[int, tuple[int, int]]:
    """Parse window id -> (width, height) from one root-tree query."""
    result: dict[int, tuple[int, int]] = {}
    for line in _root_tree(env).splitlines():
        m = re.search(r"(0x[0-9a-fA-F]+).*?\s(\d+)x(\d+)\+", line)
        if m:
            result[int(m.group(1), 16)] = (int(m.group(2)), int(m.group(3)))
    return result


def window_matches(env: dict, wid: int, pid: int) -> bool:
    """Whether a previously selected window still belongs to the DOSBox pid."""
    try:
        probe = subprocess.run(["xwininfo", "-id", hex(wid)], env=env,
                               capture_output=True, text=True, timeout=2)
        if probe.returncode != 0:
            return False
    except (OSError, subprocess.SubprocessError):
        return False
    props = xprop_output(env, ["-id", hex(wid), "WM_CLASS", "_NET_WM_PID"])
    match = re.search(r"_NET_WM_PID.*?=\s*(\d+)", props)
    if match:
        return int(match.group(1)) == pid
    # Never match WM_NAME: the parity terminal's title contains "dosbox" while
    # the command is running, which previously pinned X focus to the terminal.
    klass = re.search(r"WM_CLASS\(STRING\) = (.*)", props)
    return bool(klass and "dosbox" in klass.group(1).lower())


def remember_window(meta: dict, env: dict, pid: int) -> None:
    global _PREFERRED_WINDOW
    value = meta.get("window")
    if not isinstance(value, str) or not value.startswith("0x"):
        return
    wid = int(value, 16)
    if window_matches(env, wid, pid):
        _PREFERRED_WINDOW = wid


def find_window(env: dict, pid: int, sizes: set[tuple[int, int]] | None = None) -> int | None:
    """Find the DOSBox-X game window quickly.

    The X desktop contains many tiny helper windows; querying each one with a
    2s xwininfo timeout costs seconds and blows the 600s DOSBox time limit.
    Parse geometry from a single root-tree query, then inspect only DOSBox
    window sizes. Startup uses a 640x400 text-mode window; the game switches
    to 320x200 after the two boot Enter presses. Once the in-game window is
    chosen, keep it: DOSBox can leave a stale startup window in the tree, and
    switching between two matching windows loses X input focus.
    """
    global _PREFERRED_WINDOW
    if _PREFERRED_WINDOW is not None and window_matches(env, _PREFERRED_WINDOW, pid):
        return _PREFERRED_WINDOW
    geom = _root_geometry_map(env)
    wanted = sizes if sizes is not None else {(320, 200), (640, 400)}
    candidates = [wid for wid, size in geom.items() if size in wanted]
    if not candidates:
        return None
    # Prefer the in-game 320x200 window when both sizes are present.
    candidates.sort(key=lambda wid: 0 if geom[wid] == (320, 200) else 1)
    fallback = None
    for wid in candidates:
        props = xprop_output(env, ["-id", hex(wid), "WM_CLASS", "_NET_WM_PID", "_NET_WM_STATE", "WM_NAME"])
        m = re.search(r"_NET_WM_PID.*?=\s*(\d+)", props)
        if m and int(m.group(1)) == pid:
            return wid
        if "dosbox" in props.lower() and fallback is None:
            fallback = wid
    return fallback if fallback is not None else candidates[0]


def wait_window(env: dict, pid: int, timeout_ms: int = 20000,
                sizes: set[tuple[int, int]] | None = None) -> int:
    deadline = time.monotonic() + timeout_ms / 1000
    while time.monotonic() < deadline:
        wid = find_window(env, pid, sizes)
        if wid is not None:
            return wid
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            raise RuntimeError(f"dosbox process {pid} exited while waiting for window")
        except Exception:
            pass
        time.sleep(0.2)
    diag = []
    try:
        os.kill(pid, 0); diag.append("pid_alive=True")
    except Exception:
        diag.append("pid_alive=False")
    for wid, size in _root_geometry_map(env).items():
        if size in ((320, 200), (640, 400)):
            props = xprop_output(env, ["-id", hex(wid), "WM_CLASS", "_NET_WM_PID", "_NET_WM_STATE", "WM_NAME"])
            diag.append(f"{hex(wid)} sz={size[0]}x{size[1]} {props.strip()[:80]}")
    raise RuntimeError(f"no viewable DOSBox window appeared; diag={diag[:8]}")

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


def ocr_typed_command(frame: Path) -> str:
    """OCR the bottom text line (the input prompt line) to verify typed command.

    The input line's y position depends on how much response text precedes it,
    so a fixed crop is unreliable. OCR the bottom half with TSV output and
    reconstruct the bottom-most text line (words within 4 original pixels of
    the lowest word top, which merges prompt + command + cursor artifacts).
    """
    try:
        proc = subprocess.run([
            'bash','-lc',
            f"convert {str(frame)!s} -crop 320x100+0+100 -resize 400% -type Grayscale -sharpen 0x1 png:- | tesseract stdin stdout -l deu --psm 6 tsv"
        ], capture_output=True, text=True, timeout=20)
        words = []
        for row in proc.stdout.splitlines()[1:]:
            parts = row.split('\t')
            if len(parts) < 12:
                continue
            text = parts[11].strip()
            if not text:
                continue
            try:
                conf = float(parts[10])
                left, top = int(parts[6]), int(parts[7])
            except ValueError:
                continue
            if conf >= 0:
                words.append((left, top, text))
        if words:
            max_top = max(w[1] for w in words)
            line = sorted((w for w in words if w[1] >= max_top - 16), key=lambda w: w[0])
            txt = ' '.join(w[2] for w in line).strip()
            if any(c.isalpha() for c in txt):
                return txt
    except Exception:
        pass
    # Fallback: legacy fixed crop of the input area.
    try:
        proc = subprocess.run([
            'bash','-lc',
            f"convert {str(frame)!s} -crop 320x48+0+152 -resize 400% -type Grayscale -contrast-stretch 2%x2% png:- | tesseract stdin stdout -l deu --psm 6"
        ], capture_output=True, text=True, timeout=15)
        txt = proc.stdout.strip().replace('\n',' ')
    except Exception:
        txt = ''
    return txt


def ocr_typed_candidates(frame: Path) -> list[str]:
    """Several independent OCR reads of the echoed command line.

    The 320x200 VGA font makes Tesseract glue adjacent words together and
    confuse the blinking cursor with punctuation.  Combining the structural
    TSV read with fixed crops (and accepting a match from any of them) keeps
    verification strict while tolerating crop drift as the prompt moves.
    """
    candidates = [ocr_typed_command(frame)]
    for crop, scale, psm in (
        ("320x8+0+186", 800, 7),
        ("320x20+0+180", 400, 6),
        ("320x16+0+184", 600, 7),
    ):
        try:
            proc = subprocess.run([
                'bash', '-lc',
                f"convert {str(frame)!s} -crop {crop} -resize {scale}% "
                f"-type Grayscale -sharpen 0x1 png:- | "
                f"tesseract stdin stdout -l deu --psm {psm}"
            ], capture_output=True, text=True, timeout=15)
            txt = proc.stdout.strip().replace('\n', ' ')
            if txt:
                candidates.append(txt)
        except Exception:
            pass
    return [c for c in candidates if c]


def normalize_cmd(s: str) -> str:
    import unicodedata
    s = s.lower().strip().replace('ß','ss')
    s = ''.join(c for c in unicodedata.normalize('NFKD', s) if not unicodedata.combining(c))
    s = re.sub(r'[^a-z0-9 ]+',' ', s)
    s = re.sub(r'\s+',' ', s).strip()
    return s


def _levenshtein(a: str, b: str) -> int:
    if a == b:
        return 0
    if not a:
        return len(b)
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def _token_hit(t: str, x: str) -> bool:
    if t == x:
        return True
    if len(t) >= 4 and (x.startswith(t[:4]) or t.startswith(x[:4])):
        return True
    # OCR noise: g->s, u->y, prompt glyphs glued to the first word ("Sschaue").
    for cand in (x, x[1:], x[2:]):
        if cand and _levenshtein(t, cand) <= max(1, len(t) // 5):
            return True
    return False


def glyph_typed_command_matches(expected: str, frame: Path) -> bool:
    """Verify a typed command against the original 8x8 VGA glyph bitmap.

    Tesseract sometimes reads the illustration text (for example the "Harald
    Evers" credit) instead of the input line.  Matching against the font used
    by the original game avoids both reading the wrong line and weakening the
    command check: a coincidental match in the picture scores far below the
    0.45 threshold required here.
    """
    try:
        from parity_ocr import best_match, load_font, load_screen
        font_path = Path(os.environ.get(
            "HEXUMA_FONT", "/home/bob/Downloads/Hexuma/8X8PROP.FON"))
        glyphs = load_font(font_path)
        screen = load_screen(frame)
        expected_line = ">" + normalize_cmd(expected)
        det = best_match(expected_line, glyphs, screen, min_y=178)
        return (float(det.get("confidence", 0.0)) >= 0.45 and
                float(det.get("matched", 0.0)) >= 20)
    except Exception:
        return False


def typed_command_matches(expected: str, ocr: str) -> bool:
    e = normalize_cmd(expected)
    o = normalize_cmd(ocr)
    if not e:
        return True
    # Tesseract reads the trailing "1" of the game's info1 debug command as
    # nothing or as "t"/"l". The 400% typed-frame crop was manually confirmed.
    if e == "info1" and re.search(r"\b(?:info|into|infot|infoll)\b", o):
        return True
    # Tesseract renders the German "glas" in the typed prompt as "slas",
    # "slasl", or "sls" (manually confirmed on the 400% step crop).
    if "glas" in e:
        eo = re.sub(r"\b(?:slas|slasl|sls|glasl)\b", "glas", o)
        eo = re.sub(r"\blese\b", "lege", eo)
        if e in eo or ("glas" in eo and e.split()[-1] == "glas"):
            return True
    if e in o:
        return True
    # OCR often appends garbage/truncates the last char and merges words
    # ("öffnehaustüre"), so also compare whitespace-free strings with a
    # bounded edit distance over sliding windows.
    ec = e.replace(' ', '')
    oc = o.replace(' ', '')
    if ec in oc:
        return True
    limit = max(1, min(3, len(ec) // 8))
    for width in (len(ec), len(ec) + 1, len(ec) + 2, len(ec) - 1):
        if width <= 0:
            continue
        for i in range(len(oc) - width + 1):
            if _levenshtein(ec, oc[i:i + width]) <= limit:
                return True
    # Finally fall back to per-token matching for heavy glyph noise.
    et = e.split(); ot = o.split()
    if not et:
        return True
    hits = 0
    for t in et:
        if any(_token_hit(t, x) for x in ot):
            hits += 1
    return hits == len(et)
TASTE_CANDIDATES = ["- TASTE -", "-TASTE-", "- TASTE-", "-TASTE -"]


def frame_mean(frame: Path) -> float:
    """Mean normalized brightness; the pre-game idle screen is fully black."""
    try:
        out = subprocess.run(["convert", str(frame), "-colorspace", "Gray",
                              "-format", "%[fx:mean]", "info:"],
                             capture_output=True, text=True, timeout=5).stdout.strip()
        return float(out)
    except Exception:
        return 0.0


def ocr_frame_text(frame: Path) -> str:
    """Plain OCR of the whole frame, used only for startup-state classification."""
    try:
        proc = subprocess.run([
            "bash", "-lc",
            f"convert {str(frame)!s} -filter point -resize 400% "
            f"-type Grayscale png:- | tesseract stdin stdout --psm 6 -l deu",
        ], capture_output=True, text=True, timeout=20)
        return " ".join(proc.stdout.split())
    except Exception:
        return ""


def classify_start_frame(frame: Path) -> dict:
    """Classify the frame after boot keys instead of blindly pressing more keys.

    A successful boot shows no text. The illustrated title/credits sequence and
    a genuine "- TASTE -" prompt are reported explicitly so the caller can
    either advance on a confirmed prompt or fail with the evidence frame.
    """
    text = ocr_frame_text(frame)
    det = detect_taste(frame)
    if det.get("detected"):
        return {"state": "taste", "text": text, "taste": det}
    lowered = text.lower()
    if any(mark in lowered for mark in (
        "lieber abenteurer", "die autoren", "das auge", "harald evers",
        "andreas neth", "thomas kometer",
    )):
        return {"state": "credits", "text": text, "taste": det}
    if not text and frame_mean(frame) <= 0.02:
        return {"state": "ready", "text": text, "taste": det}
    return {"state": "unknown", "text": text, "taste": det}


def detect_taste(frame: Path) -> dict:
    """Best-effort detection of the original game's "- TASTE -" prompt.

    Uses parity_ocr glyph matching; returns match metadata. Conservative
    threshold avoids auto-advancing on normal text (which would desync input).
    """
    try:
        from parity_ocr import load_font, load_screen, best_match
        font = Path(os.environ.get("HEXUMA_FONT", "/home/bob/Downloads/Hexuma/8X8PROP.FON"))
        glyphs = load_font(font)
        screen = load_screen(frame)
        best = {"confidence": 0.0, "y": 0, "x": 0, "line": ""}
        for line in TASTE_CANDIDATES:
            m = best_match(line, glyphs, screen)
            conf = float(m.get("confidence", 0.0))
            y = int(m.get("y", 0))
            # - TASTE - prompt appears at the very bottom of the text area.
            # Genuine prompt measures conf~0.59 at y=186; body-text false
            # positives sit lower-confidence (~0.46) and higher up (y~178).
            if y >= 182 and conf > float(best["confidence"]):
                best = {"confidence": conf, "y": y, "x": int(m.get("x", 0)), "line": line}
        best["detected"] = best["confidence"] >= 0.55
        return best
    except Exception as exc:
        return {"confidence": 0.0, "y": 0, "x": 0, "line": "", "detected": False, "error": str(exc)}


def stable_capture(env: dict, wid: int, path: Path, pre_hash: str | None,
                   interval_ms: int, timeout_ms: int, pid: int | None = None) -> dict:
    deadline = time.monotonic() + timeout_ms / 1000
    previous_hash: str | None = None
    previous_raw: bytes | None = None
    changed = pre_hash is None
    stable = 0
    attempts = 0
    current_wid = wid
    while time.monotonic() < deadline:
        attempts += 1
        if pid is not None:
            resolved = find_window(env, pid)
            if resolved is not None:
                current_wid = resolved
        shot = capture(env, current_wid, path)
        if shot is None:
            if pid is not None:
                try:
                    current_wid = wait_window(env, pid, timeout_ms=3000)
                except Exception:
                    pass
            else:
                w=find_window(env, pid) if pid else None
                if w is not None: current_wid=w
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
                    "stable": stable, "width": 320, "height": 200, "window": hex(current_wid)}
        time.sleep(interval_ms / 1000)
    # A command such as `warte` can be visually inert. Record the last stable
    # frame rather than failing the entire playthrough.
    if previous_hash is None:
        raise RuntimeError(f"window 0x{current_wid:x} could not be captured")
    return {"sha256": previous_hash, "changed": changed, "attempts": attempts,
            "stable": stable, "width": 320, "height": 200, "window": hex(current_wid)}


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
keyboardlayout=de

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
keyb de
hexuma.bat
""", encoding="utf-8")


def run_engine(args: argparse.Namespace, seq: dict, out: Path) -> dict:
    replay = seq.get("replay", [])
    commands_file = out / "commands.txt"
    lines = [item["command"] for item in replay if item.get("command")]
    continuation_lines = []
    for item in seq["commands"]:
        command = item.get("command")
        if command:
            continuation_lines.append(command)
    lines.extend(continuation_lines)
    commands_file.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
    trace_file = out / "engine-trace.ndjson"
    cmd = [args.zig_bin, "play", "--extracted", args.extracted]
    if args.engine_load:
        cmd.extend(["--load", args.engine_load])
    cmd.extend(["--script", str(commands_file), "--trace-file", str(trace_file)])
    result = subprocess.run(cmd, capture_output=True, text=True)
    (out / "engine-output.txt").write_text(result.stdout, encoding="utf-8")
    (out / "engine-stderr.txt").write_text(result.stderr, encoding="utf-8")
    raw_trace = []
    for line in trace_file.read_text(encoding="utf-8").splitlines():
        if line.strip():
            raw_trace.append(json.loads(line))
    trace = []
    for row in raw_trace:
        step = row.get("step", 0)
        if replay and step > len(replay):
            row = dict(row)
            row["step"] = step - len(replay)
            trace.append(row)
        elif not replay:
            trace.append(row)
    if replay:
        trace_file.write_text(
            "\n".join(json.dumps(row, ensure_ascii=False) for row in trace) + "\n",
            encoding="utf-8")
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
            "commands": len(continuation_lines),
            "replay_commands": len(replay),
            "loaded_state": args.engine_load,
            "checkpoints": checkpoints,
            "checkpoints_ok": all(row["ok"] for row in checkpoints),
            "final_state": trace[-1]["state"] if trace else None}


def _has_live_parity_ancestor(pid: int) -> bool:
    """Whether a DOSBox still belongs to another active parity runner."""
    seen: set[int] = set()
    current = pid
    while current not in seen and current > 1:
        seen.add(current)
        try:
            status = Path(f"/proc/{current}/status").read_text()
        except OSError:
            return False
        match = re.search(r"^PPid:\s*(\d+)", status, re.MULTILINE)
        if not match:
            return False
        parent = int(match.group(1))
        if parent <= 1:
            return False
        try:
            cmdline = Path(f"/proc/{parent}/cmdline").read_bytes().replace(b"\0", b" ").decode("utf-8", "replace")
        except OSError:
            return False
        if "dosbox_parity.py" in cmdline and parent != os.getpid():
            return True
        current = parent
    return False


def kill_stale_dosbox() -> None:
    """Remove unowned DOSBox windows before starting a fresh sequence.

    A previous failed run can leave a DOSBox-X window on top. KDE then gives
    that stale window X input focus, so a newly started instance cannot receive
    keystrokes even though its own window is found by geometry. A DOSBox with a
    still-live parity ancestor is left alone: concurrent runs used to kill each
    other at startup and abort with a misleading "exited early" failure.
    """
    try:
        found = subprocess.run(["pgrep", "-f", r"(^|/)dosbox-x($|\s)"],
                               capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return
    stale: list[int] = []
    for raw in found.stdout.split():
        try:
            pid = int(raw)
        except ValueError:
            continue
        if pid == os.getpid() or _has_live_parity_ancestor(pid):
            continue
        stale.append(pid)
    for pid in stale:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in stale:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def run_dosbox(args: argparse.Namespace, seq: dict, out: Path) -> dict:
    global _PREFERRED_WINDOW
    _PREFERRED_WINDOW = None
    kill_stale_dosbox()
    steps_dir = out / "steps"
    steps_dir.mkdir(parents=True, exist_ok=True)
    scratch = out / "game"
    if not scratch.is_dir():
        shutil.copytree(args.game_dir, scratch, dirs_exist_ok=True)
    conf = out / "dosbox.conf"
    log = out / "dosbox.log"
    total_commands = len(seq.get("replay", [])) + len(seq["commands"])
    time_limit = args.time_limit or max(900, total_commands * 12)
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
    client = XTestClient(args.display, de_dosbox_mode=True)
    records = []
    previous_hash: str | None = None
    failure = None
    try:
        # DOSBox-X startup is nondeterministic: it sometimes reaches the
        # 320x200 game display on its own and sometimes stalls in the 640x400
        # text window until it receives a real pointer event. Click any
        # non-game startup window before waiting for the game display.
        startup_sizes = {(320, 200), (640, 400), (720, 400)}
        first = wait_window(env, proc.pid, sizes=startup_sizes)
        first_size = _root_geometry_map(env).get(first)
        records.append({"id": "startup-window", "kind": "setup",
                        "window": hex(first),
                        "size": [first_size[0], first_size[1]] if first_size else None})
        if first_size != (320, 200):
            try:
                client.click_focus(first)
            except Exception:
                pass
            time.sleep(1)
        wid = wait_window(env, proc.pid, timeout_ms=30000, sizes={(320, 200)})
        _PREFERRED_WINDOW = wid
        records.append({"id": "window", "kind": "setup", "window": hex(wid)})
        setup_actions = list(seq.get("setup", []))
        if first_size != (320, 200) and len(setup_actions) > 1:
            # The click that unblocks startup is itself consumed as the first
            # game keypress, so only one further boot Enter is needed.
            setup_actions = setup_actions[:1]
        records.append({"id": "setup-actions", "kind": "setup",
                        "count": len(setup_actions)})
        for i, action in enumerate(setup_actions):
            wait = int(action.get("wait_ms", 0)) / 1000
            if wait:
                time.sleep(wait)
            wid = wait_window(env, proc.pid, sizes={(320, 200)})
            try:
                client.send_tokens(wid, action["tokens"], args.key_delay_ms)
            except Exception as exc:
                raise RuntimeError(f"setup action {action.get('id', i)} failed: {exc}") from exc
        # The illustrated intro is timed, not key-driven. Poll it without input
        # until the original "- TASTE -" prompt is actually detected. Sending
        # setup keys during the animation only desynchronises buffered input.
        current_ready = steps_dir / "00-ready.png"
        intro_debug = []
        startup_deadline = time.monotonic() + float(
            os.environ.get("HEXUMA_START_TIMEOUT_S", "120"))
        state = None
        while time.monotonic() < startup_deadline:
            try:
                wid = wait_window(env, proc.pid, timeout_ms=3000,
                                  sizes={(320, 200), (640, 400), (720, 400)})
                probe = steps_dir / f"startup-{len(intro_debug):03d}.png"
                if capture(env, wid, probe) is None:
                    time.sleep(0.25)
                    continue
                cls = classify_start_frame(probe)
                state = cls["state"]
                intro_debug.append({"frame": probe.name, **cls,
                                    "mean": frame_mean(probe)})
                if state == "taste":
                    break
            except Exception as exc:
                intro_debug.append({"frame": None, "state": "error", "error": str(exc)})
            time.sleep(0.25)
        if state != "taste":
            raise RuntimeError(
                f"game - TASTE - prompt was not detected during startup; "
                f"last state={state!r}; frames={steps_dir}")
        shutil.copyfile(probe, current_ready)
        ready = stable_capture(env, wid, current_ready, None,
                               args.settle_interval_ms, args.settle_timeout_ms, pid=proc.pid)
        remember_window(ready, env, proc.pid)
        wid = int(ready["window"], 16)
        previous_hash = ready["sha256"]
        records.append({"id": "00-ready", "kind": "setup", "frame": "steps/00-ready.png",
                        **ready, "window": hex(wid)})
        records.append({"id": "intro-state", "kind": "setup",
                        "state": state, "debug": intro_debug,
                        "window": hex(wid)})

        replay = seq.get("replay", [])
        all_items = replay + seq["commands"]
        for idx, item in enumerate(all_items, 1):
            is_replay = idx <= len(replay)
            wait = int(item.get("wait_ms", 0)) / 1000
            if wait:
                time.sleep(wait)
            prof(f"pre-wait-{item['id']}")
            wid = wait_window(env, proc.pid)
            prof(f"post-wait-{item['id']}")
            if proc.poll() is not None:
                raise RuntimeError(f"DOSBox exited early before step {item['id']} (rc={proc.returncode})")

            # Advance through "- TASTE -" prompts before sending command input.
            # The original game blocks for a keypress; sending command text then
            # would lose/garble input.
            taste_presses = 0
            taste_debug = []
            auto_taste = (not args.no_auto_taste)
            if auto_taste:
                for _ in range(12):
                    probe = steps_dir / f"{item['id']}-probe.png"
                    # A probe needs a current stable frame, not a *changed*
                    # frame relative to the previous command. Requiring a
                    # change here wastes the whole settle timeout whenever the
                    # screen is already quiet (which is the common case).
                    probe_meta = stable_capture(env, wid, probe, None,
                                                args.settle_interval_ms, args.settle_timeout_ms, pid=proc.pid)
                    remember_window(probe_meta, env, proc.pid)
                    wid = int(probe_meta["window"], 16)
                    det = detect_taste(probe)
                    taste_debug.append({"phase": "probe", "frame": probe.name, **det})
                    if not det.get("detected"):
                        break
                    taste_presses += 1
                    try:
                        client.activate(wid, strict=False)
                        client.send_tokens(wid, ["space"], args.key_delay_ms)
                    except Exception as exc:
                        wid = wait_window(env, proc.pid)
                        client.activate(wid, strict=False)
                        try:
                            client.send_tokens(wid, ["space"], args.key_delay_ms)
                        except Exception as exc2:
                            raise RuntimeError(f"taste-advance failed at step {item['id']}: {exc2}") from exc2
                    post = steps_dir / f"{item['id']}-taste-{taste_presses}.png"
                    post_meta = stable_capture(env, wid, post, probe_meta["sha256"],
                                               args.settle_interval_ms, args.settle_timeout_ms, pid=proc.pid)
                    remember_window(post_meta, env, proc.pid)
                    wid = int(post_meta["window"], 16)
                    previous_hash = post_meta["sha256"]
                    taste_debug.append({"phase": "post", "frame": post.name,
                                        "sha256": post_meta["sha256"],
                                        "changed": post_meta.get("changed", False)})
                    # A genuine -TASTE- dismiss changes the screen. If the space
                    # press changed nothing, the detection was a false positive;
                    # stop instead of spamming keys into the input buffer.
                    if not post_meta.get("changed", False):
                        taste_debug.append({"phase": "no-change-stop", "frame": post.name})
                        break

            prof(f"post-taste-{item['id']}")
            input_verify = []
            if item.get("tokens"):
                cmd = item.get("command", "")
                tokens = list(item["tokens"])
                is_plain_command = bool(cmd) and not cmd.startswith("@") and tokens and tokens[-1] == "enter"
                verify_input = args.verify_input and not args.no_verify_input and is_plain_command

                def _send_with_recovery(toks, label, fail_frame=True):
                    nonlocal wid
                    last_exc = None
                    for attempt in range(4):
                        try:
                            wid = wait_window(env, proc.pid, timeout_ms=15000)
                        except Exception:
                            pass
                        try:
                            client.activate(wid, strict=False)
                            client.send_tokens(wid, toks, args.key_delay_ms)
                            return
                        except Exception as exc:
                            last_exc = exc
                            time.sleep(0.35)
                            try:
                                wid = wait_window(env, proc.pid, timeout_ms=15000)
                            except Exception:
                                pass
                    # Last-resort: window exists but focus is flaky; try non-strict
                    # activation and send once if the target window is still present.
                    try:
                        wid2 = wait_window(env, proc.pid, timeout_ms=20000)
                        if wid2 is not None:
                            wid = wid2
                            client.activate(wid, strict=False)
                            client.send_tokens(wid, toks, args.key_delay_ms)
                            return
                    except Exception as exc:
                        last_exc = exc
                    frame = steps_dir / f"{item['id']}-{label}-input-failed.png"
                    if fail_frame:
                        try:
                            capture(env, wid, frame)
                        except Exception:
                            try:
                                subprocess.run(["import", "-window", "root", str(frame)], env=env, capture_output=True, timeout=5)
                            except Exception:
                                pass
                    raise RuntimeError(
                        f"input failed at step {idx}/{len(all_items)} {item['id']} "
                        f"command={cmd!r}: {last_exc}; frame={frame}"
                    )

                if verify_input:
                    def _send_cmd(toks, label):
                        _send_with_recovery(toks, label, fail_frame=True)
                    _send_cmd(tokens[:-1], "type")
                    prof(f"typed-send-{item['id']}")
                    typed_frame = steps_dir / f"{item['id']}-typed.png"
                    typed_meta = stable_capture(env, wid, typed_frame, previous_hash,
                                                args.settle_interval_ms, args.settle_timeout_ms, pid=proc.pid)
                    remember_window(typed_meta, env, proc.pid)
                    wid = int(typed_meta["window"], 16)
                    prof(f"typed-capture-{item['id']}")
                    candidates = ocr_typed_candidates(typed_frame)
                    prof(f"typed-ocr-{item['id']}")
                    ocr_text = " | ".join(candidates)
                    ok = (any(typed_command_matches(cmd, c) for c in candidates) or
                          glyph_typed_command_matches(cmd, typed_frame))
                    input_verify.append({"attempt": 1, "frame": typed_frame.name, "ocr": ocr_text,
                                         "candidates": candidates, "ok": ok})
                    if not ok:
                        # Clear with backspaces only. Escape can put the game
                        # into a transient state; a previous retry retyped into
                        # that state and the final character was corrupted.
                        ok2 = False
                        typed_frame2 = None
                        ocr_text2 = ocr_text
                        for retry in range(2, 4):
                            try:
                                wid = wait_window(env, proc.pid, timeout_ms=5000)
                            except Exception:
                                pass
                            for _ in range(len(tokens) + 20):
                                try:
                                    client.activate(wid, strict=False)
                                    client.send_tokens(wid, ["BackSpace"], args.key_delay_ms)
                                except Exception:
                                    try: wid = wait_window(env, proc.pid, timeout_ms=5000)
                                    except Exception: pass
                                    break
                            time.sleep(0.2)
                            _send_cmd(tokens[:-1], f"retry{retry}-type")
                            typed_frame2 = steps_dir / f"{item['id']}-typed-retry{retry}.png"
                            retry_meta = stable_capture(env, wid, typed_frame2, typed_meta["sha256"],
                                                        args.settle_interval_ms, args.settle_timeout_ms, pid=proc.pid)
                            remember_window(retry_meta, env, proc.pid)
                            wid = int(retry_meta["window"], 16)
                            candidates2 = ocr_typed_candidates(typed_frame2)
                            ocr_text2 = " | ".join(candidates2)
                            ok2 = (any(typed_command_matches(cmd, c) for c in candidates2) or
                                   glyph_typed_command_matches(cmd, typed_frame2))
                            input_verify.append({"attempt": retry, "frame": typed_frame2.name, "ocr": ocr_text2,
                                                 "candidates": candidates2, "ok": ok2})
                            if ok2:
                                break
                        if not ok2:
                            raise RuntimeError(
                                f"typed command OCR mismatch at step {item['id']} cmd={cmd!r} ocr={ocr_text2!r}; frame={typed_frame2}"
                            )
                    _send_with_recovery(["enter"], "enter", fail_frame=True)
                    prof(f"enter-send-{item['id']}")
                else:
                    _send_with_recovery(tokens, "send", fail_frame=True)
            frame = steps_dir / f"{item['id']}.png"
            meta = stable_capture(env, wid, frame, previous_hash,
                                  args.settle_interval_ms, args.settle_timeout_ms, pid=proc.pid)
            remember_window(meta, env, proc.pid)
            wid = int(meta["window"], 16)
            prof(f"final-capture-{item['id']}")
            previous_hash = meta["sha256"]
            records.append({"id": item["id"],
                            "kind": "replay" if is_replay else "command",
                            "command": item.get("command", ""),
                            "frame": f"steps/{item['id']}.png",
                            "taste_presses": taste_presses,
                            "taste_debug": taste_debug,
                            "input_verify": input_verify,
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
        frame_rel = record.get("frame")
        if not frame_rel:
            continue
        frame = out / frame_rel
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
    if args.engine_load and not args.no_dosbox:
        raise SystemExit("--engine-load requires --no-dosbox; use --replay-commands-file for DOSBox parity")
    if args.engine_load and not Path(args.engine_load).is_file():
        raise SystemExit(f"engine state not found: {args.engine_load}")
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    seq = load_sequence(args)
    (out / "sequence.json").write_text(
        json.dumps(seq, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    report: dict = {"name": seq.get("name", ""), "commands": len(seq["commands"])}
    report_path = out / "parity-report.json"
    try:
        if not args.no_engine:
            report["engine"] = run_engine(args, seq, out)
        if not args.no_dosbox:
            report["dosbox"] = run_dosbox(args, seq, out)
        try:
            run_ocr(args, seq, out, report)
        except Exception as exc:
            report["ocr_error"] = str(exc)
    except Exception as exc:
        report["harness_failure"] = str(exc)
    finally:
        report_path.write_text(
            json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"full-playthrough report: {report_path}")
    if report.get("harness_failure"):
        print(f"harness failure: {report['harness_failure']}", file=sys.stderr)
        return 1
    ok = True
    if not args.no_engine and not report.get("engine", {}).get("checkpoints_ok", True):
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
