#!/usr/bin/env bash
set -euo pipefail

if [ -n "${ZIG:-}" ]; then
  ZIG="$ZIG"
elif command -v zig >/dev/null 2>&1; then
  ZIG="$(command -v zig)"
else
  ZIG="/tmp/opencode/toolchain/zig-x86_64-linux-0.15.2/zig"
fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT="${1:-/home/bob/Downloads/Hexuma}"

cd "$ROOT"
"$ZIG" build

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

"$ROOT/zig-out/bin/hexuma" extract --input "$INPUT" --output "$OUT"

png_count="$(find "$OUT/images" -maxdepth 1 -name '*.png' | wc -l)"
wav_count="$(find "$OUT/audio" -maxdepth 1 -name '*.wav' | wc -l)"

test "$png_count" -eq 263
test "$wav_count" -eq 7
test -s "$OUT/data/game.json"
test -s "$OUT/data/texts.json"
test -s "$OUT/data/code_strings.json"
test -s "$OUT/data/action_menu.json"
test -s "$OUT/data/overlays.json"
test -s "$OUT/data/initial_flags.json"
test -s "$OUT/data/vors_overrides.json"
test -s "$OUT/data/vors_records.json"
test -s "$OUT/lua/game.lua"
test -s "$OUT/lua/texts.lua"
test -s "$OUT/lua/code_strings.lua"
test -s "$OUT/lua/action_menu.lua"
test -s "$OUT/lua/locale.lua"
test "$(find "$OUT/images" -maxdepth 1 -name '*.raw' | wc -l)" -eq 263

python3 - "$OUT/data/game.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(data["rooms"]) == 240
assert len(data["verbs"]) == 346
assert len(data["vocabulary"]) >= 1000
assert len(data["pictures"]) == 271
assert len(data["click_regions"]) >= 400
assert len(data["vocabulary_5"]) > 300
assert len(data["vocabulary_6"]) > 500
entry = data["vocabulary"][8]
assert entry["word"] == "eingangshalle"
assert entry["room_gate"] == 1
assert entry["text_b"] == 126
PY

python3 - "$OUT/data/texts.json" <<'PY'
import json, sys
texts = {t["id"]: t["text"] for t in json.load(open(sys.argv[1], encoding="utf-8"))["texts"]}
assert texts[126].startswith("In der Eingangshalle")
assert texts[35013].startswith("Es handelt sich um ein kleines Fläschchen")
PY

python3 - "$OUT/data/code_strings.json" <<'PY'
import json, sys
pools = {p["name"]: [m["text"] for m in p["messages"]] for p in json.load(open(sys.argv[1], encoding="utf-8"))["pools"]}
assert pools["take"][0] == "Bitte geben Sie genau an, was Sie nehmen wollen."
assert pools["parser"][0] == "Ich kann Ihren Satz leider nicht verstehen."
assert pools["examine"][4] == "hat keine besonderen Merkmale."
assert pools["move"][1] == "Das ist von hier aus nicht erreichbar."
PY

python3 - "$OUT/data/action_menu.json" <<'PY'
import json, sys
rooms = {r["room"]: r["actions"] for r in json.load(open(sys.argv[1], encoding="utf-8"))["rooms"]}
assert rooms[1][0] == "Schau das Gemälde an"
assert rooms[5][-1] == "Geh nach Süden"
PY

python3 - "$OUT/data/overlays.json" "$OUT/data/initial_flags.json" <<'PY'
import json, sys
frames = json.load(open(sys.argv[1], encoding="utf-8"))["frames"]
assert len(frames) == 57
assert frames[0] == {"scene": 1, "file": "fr00101.seq", "cond": "byte(0x5e31)==0", "source_line": 145}
assert any(f["cond"] == "byte(0xf36c)==0||byte(0xf36c)==3" for f in frames)
initial = json.load(open(sys.argv[2], encoding="utf-8"))
assert str(0xf44e) in initial["bytes"] and initial["bytes"][str(0xf44e)] == 1
assert str(0xf452) in initial["dwords"] and initial["dwords"][str(0xf452)] == 0xc5
PY

"$ROOT/zig-out/bin/hexuma" overlays --room 1 --extracted "$OUT" | grep -qx 'fr00101.seq'
"$ROOT/zig-out/bin/hexuma" overlays --room 1 --extracted "$OUT" | grep -qx 'fr00107.seq'

python3 - "$OUT/data/vors_overrides.json" "$OUT/data/vors_records.json" <<'PY'
import json, sys
overrides = json.load(open(sys.argv[1], encoding="utf-8"))["overrides"]
counts = json.load(open(sys.argv[2], encoding="utf-8"))["counts"]
assert len(overrides) == 199
assert counts[35] == 8 and counts[40] == 11 and counts[123] == 5
assert any(o["record"] == 35 and o["slot"] == 4 and o["cond"] == "room==88" for o in overrides)
assert any(o["cond"] == "byte(0x5422)==1&&room==189&&room==dword(0x4a62)" for o in overrides)
PY

"$ROOT/zig-out/bin/hexuma" vors --picture 35 --room 88 --extracted "$OUT" | grep -q $'^4\tKlettere rauf\t '
"$ROOT/zig-out/bin/hexuma" vors --picture 40 --room 147 --extracted "$OUT" | grep -q $'^5\tGeh nach Osten\tGehe nach Süden'

"$ROOT/zig-out/bin/hexuma" run "$OUT/lua/init.lua"

printf 'quit\n' | "$ROOT/zig-out/bin/hexuma" play --extracted "$OUT" | grep -q 'Du bist hier'
printf 'quit\n' | "$ROOT/zig-out/bin/hexuma" play --lang en --extracted "$OUT" --choices | grep -q 'You are here'

echo "smoke test passed: $png_count PNG, $wav_count WAV, semantic data, DE/EN engine"
