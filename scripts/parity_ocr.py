#!/usr/bin/env python3
"""Match original DOS frames against known engine text lines.

This is not general OCR.  It uses the original 8x8 proportional FON glyph masks
to score every supplied candidate string at each text line position.  Supplying
the engine's own output as candidates makes semantic DOSBox parity checkable:
a high match score at a screen row means the original displays that line.

Usage:
  parity_ocr.py SCREENSHOT CANDIDATES_FILE [CANDIDATES_FILE ...]
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

DEFAULT_FONT = Path("/home/bob/Downloads/Hexuma/8X8PROP.FON")
WIDTH, HEIGHT = 320, 200
TEXT_TOP, TEXT_BOTTOM, TEXT_STEP = 123, 192, 7
X_STARTS = range(24, 32)
Y_OFFSETS = (-1, 0, 1)


def load_font(path: Path):
    data = path.read_bytes()
    if len(data) != 256 + 256 * 62:
        raise ValueError(f"unexpected FON size {len(data)}")
    records = [data[256 + c * 62:256 + (c + 1) * 62] for c in range(256)]
    glyphs = []
    for c, rec in enumerate(records):
        rows = []
        for dy in range(8):
            bits = rec[4 + dy * 7:4 + dy * 7 + 7]
            rows.append(tuple((dx, bool(bits[dx])) for dx in range(7) if bits[dx]))
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
            r, g, b = raw[i], raw[i + 1], raw[i + 2]
            row[x] = 1 if r > 80 and abs(r - g) < 14 and 18 <= r - b <= 75 else 0
        rows.append(bytes(row))
    return rows


def candidates(paths: list[str]) -> list[str]:
    out: list[str] = []
    for name in paths:
        for line in Path(name).read_text(errors="replace").splitlines():
            line = line.strip()
            if not line:
                continue
            if "XTEST_SCRIPT" in name or Path(name).name == "input-script.txt":
                for entry in line.split(";"):
                    if ":" not in entry:
                        continue
                    cmd = entry.split(":", 1)[1]
                    for token in cmd.replace(",", " ").split():
                        if token == "enter":
                            continue
                        out.append(token)
            out.append(line)
    # Preserve order, remove duplicates.
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


def score_line(chars, x0: int, y0: int, screen) -> float:
    x = x0
    score = 0
    matched_ink = 0
    for rows, advance in chars:
        if x + 7 > WIDTH:
            break
        for dy in range(8):
            screen_row = screen[y0 + dy]
            for dx, ink in rows[dy]:
                actual = screen_row[x + dx]
                if ink:
                    if actual:
                        score += 5
                        matched_ink += 1
                    else:
                        score -= 3
                elif not actual:
                    score += 1
                else:
                    score -= 3
        x += advance
    # Penalise screen ink left unexplained by this candidate.  Without this a
    # short menu fragment such as "8." can win simply by being exact.
    total_ink = 0
    for dy in range(8):
        total_ink += sum(screen[y0 + dy][24:300])
    return score - 3 * (total_ink - matched_ink)


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage: parity_ocr.py SCREENSHOT CANDIDATES_FILE [FILE...]", file=sys.stderr)
        return 2
    font_path = Path(os.environ.get("HEXUMA_FONT", str(DEFAULT_FONT)))
    font = load_font(font_path)
    screen = load_screen(Path(argv[1]))
    lines = candidates(argv[2:])
    rendered = [(line, renderable(line, font)) for line in lines]
    for y in range(TEXT_TOP, TEXT_BOTTOM, TEXT_STEP):
        best = (-10**9, "", 0, 0)
        for line, chars in rendered:
            if not chars:
                continue
            for x in X_STARTS:
                for yo in Y_OFFSETS:
                    sc = score_line(chars, x, y + yo, screen)
                    if sc > best[0]:
                        best = (sc, line, x, y + yo)
        print(f"y={y:3d} score={best[0]:5d} x={best[2]:2d} text={best[1]!r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
