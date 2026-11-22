#!/usr/bin/env python3
"""Candidate-driven semantic check of a DOSBox frame.

This is not general OCR. It scores the engine's own response lines against the
original DOS text pixels using the original proportional FON glyph masks. The
result is a confidence-ranked list of candidates for each text row; it is used
as parity evidence, not as pixel-identity proof.

Usage:
  parity_ocr.py SCREENSHOT CANDIDATES_FILE [FILE ...]
  parity_ocr.py SCREENSHOT --candidates-json STEP.json [--json OUT] [--step ID]
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

DEFAULT_FONT = Path("/home/bob/Downloads/Hexuma/8X8PROP.FON")
WIDTH, HEIGHT = 320, 200
TEXT_TOP, TEXT_BOTTOM = 100, 193
X_STARTS = range(20, 43)
# Text in DOS captures is mostly olive/yellow on dark background, but
# antialiasing and capture differences introduce nearby shades. Accept exact
# palette hits and a tolerant olive/bright heuristic.
TEXT_COLORS = {
    (146, 146, 93), (158, 162, 109), (174, 174, 125),
    (231, 235, 207), (243, 243, 231),
}


def is_text_pixel(r: int, g: int, b: int) -> bool:
    if (r, g, b) in TEXT_COLORS:
        return True
    # Olive/yellow antialiased text: red/green dominant, blue suppressed.
    if r >= 110 and g >= 100 and b <= 210 and (r + g) >= 2 * b + 30:
        # Exclude very dark/brown UI noise.
        if r + g + b >= 280:
            return True
    # Bright near-white text edges.
    if r >= 210 and g >= 210 and b >= 170:
        return True
    return False


def load_font(path: Path):
    data = path.read_bytes()
    if len(data) != 256 + 256 * 62:
        raise ValueError(f"unexpected FON size {len(data)}")
    glyphs = []
    for code in range(256):
        rec = data[256 + code * 62:256 + (code + 1) * 62]
        rows = []
        for dy in range(8):
            width = min(rec[0], 7)
            rows.append(tuple(dx for dx in range(width) if rec[4 + dy * 7 + dx]))
        glyphs.append((rows, rec[0]))
    return glyphs


def load_screen(path: Path):
    raw = subprocess.check_output(["convert", str(path), "-depth", "8", "rgb:-"])
    rows = []
    for y in range(HEIGHT):
        base = y * WIDTH * 3
        row = bytearray(WIDTH)
        for x in range(WIDTH):
            i = base + x * 3
            row[x] = 1 if is_text_pixel(raw[i], raw[i + 1], raw[i + 2]) else 0
        rows.append(bytes(row))
    return rows


def candidates_from_files(paths: list[str]) -> list[str]:
    out: list[str] = []
    for name in paths:
        for line in Path(name).read_text(errors="replace").splitlines():
            line = line.strip().lstrip("> ")
            if line and not line[0].isdigit():
                out.append(line)
    return list(dict.fromkeys(out))


def candidates_from_json(path: Path, step: str | None) -> list[str]:
    text = path.read_text(encoding="utf-8")
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        rows = [json.loads(line) for line in text.splitlines() if line.strip()]
        if step is not None:
            rows = [row for row in rows if str(row.get("step")) == str(step)]
        data = {"response": [line for row in rows
                             for line in (row.get("response", []) + row.get("look", []))]}
    if step is not None and isinstance(data, dict) and step in data:
        data = data[step]
    out: list[str] = []
    for key in ("response", "look", "choices"):
        for line in data.get(key, []) or []:
            line = str(line).strip()
            if line:
                out.append(line)
    return list(dict.fromkeys(out))


def renderable(line: str, glyphs):
    chars = []
    for ch in line:
        try:
            code = ch.encode("cp850")[0]
        except UnicodeEncodeError:
            continue
        if glyphs[code][1] == 0:
            continue
        chars.append(glyphs[code])
    return chars


def score_candidate(chars, x0: int, y0: int, screen) -> dict:
    x = x0
    matched = expected = 0
    for rows, advance in chars:
        for dy, points in enumerate(rows):
            for dx in points:
                expected += 1
                px = x + dx
                py = y0 + dy
                if px < WIDTH and screen[py][px]:
                    matched += 1
                else:
                    # Antialiased DOS text can shift by a pixel; allow a small
                    # neighborhood hit but only as weak evidence.
                    hit = False
                    for ny in range(max(TEXT_TOP, py - 1), min(TEXT_BOTTOM, py + 2)):
                        if hit:
                            break
                        for nx in range(max(0, px - 1), min(WIDTH, px + 2)):
                            if screen[ny][nx]:
                                matched += 0.7
                                hit = True
                                break
        x += advance
    end = min(x, WIDTH)
    ink = sum(sum(screen[y0 + dy][x0:end]) for dy in range(8))
    unexplained = max(0, ink - int(matched))
    coverage = matched / expected if expected else 0.0
    precision = matched / (matched + unexplained) if matched + unexplained else 0.0
    return {"x": x0, "y": y0, "matched": round(matched, 2), "expected": expected,
            "unexplained": unexplained, "coverage": round(coverage, 4),
            "precision": round(precision, 4),
            "confidence": round(coverage * precision, 4)}


def best_match(line: str, glyphs, screen) -> dict:
    chars = renderable(line, glyphs)
    if not chars:
        return {"line": line, "confidence": 0.0}
    best = {"line": line, "confidence": -1.0}
    for y in range(TEXT_TOP, TEXT_BOTTOM):
        for x in X_STARTS:
            result = score_candidate(chars, x, y, screen)
            if result["confidence"] > best["confidence"]:
                best = {"line": line, **result}
    return best


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("screen")
    parser.add_argument("candidates", nargs="*")
    parser.add_argument("--candidates-json")
    parser.add_argument("--step")
    parser.add_argument("--json")
    parser.add_argument("--font", default=os.environ.get("HEXUMA_FONT", str(DEFAULT_FONT)))
    args = parser.parse_args(argv)

    glyphs = load_font(Path(args.font))
    screen = load_screen(Path(args.screen))
    if args.candidates_json:
        lines = candidates_from_json(Path(args.candidates_json), args.step)
    elif args.candidates:
        lines = candidates_from_files(args.candidates)
    else:
        parser.error("provide candidate files or --candidates-json")

    ranked = sorted((best_match(line, glyphs, screen) for line in lines),
                    key=lambda row: row["confidence"], reverse=True)
    result = {"screen": args.screen, "step": args.step,
              "candidates": len(lines), "matches": ranked}
    if args.json:
        Path(args.json).write_text(
            json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    else:
        for row in ranked:
            print(f"{row['confidence']:.4f} y={row.get('y', '-')} "
                  f"x={row.get('x', '-')} {row['line']!r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
