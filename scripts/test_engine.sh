#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/zig-out/bin/hexuma"
EXTRACTED="${1:-$ROOT/extracted}"

run() {
  printf '%s\nquit\n' "$1" | "$BIN" play --extracted "$EXTRACTED" "${@:2}"
}

# German original vocabulary path.
out="$(run 'gehe süden' --choices)"
grep -q 'Du gehst süden' <<<"$out"
grep -q 'Gehe nach Norden ins Haus' <<<"$out"

# REA-derived VORS runtime overrides are applied to the start screen.
out="$(run 'untersuche kamin' --choices)"
grep -q 'Schließe die Haustüre' <<<"$out"
grep -q 'Gehe in die Bibliothek' <<<"$out"
grep -q 'Schau das Gemälde an' <<<"$out"
grep -q 'Nimm den Zettel' <<<"$out"
# The VORS portion precedes the OBLISTE menu in the choice list; the menu
# legitimately contains the original "Öffne die Haustür" label.
vors_only="$(sed -n '/^  1\./,/^  9\./p' <<<"$out")"
if grep -q 'Öffne die Haustür' <<<"$vors_only"; then
  echo 'stale VORS label was not overridden' >&2
  exit 1
fi

# REA-decoded open/close state machine (0x1755:0x31a1). The front door starts
# open, toggles state, and non-openable objects use the exact code strings.
out="$(printf 'öffne haustüre\nschließe haustüre\nschließe haustüre\nöffne kamin\nquit\n' | "$BIN" play --extracted "$EXTRACTED")"
grep -q 'haustüre ist bereits offen.' <<<"$out"
grep -q 'haustüre ist jetzt zu.' <<<"$out"
grep -q 'haustüre ist bereits zu.' <<<"$out"
grep -q 'kamin kann man nicht öffnen.' <<<"$out"

# Original OBNWOR/TEXT*.REL description is used for German lookups.
out="$(run 'untersuche gemälde')"
grep -q 'Ein Gemälde von dieser Größe' <<<"$out"

# The no-object examine path reproduces the original room object scan and the
# container state suffix from the same code-string pool.
out="$(run 'untersuche')"
grep -q 'Hier befinden sich eingangshalle, treppe' <<<"$out"
out="$(run 'untersuche haustüre')"
grep -q 'ist offen und enthält nichts.' <<<"$out"
out="$(printf 'schließe haustüre\nuntersuche haustüre\nquit\n' | "$BIN" play --extracted "$EXTRACTED")"
grep -q 'haustüre ist jetzt zu.' <<<"$out"
grep -q 'Ein ist zu.' <<<"$out"

# English alternative path uses the same verb ids and original VORS labels.
out="$(run 'go south' --lang en --choices)"
grep -q 'You go south' <<<"$out"
grep -q 'Go North into the House' <<<"$out"

# Point-and-click labels and the text parser share one dispatcher.
out="$(run '1' --lang en --choices)"
grep -q -E 'You (go|see)|That is not possible' <<<"$out"

# Exact German message fragments recovered from HEXPRG.EXE.
out="$(run 'nimm')"
grep -q 'Bitte geben Sie genau an, was Sie nehmen wollen.' <<<"$out"
out="$(printf 'nimm wand\nnimm wand\nquit\n' | "$BIN" play --extracted "$EXTRACTED")"
grep -q 'wand haben Sie schon.' <<<"$out"
out="$(run 'quatsch')"
grep -q 'Ich kann Ihren Satz leider nicht verstehen.' <<<"$out"

# Original drop/inventory/ignite message pools and class-checked take.
out="$(printf 'nimm wand\ninventur\nlege wand\nlege wand\ninventur\nzünde kamin an\nquit\n' | "$BIN" play --extracted "$EXTRACTED")"
grep -q 'Sie haben wand.' <<<"$out"
grep -q 'wand liegt jetzt hier auf dem Boden.' <<<"$out"
grep -q 'wand haben Sie ja gar nicht!' <<<"$out"
grep -q 'Sie haben nichts.' <<<"$out"
grep -q 'Das kann man nicht anzünden.' <<<"$out"
out="$(run 'nimm kamin')"
grep -q 'kamin können Sie nicht nehmen!' <<<"$out"

# Conditional FR overlays use the REA-derived startup globals.
out="$("$BIN" overlays --room 1 --extracted "$EXTRACTED")"
grep -qx 'fr00101.seq' <<<"$out"
grep -qx 'fr00103.seq' <<<"$out"
grep -qx 'fr00107.seq' <<<"$out"
if grep -qx 'fr00104.seq' <<<"$out"; then
  echo 'wrong door-state overlay at startup' >&2
  exit 1
fi

# Complete REA-derived VORS runtime override table, including records that
# were missing from the earlier hand-written subset.
out="$("$BIN" vors --picture 35 --room 88 --extracted "$EXTRACTED")"
grep -q $'^4\tKlettere rauf\t $' <<<"$out"
out="$("$BIN" vors --picture 40 --room 147 --extracted "$EXTRACTED")"
grep -q $'^5\tGeh nach Osten\tGehe nach Süden' <<<"$out"
test "$(grep -c $'\tGehe Süd$' <<<"$out")" -eq 0
out="$("$BIN" vors --picture 1 --room 5 --extracted "$EXTRACTED")"
test "$(grep -c $'\tGehe Süd$' <<<"$out")" -eq 10
out="$("$BIN" vors --picture 1 --room 1 --flag 0x5e31=1 --extracted "$EXTRACTED")"
grep -q $'^4\tÖffne die Haustür\tÖffne die Haustür$' <<<"$out"
out="$("$BIN" vors --picture 43 --room 100 --dword 0x4b3a=100 --extracted "$EXTRACTED")"
grep -q $'^1\tSchau den Brontosaurus an\tSchau den Brontosaurus an$' <<<"$out"
out="$("$BIN" vors --picture 123 --room 189 --flag 0x5422=1 --dword 0x4a62=189 --extracted "$EXTRACTED")"
grep -q $'^4\t\tUntersuche das Holzstück$' <<<"$out"

# REA-derived OVR rules: evaluate one original if-block guard once, then apply
# all of its actions in order. Room 170/unit 0 covers all four message ids
# called out in the room-0xaa decompilation.
out="$("$BIN" rules --room 170 --verb 7 --object 0 --flag 0xf428=1 --flag 0xf427=0 --flag 0xf429=1 --flag 0xf42b=0 --extracted "$EXTRACTED")"
grep -q 'msg 0x88ba' <<<"$out"
out="$("$BIN" rules --room 170 --verb 3 --object 575 --flag 0xf429=1 --extracted "$EXTRACTED")"
grep -q 'msg 0x7761' <<<"$out"
out="$("$BIN" rules --room 170 --verb 3 --object 0 --flag 0xf428=1 --flag 0xf427=1 --flag 0xf429=1 --extracted "$EXTRACTED")"
grep -q 'msg 0x77ab' <<<"$out"
out="$("$BIN" rules --room 170 --verb 1 --object 592 --flag 0xf42b=1 --extracted "$EXTRACTED")"
grep -q 'msg 0x88c3' <<<"$out"

# Portable save/load state.
save="$(mktemp)"
original_dir="$(mktemp -d)"
trap 'rm -f "$save"; rm -rf "$original_dir"' EXIT
printf 'nimm wand\nquit\n' | "$BIN" play --extracted "$EXTRACTED" --save "$save" >/dev/null
grep -q '"inventory":\["wand"\]' "$save"
printf 'quit\n' | "$BIN" play --extracted "$EXTRACTED" --load "$save" >/dev/null

# Original .dat/.sav save state: 10839 decimal lines (7 numeric and one string
# field per object, 8 per landscape, plus the scalar finalizer fields) and a
# 0x18d8 + 0x404 byte .sav sibling.
printf 'nimm wand\nquit\n' | "$BIN" play --extracted "$EXTRACTED" --save "$original_dir/00.dat" >/dev/null
test "$(wc -l < "$original_dir/00.dat")" -eq 10839
test "$(stat -c%s "$original_dir/00.sav")" -eq 7388
printf 'quit\n' | "$BIN" play --extracted "$EXTRACTED" --load "$original_dir/00.dat" >/dev/null

echo 'engine tests passed'
