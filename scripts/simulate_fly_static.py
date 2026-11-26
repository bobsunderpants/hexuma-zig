#!/usr/bin/env python3
"""Static fly simulation from extracted LAND data and overlay-unit 11 rules.

This is a diagnostic only: it evaluates the native tick gate from
`overlay_rules.json` against a Zig trace, then replays the fly movement loop
from HEXPRG.EXE segment 0x349:0x2854-0x2995. Runtime debug dumps remain
authoritative; this script exists to generate hypotheses for those probes.
"""
from __future__ import annotations

import argparse
import json
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def norm(text: str) -> str:
    text = text.lower().replace("ß", "ss")
    return "".join(
        c for c in unicodedata.normalize("NFKD", text)
        if not unicodedata.combining(c)
    )


def signed(value: int) -> int:
    value &= 0xFFFF
    return value - 0x10000 if value >= 0x8000 else value


class Evaluator:
    def __init__(self, game: dict, trace_row: dict):
        self.verbs = {
            norm(entry["name"]): int(entry["id"])
            for entry in game.get("verbs", [])
        }
        cmd = trace_row.get("command", "")
        words = norm(cmd).split()
        self.verb = self.verbs.get(words[0], 0) if words else 0
        if self.verb == 0 and len(words) > 1:
            self.verb = self.verbs.get(" ".join(words[:2]), 0)
        state = trace_row.get("state", {})
        self.vars = {
            "verb": self.verb,
            "object": int(state.get("object", 0)),
            "object2": int(state.get("object2", 0)),
            "room": int(state.get("room", 0)),
        }
        self.flags = dict(state.get("flags", {}))
        self.flags.update(state.get("words", {}))

    def value(self, node: dict) -> int:
        if "n" in node:
            return int(node["n"])
        if "v" in node:
            return int(self.vars.get(node["v"], 0))
        if "flag" in node:
            return signed(int(self.flags.get(node["flag"], 0)))
        if "u" in node:
            arg = self.value(node["a"])
            return int(not arg) if node["u"] == "!" else -arg
        if "b" in node:
            op = node["b"]
            left = self.value(node["a"])
            right = self.value(node["c"])
            if op == "&&":
                return int(bool(left) and bool(right))
            if op == "||":
                return int(bool(left) or bool(right))
            if op == "==":
                return int(left == right)
            if op == "!=":
                return int(left != right)
            if op == "<":
                return int(left < right)
            if op == ">":
                return int(left > right)
            if op == "<=":
                return int(left <= right)
            if op == ">=":
                return int(left >= right)
        return 0


def load_trace(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("trace")
    parser.add_argument("--initial-fly", type=int, default=9)
    parser.add_argument("--flypaper", type=int, default=10)
    parser.add_argument("--jar", type=int, default=65535)
    parser.add_argument("--sugar", type=int, default=-314)
    args = parser.parse_args()

    trace = load_trace(Path(args.trace))
    game = json.loads((ROOT / "extracted/data/game.json").read_text())
    land = json.loads((ROOT / "extracted/data/tables/LAND.json").read_text())["values"]
    rules = json.loads((ROOT / "extracted/data/overlay_rules.json").read_text())
    unit = next(u for u in rules["units"] if u["unit"] == 11)
    tick_gate = next(r["when"] for r in unit["rules"] if r["group"] == 181)

    fly = args.initial_fly
    history = [args.initial_fly] * 4
    counter = 1
    for row in trace:
        if row.get("kind") != "command":
            continue
        state = row.get("state", {})
        room = int(state.get("room", 0))
        ran = bool(Evaluator(game, row).value(tick_gate))
        old = fly
        landed = ""
        if ran:
            history = [history[1], history[2], history[3], old]
            if old > 0:
                counter = 1
                while counter != 7:
                    idx = (old - 1) * 7 + counter
                    value = land[idx] if 0 <= idx < len(land) else 0
                    valid = (0 < value < 5) or (5 < value < 12)
                    if valid and value != args.flypaper:
                        fly = value
                        if value not in history:
                            counter = 7
                    if counter == 7:
                        break
                    counter += 1
            if fly == old and room == fly:
                landed = "1259"
            elif fly != old and room == old:
                landed = "1256"
        if landed:
            tick = state.get("flags", {}).get("0xf33b")
            print(f"step {row['step']:3}: {landed} room={room} "
                  f"fly {old}->{fly} timing={tick} {row.get('command', '')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
