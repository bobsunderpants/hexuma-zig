#!/usr/bin/env python3
"""Patch original HEXPRG.EXE to store last FUN_1c89_a3d8 text id in a cave word.

Memory-marker only (no DOS INT21h). Read dbg word from DOSBox-X debugger/memdump.

Hooks FUN_1c89_a3d8 (TEXT*.REL print, __stdcall16far, param_1=text id at [bp+6]
after prologue) and writes "TXT <id>\r\n" records. Uses a code cave in CODE_18
(same segment, no MZ relocation needed). Keeps original bytes executable.

This is for debugging/parity only; do not distribute patched binaries.
"""
from __future__ import annotations

import argparse, struct
from pathlib import Path

HDR_SIZE = 0x6600
LOAD = 0x10000
HOOK_LINEAR = 0x26C68  # FUN_1c89_a3d8
CAVE_LINEAR = 0x29ADD  # 131 zero bytes in CODE_18
RET_LINEAR = HOOK_LINEAR + 7
ORIG = bytes.fromhex("5589e581ec2806")  # push bp; mov bp,sp; sub sp,0628


def linear_to_file(lin: int) -> int:
    return lin - LOAD + HDR_SIZE


def u16(x: int) -> bytes:
    return struct.pack("<H", x & 0xFFFF)


def s16(x: int) -> bytes:
    return struct.pack("<h", x)


def patch(src: Path, dst: Path) -> None:
    """Log FUN_1c89_a3d8 text ids to a small CS cave ring buffer.

    Layout at dbg_off (linear CAVE_LINEAR+dbg_off):
      +0 u16 count (total calls, wraps)
      +2 u16 idx   (next slot 0..15)
      +4 u16[16]   last 16 text ids
    No DOS INT21h.
    """
    b = bytearray(src.read_bytes())
    hook_off = linear_to_file(HOOK_LINEAR)
    cave_off = linear_to_file(CAVE_LINEAR)
    if b[hook_off:hook_off+7] != ORIG:
        raise SystemExit(f"hook bytes mismatch at {hex(hook_off)}: {b[hook_off:hook_off+8].hex()}")
    if any(b[cave_off+i] != 0 for i in range(128)):
        raise SystemExit(f"cave not empty at {hex(cave_off)}")

    asm = bytearray()
    # ax = param1 (text id) - save to BDA 0040:00F0
    asm += b"\x55\x89\xe5\x8b\x46\x06\x5d"  # get param1
    asm += b"\x1e\x50"                      # push ds; push ax
    asm += b"\x68\x40\x00\x1f"              # push 0040; pop ds
    asm += b"\xa3\xf0\x00"                  # mov [00F0],ax
    asm += b"\x58\x1f"                      # pop ax; pop ds
    asm += ORIG
    jmp_pos = len(asm); asm += b"\xe9" + u16(0)
    if len(asm) > 128:
        raise SystemExit(f"cave too large: {len(asm)}")
    struct.pack_into('<h', asm, jmp_pos+1, RET_LINEAR - (CAVE_LINEAR + jmp_pos + 3))
    b[cave_off:cave_off+len(asm)] = asm
    b[hook_off:hook_off+7] = b"\xe9" + s16(CAVE_LINEAR - (HOOK_LINEAR + 3)) + b"\x90\x90\x90\x90"
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(b)
    print(f"patched {src} -> {dst}")
    print(f"hook @{hex(HOOK_LINEAR)} -> cave @{hex(CAVE_LINEAR)} size {len(asm)}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("src", nargs="?", default="/home/bob/Downloads/Hexuma/HEXPRG.EXE")
    ap.add_argument("dst", nargs="?", default="/tmp/opencode/hexuma-debug/HEXPRG.EXE")
    args = ap.parse_args()
    patch(Path(args.src), Path(args.dst))
