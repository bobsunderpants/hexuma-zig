#!/usr/bin/env python3
"""Parse fly-state records emitted by the patched HEXPRG.EXE."""
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

FIELDS = [
    ("tick", "0xf33b"),
    ("jar_state", "0x5f1e"),
    ("one_shot", "0xf33c"),
    ("killed", "0xf33a"),
    ("h3", "0xf338"),
    ("h2", "0xf336"),
    ("h1", "0xf334"),
    ("h0", "0xf332"),
    ("sugar", "0x476e"),
    ("flypaper", "0x4724"),
    ("jar", "0x4712"),
    ("fly", "0x46fe"),
    ("object2", "0xbe5e"),
    ("object", "0xbe5c"),
    ("verb", "0xcac2"),
    ("room", "0xbe1b"),
]
RECORD_SIZE = 2 * (len(FIELDS) + 1)
MARKER = b"\x5a\xa5"


def signed(value: int) -> int:
    return value - 0x10000 if value >= 0x8000 else value


def parse(data: bytes) -> list[dict[str, int]]:
    records: list[dict[str, int]] = []
    start = 0
    while True:
        pos = data.find(MARKER, start)
        if pos < 0 or pos < RECORD_SIZE - 2:
            break
        values = struct.unpack("<" + "H" * len(FIELDS), data[pos - 2 * len(FIELDS):pos])
        record: dict[str, int] = {}
        for (name, _), value in zip(FIELDS, values):
            record[name] = value
            record[name + "_s"] = signed(value)
        records.append(record)
        start = pos + 2
    return records


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} dosbox-stdout.txt")
    data = Path(sys.argv[1]).read_bytes()
    for record in parse(data):
        print(json.dumps(record, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
