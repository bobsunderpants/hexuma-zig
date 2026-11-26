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
grep -q 'Haustüre ist bereits zu.' <<<"$out"
grep -q 'Haustüre ist jetzt offen.' <<<"$out"
grep -q 'Haustüre ist bereits offen.' <<<"$out"
grep -q 'kamin kann man nicht öffnen.' <<<"$out"
# Front door starts closed (0x5e31=1). Opening it enables the south exit to room 18.
out="$(printf 'öffne haustüre\ngehe süden\nquit\n' | "$BIN" play --extracted "$EXTRACTED")"
grep -q 'Haustüre ist jetzt offen.' <<<"$out"
grep -q 'Du gehst süden.' <<<"$out"

# Original OBNWOR/TEXT*.REL description is used for German lookups.
out="$(run 'untersuche gemälde')"
grep -q 'Ein Gemälde von dieser Größe' <<<"$out"

# The no-object examine path reproduces the original room object scan and the
# container state suffix from the same code-string pool.
out="$(run 'untersuche')"
# Raw OBNBYT classes: eingangshalle=6 (TEXT record), treppe=3 (scenery), so
# neither is listed as a loose object by the original room-object routine.
grep -q 'In der Eingangshalle' <<<"$out"
grep -q 'Von der Decke hängt ein vielarmiger Kristallüster' <<<"$out"
out="$(run 'untersuche haustüre')"
grep -q 'ist zu.' <<<"$out"
out="$(printf 'öffne haustüre\nschließe haustüre\nuntersuche haustüre\nquit\n' | "$BIN" play --extracted "$EXTRACTED")"
grep -q 'Haustüre ist jetzt offen.' <<<"$out"
grep -q 'Haustüre ist jetzt zu.' <<<"$out"
grep -q 'Ein ist zu.' <<<"$out"

# English alternative path uses the same verb ids and original VORS labels.
out="$(run 'go up' --lang en --choices)"
grep -q 'You go up' <<<"$out"

# Point-and-click labels and the text parser share one dispatcher.
out="$(run '1' --lang en --choices)"
grep -q -E 'You (go|see)|That is not possible' <<<"$out"

# Exact German message fragments recovered from HEXPRG.EXE. Room 1 has no
# class-1 object (raw OBNBYT classes); postkarte is the always-available one.
out="$(run 'nimm')"
grep -q 'Bitte geben Sie genau an, was Sie nehmen wollen.' <<<"$out"
out="$(printf 'nimm postkarte\nnimm postkarte\nquit\n' | "$BIN" play --extracted "$EXTRACTED")"
grep -q 'postkarte haben Sie schon.' <<<"$out"
out="$(run 'quatsch')"
grep -q 'Ich kann Ihren Satz leider nicht verstehen.' <<<"$out"

# Original drop/inventory/ignite message pools and class-checked take.
out="$(printf 'nimm postkarte\ninventur\nlege postkarte\nlege postkarte\ninventur\nzünde kamin an\nquit\n' | "$BIN" play --extracted "$EXTRACTED")"
grep -q 'Sie haben postkarte.' <<<"$out"
grep -q 'postkarte liegt jetzt hier auf dem Boden.' <<<"$out"
grep -q 'postkarte haben Sie ja gar nicht!' <<<"$out"
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
printf 'nimm postkarte\nquit\n' | "$BIN" play --extracted "$EXTRACTED" --save "$save" >/dev/null
grep -q '"inventory":\["postkarte"\]' "$save"
printf 'quit\n' | "$BIN" play --extracted "$EXTRACTED" --load "$save" >/dev/null

# Original .dat/.sav save state: 10839 decimal lines (7 numeric and one string
# field per object, 8 per landscape, plus the scalar finalizer fields) and a
# 0x18d8 + 0x404 byte .sav sibling.
printf 'nimm postkarte\nquit\n' | "$BIN" play --extracted "$EXTRACTED" --save "$original_dir/00.dat" >/dev/null
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
assert r1['response']==['Die Spitze ist jetzt vom Billardstock abgeschraubt.'], r1['response']
s=r1['state']; f=s['flags']; w=s['words']; loc=s.get('locals',{})
assert f.get('0xf318')==1
assert (loc.get('0x5227')==1 or f.get('0x5227')==1)
assert (loc.get('0x729a')==888 or w.get('0x729a')==888)
assert w.get('0xcae8')==1
assert (loc.get('0x466c') in (65535,-1) or w.get('0x466c') in (65535,-1))
assert r2['response']==['Der Billardstock ist jetzt ganz zerlegt.'], r2['response']
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

# Native-verified route 2: fireplace, wine cellar, library, billiards, and the
# lit candle. Assert the step-scoped responses and state transitions that were
# read from DOSBox-X frames; the full evidence is in route2_v8_dos/.
route2_dir=$(mktemp -d)
"$BIN" play --extracted "$EXTRACTED" --script "$ROOT/scripts/route2_de.txt" \
  --trace-file "$route2_dir/t.ndjson" >/dev/null
python3 - "$route2_dir/t.ndjson" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
by_step = {r['step']: r for r in rows if r.get('kind') == 'command'}
assert len(by_step) == 50, len(by_step)

def response(step):
    return by_step[step]['response']

def state(step):
    return by_step[step]['state']

# OBNINT gates are one-based object ids; id 178 holds the petroleum and id 147
# is the petroleum noun. This is the guard for overlay unit 11 group 61.
r = by_step[24]
s = r['state']
assert s['object'] == 145 and s['object2'] == 147, (s['object'], s['object2'])
assert s['flags'].get('0xf309') == 1
assert s['flags'].get('0xf30a') == 1
assert s['words'].get('0xcae8') == 1
assert response(24) == [
    'Na, ob das funktionieren wird? Gut - probieren',
    "wir's. Gluckgluck... stop! Das Feuerzeug ist",
    'schon voll!',
], response(24)

assert response(43) == [
    'In der Bibliothek',
    'Hier gibt es zwei Türen: eine zum Billardzimmer',
    'und eine zur Eingangshalle hin.',
], response(43)
assert response(44) == [
    'Bssssmmmm....! Eine dicke Stubenfliege brummt',
    'vorbei.',
    'In der Eingangshalle',
    'Von der Decke hängt ein vielarmiger Kristallüster',
    'herab.',
], response(44)
assert response(45)[0] == 'In diesem Moment donnern von außen plötzlich'
assert response(45)[-1] == '- TASTE -'
assert response(46)[0] == 'Mitten auf dem Boden liegt ein Zettel.'
assert response(46)[1] == 'Vorsiiiicht....... Rrrrrrruummssss!!!!! Mit'
assert response(46)[-1].endswith('heimsen die Punkte ein! Jaja!')
assert state(46)['score'] == 32
assert response(47) == [
    'Ein Jammer! Die Kerzen haben den Sturz nur in',
    'pulverisierter Form überstanden. Aber... halt! Da',
    'liegt noch eine, die einigermaßen heil geblieben',
    'ist!',
    'Sie haben die Kerze genommen.',
], response(47)
assert response(48) == ['Rrrrrtsch! Das Feuerzeug brennt.'], response(48)
assert state(48)['flags'].get('0xf309') == 2
assert response(49) == [
    'Mitten auf dem Boden liegt ein Zettel.',
    'Fein. Ihre Kerze brennt jetzt.',
], response(49)
assert response(50) == [
    'Punkte: 32',
    'Züge: 50',
    'Das Feuerzeug ist wieder aus...',
    'Bssssmmmm....! Eine dicke Stubenfliege brummt',
    'vorbei.',
    'Bitte schauen Sie auf die Statuszeile.',
], response(50)
final = state(50)
assert final['room'] == 1 and final['moves'] == 50 and final['score'] == 32
assert final['inventory'] == [
    'feuerzeug', 'umschlag', 'klinge', 'billardstock', 'hanfseil', 'kerze',
], final['inventory']
assert final['flags'].get('0xf309') == 1
assert final['flags'].get('0xf30a') == 1
PY
rm -rf "$route2_dir"

# Native-verified route 3: the fireplace passage, wine cellar, Rumpelkammer,
# and the Enterhaken combine. Evidence: route3_v1_dos/parity-report.json and
# the direct OCR of steps/0007.png and steps/0008.png.
route3_dir=$(mktemp -d)
"$BIN" play --extracted "$EXTRACTED" --load "$ROOT/saves/route2_lit_candle.json" \
  --script "$ROOT/scripts/route3_de.txt" \
  --trace-file "$route3_dir/t.ndjson" >/dev/null
python3 - "$route3_dir/t.ndjson" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
by_step = {r['step']: r for r in rows if r.get('kind') == 'command'}
assert len(by_step) == 8, len(by_step)

assert by_step[1]['response'][0] == 'Im Kamin'
assert by_step[3]['response'][0] == 'Im Weinkeller'
assert by_step[4]['state']['room'] == 15
assert by_step[4]['response'] == ['Du gehst westen.'], by_step[4]['response']
assert by_step[5]['response'][0] == 'Schaun wir mal... hoppla! Du lieber Himmel, der'
assert by_step[6]['response'] == ['Sie haben haken genommen.'], by_step[6]['response']
assert by_step[7]['response'] == [
    'Sie haben sich eine Art Enterhaken gebastelt. Der',
    'Haken ist am Schaft befestigt. Das Ganze ist',
    'ungefähr 60 Zentimeter lang.',
], by_step[7]['response']
assert 'haken' in by_step[7]['state']['inventory']
assert by_step[8]['response'] == [
    'Punkte: 36',
    'Züge: 58',
    'Bitte schauen Sie auf die Statuszeile.',
], by_step[8]['response']
final = by_step[8]['state']
assert final['room'] == 15 and final['moves'] == 58 and final['score'] == 36
PY
rm -rf "$route3_dir"

# Native-verified route 4: kitchen table, staged Falltür, and the attic entry.
# Evidence: /tmp/opencode/route4_v27_dos/parity-report.json and the direct
# 400% OCR of steps/0015.png and steps/0016.png.
route4_dir=$(mktemp -d)
"$BIN" play --extracted "$EXTRACTED" --load "$ROOT/saves/route3_enterhaken.json" \
  --script "$ROOT/scripts/route4_de.txt" \
  --trace-file "$route4_dir/t.ndjson" >/dev/null
python3 - "$route4_dir/t.ndjson" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
by_step = {r['step']: r for r in rows if r.get('kind') == 'command'}
assert len(by_step) == 16, len(by_step)

def response(step):
    return by_step[step]['response']

def state(step):
    return by_step[step]['state']

assert response(7) == [
    'Auf dem Küchentisch',
    'Sie stehen jetzt auf dem Küchentisch. Fein. Aber',
    'wenn Sie wirkliche Größe erreichen wollen, müssen',
    'sie sich noch mehr anstrengen. Und auf eine',
    'andere Art!',
], response(7)
assert response(9) == ['Sie sind wieder vom Tisch herunten.'], response(9)
assert response(10) == [
    'Gut. Dann Hau... und Ruck... und eins und zwei...',
    'geschafft!',
], response(10)
assert response(11) == ['In diese Richtung führt kein Weg.*'], response(11)
assert response(12) == [
    'Ah - sieh an! Unsere unfehlbare Kombinationsgabe',
    'sagt uns, daß Sie etwas vorhaben! Wir wissen zwar',
    'noch nicht genau was, aber wir bleiben am',
    'Apparat! Gut. Der Küchentisch steht nun unter der',
    'Falltüre.',
], response(12)
assert response(14) == [
    'Damit wird es gehen. Dann ziehen wir mal an dem',
    'Riegel... vorsicht... die Falltür schwingt',
    'herunter! Ein schwarzes Viereck hat sich über',
    'Ihnen aufgetan.',
], response(14)
s = state(14)
assert s['room'] == 6 and s['moves'] == 72
assert s['flags'].get('0x5283') == 1
assert s['flags'].get('0xf31c') == 1
assert s['flags'].get('0xf32c') == 1
assert s['flags'].get('0xf2f7') in (None, 0)  # zero-valued flags are omitted from traces
assert s['words'].get('0x4724') == 65535
assert s['words'].get('0xcae8') == 1

assert response(15) == [
    'Ihre Kerze verbreitet einen flackernden Lichtschein.',
    'Auf dem Dachboden',
    'Dies ist ein großer, L-förmiger Raum direkt unter',
    'dem Dachgebälk. Von hier aus kann man durch eine',
    'Falltüre hinab in den oberen Flur gelangen, oder',
    'nach Westen in den Speicher - den anderen Raum',
    'unter dem Hausdach. Hier, auf dem Dachboden',
    'selbst, stehen ein paar Kisten herum, ein altes',
    'Bettgestell aus Messing und ein großer,',
    'altertümlicher Kleiderschrank.',
], response(15)
s = state(15)
assert s['room'] == 12 and s['moves'] == 73 and s['score'] == 41
assert s['flags'].get('0xf31c') in (None, 0)  # cleared table state is omitted
assert response(16) == [
    'Punkte: 41',
    'Züge: 74',
    'Bitte schauen Sie auf die Statuszeile.',
], response(16)
final = state(16)
assert final['room'] == 12 and final['moves'] == 74 and final['score'] == 41
assert 'fliegenfänger' in final['inventory']
PY
rm -rf "$route4_dir"

# Native-verified `lege Zucker in Glas` in the kitchen (route5_sugar_jar_dos):
# the verb-2 handler stores signed -314 in the live OBNINT word 0x476e and
# prints the jar's visible name rather than the parsed "innenraum" noun.
sugar_dir=$(mktemp -d)
cat > "$sugar_dir/in.txt" <<'TXT'
gehe nach westen
öffne Schublade
nimm Zucker
öffne Glas
lege Zucker in Glas
quit
TXT
"$BIN" play --extracted "$EXTRACTED" --load "$ROOT/saves/route4_dachboden.json" \
  --script "$sugar_dir/in.txt" --trace-file "$sugar_dir/t.ndjson" >/dev/null
python3 - "$sugar_dir/t.ndjson" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
by_step = {r['step']: r for r in rows if r.get('kind') == 'command'}
assert len(by_step) == 6, len(by_step)
r = by_step[5]
assert r['response'] == [
    'Der Würfelzucker befindet sich nun in dem Marmeladenglas.'
], r['response']
s = r['state']
assert s['room'] == 13 and s['moves'] == 79
assert s['words'].get('0x476e') == 65222, s['words'].get('0x476e')
assert 'würfelzucker' not in s['inventory']
PY
rm -rf "$sugar_dir"

# Native-verified bedroom/bath extension (route5_fly14b_dos, 21/21 commands).
# The dropped Marmeladenglas resolves from bare "Glas" in room 8; its state byte
# is the same OBNBYT entry as 0x5f1e, and the failed fly take has one line only.
fly_dir=$(mktemp -d)
cat > "$fly_dir/in.txt" <<'TXT'
gehe nach osten
gehe runter
gehe nach süden
öffne die Tür zum Schlafzimmer
gehe nach westen
klettere Himmelbett
springe Bett
nimm Tuch
schaue auf Tuch
gehe nach norden
gehe nach norden
lege Glas
warte
warte
warte
schließe Glas
warte
warte
warte
öffne Glas
nimm Stubenfliege
quit
TXT
"$BIN" play --extracted "$EXTRACTED" --load "$ROOT/saves/route5_sugar.json" \
  --script "$fly_dir/in.txt" --trace-file "$fly_dir/t.ndjson" >/dev/null
python3 - "$fly_dir/t.ndjson" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
by_step = {r['step']: r for r in rows if r.get('kind') == 'command'}
assert len(by_step) == 22, len(by_step)
assert by_step[12]['response'] == [
    'marmeladenglas liegt jetzt hier auf dem Boden.'
], by_step[12]['response']
assert by_step[16]['response'] == ['Das Marmeladenglas ist jetzt zu.'], by_step[16]['response']
assert by_step[16]['state']['flags'].get('0x5f1e') == 1
assert by_step[20]['response'] == [
    'Aha - da war wohl mal Himbeermarmelade drin! Ein',
    'paar Reste verströmen noch immer den einstigen',
    'Duft selbsteingekochter Marmelade.',
    'Das Marmeladenglas ist jetzt offen.',
], by_step[20]['response']
assert by_step[20]['state']['flags'].get('0x5f1e', 0) == 0
assert by_step[21]['response'] == [
    'ein Objekt "stubenfliege" befindet sich nicht an diesem Ort.'
], by_step[21]['response']
final = by_step[21]['state']
assert final['room'] == 8 and final['moves'] == 103 and final['score'] == 60
assert 'plüschtuch' in final['inventory']
PY
rm -rf "$fly_dir"

# Native-verified web/brush continuation (bath_web_without_lure_v3_dos, 2/2
# commands). Bare `Netz` resolves to the room-8 spinnennetz, and destroying it
# advances the 0xf323 state machine so the old toothbrush becomes takeable.
web_dir=$(mktemp -d)
cat > "$web_dir/in.txt" <<'TXT'
zerstöre Netz
nimm Bürste
quit
TXT
"$BIN" play --extracted "$EXTRACTED" --load "$ROOT/saves/route5_bathroom.json" \
  --script "$web_dir/in.txt" --trace-file "$web_dir/t.ndjson" >/dev/null
python3 - "$web_dir/t.ndjson" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
by_step = {r['step']: r for r in rows if r.get('kind') == 'command'}
assert len(by_step) == 3, len(by_step)
assert by_step[1]['response'] == [
    'Okay. Das Spinnennetz ist jetzt kaputt. Es',
    'scheint, als träfe Sie von irgendwoher ein höchst',
    'feindseliger Blick.',
], by_step[1]['response']
s = by_step[1]['state']
assert s['room'] == 8 and s['moves'] == 104 and s['score'] == 60
assert s['object'] == 303 and s['flags'].get('0xf323') == 2
assert by_step[2]['response'] == ['Gut. Die alte Zahnbürste gehört nun Ihnen.']
s = by_step[2]['state']
assert s['room'] == 8 and s['moves'] == 105 and s['score'] == 70
assert s['object'] == 131 and 'zahnbürste' in s['inventory']
PY
rm -rf "$web_dir"

# Native-verified library/tube continuation
# (to_library_open_tube_v3_dos, 6/6 commands). The tube starts closed and its
# state line takes the definite article in the original German parser.
tube_dir=$(mktemp -d)
cat > "$tube_dir/in.txt" <<'TXT'
gehe nach süden
gehe nach osten
gehe nach norden
gehe runter
gehe nach osten
öffne Tube
quit
TXT
"$BIN" play --extracted "$EXTRACTED" --load "$ROOT/saves/route5_bathroom.json" \
  --script "$tube_dir/in.txt" --trace-file "$tube_dir/t.ndjson" >/dev/null
python3 - "$tube_dir/t.ndjson" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
by_step = {r['step']: r for r in rows if r.get('kind') == 'command'}
assert len(by_step) == 7, len(by_step)
assert by_step[6]['response'] == ['Die Tube ist jetzt offen.'], by_step[6]['response']
s = by_step[6]['state']
assert s['room'] == 2 and s['moves'] == 109 and s['score'] == 65
assert s['object'] == 321
# The open action clears OBNBYT id 321 to zero; zero-valued flags are omitted
# from the trace, so the "jetzt offen" response above is the state evidence.
PY
rm -rf "$tube_dir"

# Native after_brush_take_fly: bare `Fliege` prefix-matches the already-owned
# Fliegenfänger instead of the full Stubenfliege noun.
fly_token_dir=$(mktemp -d)
cat > "$fly_token_dir/in.txt" <<'TXT'
zerstöre Netz
nimm Bürste
nimm Fliege
quit
TXT
"$BIN" play --extracted "$EXTRACTED" --load "$ROOT/saves/route5_bathroom.json" \
  --script "$fly_token_dir/in.txt" --trace-file "$fly_token_dir/t.ndjson" >/dev/null
python3 - "$fly_token_dir/t.ndjson" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
by_step = {r['step']: r for r in rows if r.get('kind') == 'command'}
assert by_step[3]['response'] == ['den Fliegenfänger haben Sie schon.'], by_step[3]['response']
assert by_step[3]['state']['object'] == 323
PY
rm -rf "$fly_token_dir"

echo 'engine tests passed'
