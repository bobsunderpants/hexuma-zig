#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/zig-out/bin/hexuma"
EXTRACTED="${1:-$ROOT/extracted}"

run() {
  printf '%s\nquit\n' "$1" | "$BIN" play --extracted "$EXTRACTED" "${@:2}"
}

# German original vocabulary path. REA shows room 1's LAND record is
# (1,0,-18,-2,-3,6,0): south/east/west are closed (-), while up is a positive
# exit. A negative exit keeps the room unchanged; the overlay message is still
# appended. Verify both the raw exit list and a real positive movement.
out="$(run 'gehe süden' --choices)"
grep -q 'Ausgang: süden osten westen rauf' <<<"$out"
grep -q 'Mitten auf dem Boden liegt ein Zettel' <<<"$out"
if grep -q 'Du gehst süden' <<<"$out"; then
  echo 'negative LAND exit incorrectly travelled' >&2
  exit 1
fi
out="$(run 'gehe rauf' --choices)"
grep -q 'Du gehst rauf' <<<"$out"

# REA-derived VORS runtime overrides are applied to the start screen.
# Startup has 0x5e31=1 (timer/postman active), so slot 4 keeps the original
# "Öffne die Haustür" label; the close-door override applies when 0x5e31==0.
# Startup initializes 0x5fa7=1 (pragmatic library-door fix), so VORS slot 9
# shows the base open-door label rather than "Gehe in die Bibliothek".
out="$(run 'untersuche kamin' --choices)"
grep -q 'Öffne die Haustür' <<<"$out"
grep -q 'Öffne die Tür zur Bibliothek' <<<"$out"
grep -q 'Schau das Gemälde an' <<<"$out"
grep -q 'Nimm den Zettel' <<<"$out"
out="$("$BIN" vors --picture 1 --room 1 --flag 0x5e31=0 --extracted "$EXTRACTED")"
grep -q $'^4\tÖffne die Haustür\tSchließe die Haustüre$' <<<"$out"

# REA-decoded open/close state machine (0x1755:0x31a1). Startup initializes
# 0x5e31=1 (front door closed); open/close toggles state and non-openable
# objects use the exact code strings.
out="$(printf 'schließe haustüre\nöffne haustüre\nöffne haustüre\nöffne kamin\nquit\n' | "$BIN" play --extracted "$EXTRACTED")"
grep -q 'haustüre ist bereits zu.' <<<"$out"
grep -q 'haustüre ist jetzt offen.' <<<"$out"
grep -q 'haustüre ist bereits offen.' <<<"$out"
grep -q 'kamin kann man nicht öffnen.' <<<"$out"
# Front door starts closed (0x5e31=1). Opening it enables the south exit to room 18.
out="$(printf 'öffne haustüre\ngehe süden\nquit\n' | "$BIN" play --extracted "$EXTRACTED")"
grep -q 'haustüre ist jetzt offen.' <<<"$out"
grep -q 'Du gehst süden.' <<<"$out"

# Original OBNWOR/TEXT*.REL description is used for German lookups.
out="$(run 'untersuche gemälde')"
grep -q 'Ein Gemälde von dieser Größe' <<<"$out"

# The no-object examine path reproduces the original room object scan and the
# container state suffix from the same code-string pool.
out="$(run 'untersuche')"
grep -q 'Hier befinden sich eingangshalle, treppe' <<<"$out"
out="$(run 'untersuche haustüre')"
grep -q 'ist zu.' <<<"$out"
out="$(printf 'öffne haustüre\nschließe haustüre\nuntersuche haustüre\nquit\n' | "$BIN" play --extracted "$EXTRACTED")"
grep -q 'haustüre ist jetzt offen.' <<<"$out"
grep -q 'haustüre ist jetzt zu.' <<<"$out"
grep -q 'Ein ist zu.' <<<"$out"

# English alternative path uses the same verb ids and original VORS labels.
out="$(run 'go up' --lang en --choices)"
grep -q 'You go up' <<<"$out"

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

# Room-1 postman/envelope flow: timer advances f301, envelope/splitter become
# takeable through overlay rules, and cae8-handled take grants inventory.
# Evidence: docs/reports/HEXPRG_0x13e7d_pseudocode.c group 9 (obj 70/0x452a).
out="$(printf 'warte\nwarte\nwarte\nöffne haustür\nnimm umschlag\nja\nja\nöffne umschlag\nnimm edelsteinsplitter\ninventur\nquit\n' | "$BIN" play --extracted "$EXTRACTED")"
grep -q 'Behalten Sie es lieber selbst.' <<<"$out"
grep -q 'edelsteinsplitter' <<<"$out"

# Conditional FR overlays use the REA-derived startup globals.
# Startup initializes 0x5e31=1 and 0x5fa7=1 (pragmatic door/timer fixes), so
# fr00101/fr00107 are inactive while fr00103 remains active and fr00104 stays off.
out="$("$BIN" overlays --room 1 --extracted "$EXTRACTED")"
grep -qx 'fr00103.seq' <<<"$out"
for bad in fr00101.seq fr00104.seq fr00107.seq; do
  if grep -qx "$bad" <<<"$out"; then
    echo "unexpected overlay at startup: $bad" >&2
    exit 1
  fi
done

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
# Rooms outside every compiled overlay unit use the main dispatcher tail string.
out="$("$BIN" rules --room 25 --verb 3 --object 0 --extracted "$EXTRACTED")"
grep -q 'allowed=no' <<<"$out"
grep -q 'Keine Action programmiert für diesen Raum' <<<"$out"
# Room 1's 0x8a message is driven by the OVR counter increment, so setting the
# counter to 4 up front would skip it. Verify the startup path instead.
out="$("$BIN" rules --room 1 --verb 3 --object 0 --extracted "$EXTRACTED")"
grep -q 'msg 0x8a' <<<"$out"
# Rooms 17 and 26 reach main-module dispatcher 0x13e7d, not the fallback string.
# First entry into room 17 runs the inline 0xf330 state machine and returns
# TEXT 0x67f before the dispatcher; later entries continue to the dispatcher.
out="$("$BIN" rules --room 17 --verb 1 --object 424 --extracted "$EXTRACTED")"
grep -q 'msg early: Schon wenige Augenblicke später' <<<"$out"
out="$("$BIN" rules --room 17 --verb 1 --object 424 --flag 0xf330=3 --extracted "$EXTRACTED")"
grep -q 'allowed=yes' <<<"$out"
out="$("$BIN" rules --room 26 --verb 3 --object 0 --extracted "$EXTRACTED")"
grep -q 'allowed=yes' <<<"$out"
# Top-guard object 0x24a switches the text segment and emits TEXT id 0x8e
# before the room's normal overlay rules.
out="$("$BIN" rules --room 170 --verb 3 --object 586 --extracted "$EXTRACTED")"
grep -q 'msg early: trägt. Oben steht' <<<"$out"

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
# The .dat writer must serialise the live mutable LAND state, not the initial
# asset table. With startup 0x5e31=1 the front door is closed (room 1 word 2
# is -18/blocked); opening it makes it +18.
test "$(sed -n '3p' "$original_dir/00.dat")" -eq -18
printf 'öffne haustüre\nquit\n' | "$BIN" play --extracted "$EXTRACTED" --save "$original_dir/01.dat" >/dev/null
test "$(sed -n '3p' "$original_dir/01.dat")" -eq 18
printf 'quit\n' | "$BIN" play --extracted "$EXTRACTED" --load "$original_dir/01.dat" >/dev/null


# Main-loop timer/counter 0xcae2 increments once per command iteration
# (entry 0x11841: INC word ptr [0xcae2] at 0x1196f). Verb 47/wait returns
# "Die Zeit vergeht..." (text 46) and still goes through overlay dispatch.
out="$(printf 'warte\nwarte\nquit\n' | "$BIN" play --extracted "$EXTRACTED")"
grep -q 'Die Zeit vergeht' <<<"$out"
cae2_dir="$(mktemp -d)"
printf 'warte\nwarte\nquit\n' | "$BIN" play --extracted "$EXTRACTED" --save "$cae2_dir/00.dat" >/dev/null
# save_layout word range 51938..51940 is lines 10404..10406 in 00.dat
# warte, warte, quit = 3 command iterations.
test "$(sed -n '10404p' "$cae2_dir/00.dat")" -eq 3
rm -rf "$cae2_dir"

# Billardstock split (verb 125/object 225, f316==3): evidence-backed
# HEXPRG_0x13e7d_pseudocode.c:496-640. Use portable save to reach room 4 state.
billard_dir=$(mktemp -d)
cat > "$billard_dir/s.json" <<'JSON'
{"room":4,"picture":4,"moves":0,"score":0,"inventory":["billardstock"],"flags":{"0xf316":3,"0xf317":1,"0xf318":0,"0x5e31":1,"0x5fa7":1},"words":{},"dwords":{}}
JSON
cat > "$billard_dir/in.txt" <<'TXT'
zerlege billardstock
zerlege billardstock
quit
TXT
"$BIN" play --extracted "$EXTRACTED" --load "$billard_dir/s.json" --script "$billard_dir/in.txt" --trace-file "$billard_dir/t.ndjson" >/dev/null
python3 - "$billard_dir/t.ndjson" <<'PY'
import json, sys
rows=[json.loads(l) for l in open(sys.argv[1])]
cmd=[r for r in rows if r.get('kind')=='command']
r1,r2=cmd[0],cmd[1]
assert r1['response']==['lang und hat ein wenig mehr als einen Zentimeter'], r1['response']
s=r1['state']; f=s['flags']; w=s['words']; loc=s.get('locals',{})
assert f.get('0xf318')==1
assert (loc.get('0x5227')==1 or f.get('0x5227')==1)
assert (loc.get('0x729a')==888 or w.get('0x729a')==888)
assert w.get('0xcae8')==1
assert (loc.get('0x466c') in (65535,-1) or w.get('0x466c') in (65535,-1))
assert r2['response']==['Vielleicht sollten Sie Ihren Billardstock erstmal'], r2['response']
s=r2['state']; f=s['flags']; w=s['words']; loc=s.get('locals',{})
assert f.get('0xf318')==2
assert (loc.get('0x5225')==1 or f.get('0x5225')==1)
assert (loc.get('0x5226')==1 or f.get('0x5226')==1)
assert (loc.get('0x5227')==1 or f.get('0x5227')==1)
assert (loc.get('0x4660')==4 or w.get('0x4660')==4)
assert (loc.get('0x4668') in (65535,-1) or w.get('0x4668') in (65535,-1))
assert (loc.get('0x466a') in (65535,-1) or w.get('0x466a') in (65535,-1))
assert (loc.get('0x5221')==3 or w.get('0x5221')==3)
assert (loc.get('0x729a')==867 or w.get('0x729a')==867)
assert w.get('0xcae8')==1
PY
rm -rf "$billard_dir"

echo 'engine tests passed'
