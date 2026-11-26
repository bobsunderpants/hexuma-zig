#!/usr/bin/env python3
"""Build HEXPRG.EXE that appends fly-global records on every fly tick."""
from __future__ import annotations

import shutil
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = Path("/home/bob/Downloads/Hexuma")
DEST = ROOT / ".tmp_fly_append_game"

HEADER = 0x6600
FLY_SEG = 0x349
FLY_OFF = 0x2854
CAVE_SEG = 0xC89
CAVE_OFF = 0xD24D
CAVE_LEN = 131
ORIGINAL = bytes.fromhex("a136f3a338f3a134f3")


def file_offset(segment: int, offset: int) -> int:
    return HEADER + segment * 16 + offset


def main() -> int:
    if DEST.exists():
        shutil.rmtree(DEST)
    shutil.copytree(SOURCE, DEST)

    asm = ROOT / "scripts" / "fly_debug_append_routine.s"
    obj = ROOT / ".fly_debug_append.o"
    raw = ROOT / ".fly_debug_append.bin"
    subprocess.run(["as", "--32", "-o", str(obj), str(asm)], check=True)
    subprocess.run(["objcopy", "-O", "binary", "--only-section=.text", str(obj), str(raw)], check=True)
    routine = bytearray(raw.read_bytes())
    routine.extend(ORIGINAL)
    routine.append(0xCB)  # retf
    if len(routine) > CAVE_LEN:
        raise SystemExit(f"debug routine too large: {len(routine)}")

    exe = DEST / "HEXPRG.EXE"
    data = bytearray(exe.read_bytes())

    patch_at = file_offset(FLY_SEG, FLY_OFF)
    if bytes(data[patch_at:patch_at + 9]) != ORIGINAL:
        raise SystemExit(f"unexpected fly entry bytes: {bytes(data[patch_at:patch_at + 9]).hex()}")

    data[patch_at:patch_at + 9] = bytes.fromhex("9a4dd2890c") + b"\x90" * 4

    reloc_offset = FLY_OFF + 3
    reloc_at = struct.unpack_from("<H", data, 0x18)[0]
    reloc_count = struct.unpack_from("<H", data, 0x06)[0]
    entry_at = reloc_at + 4 * reloc_count
    if entry_at + 4 > HEADER:
        raise SystemExit(f"no relocation-table slack at {entry_at:x}")
    struct.pack_into("<HH", data, entry_at, reloc_offset, FLY_SEG)
    struct.pack_into("<H", data, 0x06, reloc_count + 1)

    cave_at = file_offset(CAVE_SEG, CAVE_OFF)
    if any(data[cave_at:cave_at + len(routine)]):
        raise SystemExit("debug routine cave is not zero-filled")
    data[cave_at:cave_at + len(routine)] = routine
    exe.write_bytes(data)
    (DEST / "FLYDBG.TXT").write_bytes(b"")
    print(f"patched {exe} ({len(routine)} debug bytes, reloc {reloc_offset:x}:{FLY_SEG:x})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
