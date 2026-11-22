# Reverse-engineering findings

This file records analysis evidence used to reconstruct the engine. It is not
source code and not a substitute for the generated assets in `extracted/`.

## Target

- Binary: `/home/bob/Downloads/Hexuma/HEXPRG.EXE`
- Format: DOS MZ, x86
- SHA-256: `8e792e65fe97d7009cad0728f01af7693d94d48d993d32606edb27d19b4b90ae`
- REA `binary_overview`: 31 segments, 400 procedures, 40 strings.
- REA evidence id:
  `ev_51c007b97148e6313e3fd0fe7395c94e92dc29148b667bae1f0849045bbb4827`
- Load-segment caveat: MZ load segment is `0x1000`; Ghidra image base is `0x0`.
  Do not compute procedure addresses as `file_offset + 0x1000`.

## Function responsibility map

| Address | Responsibility |
|---|---|
| `0x100f1` | Asset-name table/open/read: `vorein.seq`, `verben.seq`, `obw.seq`, `obnint.bin`, `obnbyt.bin`, `obnwor.bin`, `auswoert.seq`, `land.bin`, `matr.seq`, `bilddat.seq` |
| `0x10b17` | Global flag/array initialization and scene/text block setup |
| `0x11be9` | Shared action dispatcher prelude, inline rooms `0x11`/`0x1a`, overlay unit range dispatch, unmapped-room fallback |
| `0x13e7d` | Main-module room-action dispatcher for inline rooms `0x11` and `0x1a` |
| `0x11612` | Memory check, abort prompt, asset size validation |
| `0x1755d` | Input tokenization on spaces into 31-byte token slots |
| `0x17d2f` | Token matching against noun/verb tables; sets room/verb/object state |
| `0x1d621` | Builds and loads `hg<id>.seq` scene backgrounds |
| `0x200f9` | Inventory display |
| `0x22b1f` | Save/load (`sapic.tmp`, `save.tmp`, `.sav`/`.dat`) |
| `0x2408d` | Loads `VORS.BIN` and fills 15 context-action slots |
| `0x2fdcf` | `FUN_2d0d_2cff`, the small bounded far-copy helper used by save/load reload |
| `0x3afb4` | `FUN_3a97_0644`: copy `min(count, source[0])` bytes from a far Pascal string |
| `0x25206` | Main input loop: mouse/hotspot dispatch, command keys, line editing |
| `0x26c68` | `TEXT*.REL` record dispatcher and byte decoding |
| `0x278a3` | Startup: sound detect, graphics driver, fonts, menu assets |
| `0x2ae84` | Sound asset open/header/buffer setup |
| `0x2b08c`, `0x2b814` | AdLib/OPL detection and port I/O |
| `0x2bffd` | Builds `bild<id>.seq` background plus conditional overlays |

Confidence: high for addresses with direct disassembly evidence above; medium for
top-level roles where the entry function `0x11841` did not decompile.

### Decompiler pointer caveat

Ghidra repeatedly renders `PUSH CS` as the integer `14999` (`0x3a97`) in
far-pointer arguments. Assembly proves those constants are the *containing
code segment*, not a data segment named `0x3a97`: for example, in
`0x2408d.c:95`, `14999` means `CS = 0x1c89`, so the string pointer
`0x758c,14999` resolves to `0x1c89:0x758c` (`"Schließe die Haustüre"`). The same
rule applies to `FUN_1755_*` functions (`CS = 0x1755`). Any pointer decoding
that treats `14999` as a literal segment produces garbage.

REA `decompile_all` evidence id:
`ev_5e76269aa5a87d7b7667b597713274b744b7a0674dd90f1c1a046035d7187b75`.

## Table layouts

### Vocabulary

- `VOREIN.SEQ` globals: `0xa196 = 245`, `0xa198 = 345`, `0xa19a = 10`,
  `0xa19c = 1060`, `0xa19e = 240`.
- `VERBEN.SEQ`: alternating verb string and decimal action id. 345 real records
  plus a terminator. Zero-based record `j` maps to runtime index `j + 1`.
- `OBW*.SEQ`: one word per CRLF line. Physical line `k` maps to runtime id
  `k + 1`. Strings are copied with max length 29 and token stride 31.
- `OBNINT*.BIN`: 1060 × 4 bytes, two little-endian `i16` values. The generated
  JSON renders each record as file-order hex bytes, so `"0300"` decodes as `3`,
  not `0x0300`. `field_b` is the room gate: current room, `0xffff` global,
  negative alias id, or `LAND.BIN` adjacency. `field_a` is the 1-based LAND
  loader slot used at `0x37fc`; the live file-word column is `field_a - 1`.
  `field_a > 100` means parent object id `field_a - 100`.
- `OBNBYT*.BIN`: 1060 × 3 bytes of object flags; the first byte array at file
  index `id - 1` is the original class byte. Exact taxonomy remains unresolved.
- `OBNWOR*.BIN`: 1060 × 4 bytes, two `u16` 1-based `TEXT*.REL` ids.

### Room graph

`LAND.BIN` is 240 × 14 bytes = seven `i16` values. File word 0 is the room id;
file words 1..6 are the six directional exits. The loader loop at
`0x100f1:187-199` writes file word `j` of room `i` to runtime offset
`i*0xe + (j+1)*2 - 0x52b0`; therefore the original 1-based loader slot is
`j + 1`. The parser at `0x184e4:416-435` maps movement verbs `10..16` to
`0xbe5c = verb - 7` and `0xcac2 = 7`; class-0 movement at `0x1b38e` uses that
loader slot directly. The engine stores the six exits with 0-based file indices
`1..6`. Negative exits are closed doors; a target of `0` emits TEXT id `0x61`
("In diese Richtung führt kein Weg.*"), while a negative exit emits message
`0x3c` only when a matching class-4 door object exists and is otherwise silent.
Room 1's record is `(1,0,-18,-2,-3,6,0)`, so south is blocked until the front
door is closed and up is traversable.

### Text records

`TEXT*.REL` files contain 77-byte records. The dispatcher at `0x26c68` computes
a file/record from the 1-based id; stored bytes are `(stored + 0x14)`, with
`0x2f` mapped to space, then decoded as CP850. The `@` byte terminates display.

## In-code message pools

The original German parser/action messages are packed Pascal strings in the
executable, not in `TEXT*.REL`. Their far pointers are passed to the bounded
copy helper `FUN_3a97_0644`. The extractor writes the decoded chains to
`data/code_strings.json` and `lua/code_strings.lua`.

| Pool | Pointer | Count | Representative messages |
|---|---|---|---|
| take | `0x1755:0x1fab` | 8 | `Bitte geben Sie genau an, was Sie nehmen wollen.`, `haben Sie schon.`, `Sie haben `, `genommen.` |
| parser | `0x1755:0x22a5` | 8 | `Ich kann Ihren Satz leider nicht verstehen.`, `Das ist leider nicht möglich.`, `befindet sich nun in ` |
| examine | `0x1755:0x262b` | 14 | `Es ist finster hier, Sie werden Licht brauchen.`, `hat keine besonderen Merkmale.`, `ist offen und enthält ` |
| movement | `0x1b27:0x0000` | 6 | `Da sind Sie bereits.`, `Das ist von hier aus nicht erreichbar.`, `versperrt Ihnen den Weg.` |
| door | `0x1755:0x0de0` | 25 | `Eine solche Tür gibt es hier nicht!`, `Diesen Satz verstehe ich nicht.`, `Der Begriff "` |
| ignite | `0x1755:0x1f6a` | 1 | `Das kann man nicht anzünden.` |
| open/close | `0x1755:0x312e` | 6 | `kann man nicht öffnen.`, `ist jetzt offen.`, `ist bereits zu.` |
| drop | `0x1755:0x225a` | 2 | `Bitte geben Sie genau an, was Sie weglegen wollen.`, `haben Sie ja gar nicht!` |
| inventory | `0x1755:0x2e61` | 6 | `Sie haben `, `nichts.`, `und ` |
| dispatch | `0x119c:0x0000` | 1 | `Keine Action programmiert für diesen Raum` |

The file-offset mapping for these load-module pointers is
`segment * 16 + offset - 0x9a00`.

## Parser and VORS details

- `0x1755d` splits input on literal spaces into 31-byte token records and
  removes `und`, setting the carry-verb flag `0x7d7e`.
- `0x17931` strips one suffix from words longer than five characters, in the
  order `en`, `es`, `s`, `n`, `st`, into a parallel token buffer.
- `0x17d2f` first matches verbs exactly, then nouns by exact string or proper
  prefix. A noun is accepted when its room gate equals the current room or
  `-1`; negative gates below `-1` consult a per-room alternate gate table.
- The VORS record is selected from `0x32d0`, which is the picture id read while
  loading a BILD resource, not the room id. The engine therefore filters click
  regions by `pictureValue()`, not by `room`.
- `VORS.BIN` record `n` starts at file offset `n * 0x377`; record 0 is an
  unused/corrupt sentinel. Record 1 contains `"Untersuche den Kamin"`.
- `0x2408d` additionally overwrites VORS action slots with hardcoded,
  room/flag-gated labels. The extractor emits every original slot, including
  length-zero and one-space Pascal strings, because the runtime clears and
  overwrites slots by index. `data/vors_records.json` stores each record's
  original slot count (with the original `count > 14 -> 1` clamp), and
  `data/vors_overrides.json` stores all 199 decoded assignments in original
  branch order. `engine.Game.actionForSlot()` evaluates their boolean
  conditions against the current room and live byte/dword state. Examples:
  - record 1, flag `0x5e31 == 0`: slot 4 becomes `Schließe die Haustüre`,
    slot 9 becomes `Gehe in die Bibliothek` when `0x5fa7 == 0`.
  - record 1 in room 5: all ten effective slots become `Gehe Süd`.
  - record 5: slot 0 toggles between `Schließe die Tür` and `Öffne die Tür`
    with flag `0x5fab`.
  - record 35 in room 88: slot 4 is replaced by a length-one space command.
  - record 40 in room 147: eleven slots are replaced with the beach labels.
  - record 43: slot 1 is blanked while `room != dword(0x4b3a)`.
  - record 123: slot 4 receives `Untersuche das Holzstück` only when
    `byte(0x5422) == 1`, `room == 189`, and `room == dword(0x4a62)`.
  These flags are live, mutable state, not startup constants. Some are
  initialized by `0x10b17` and others are written by scene/action code; the
  exact mutators for several addresses are still unresolved. The engine keeps
  them in saveable state and initializes new games from `initial_flags.json`.
  `hexuma vors --picture N --room N [--flag ADDR=VAL] [--dword ADDR=VAL]`
  displays the original and effective command for every effective slot.

## Reconstructed verb handlers

The engine now follows the original `0x1b140` verb dispatch for the handlers
whose bodies are complete in the load module:

- `1` take (`0x1755:0x203d`): rejects object class `0` or `>2`, checks the
  container state byte at `id + 0x5de4`, and appends only the exact packed
  fragments from the `take` pool.
- `2` drop (`0x1755:0x2362`) and `5` inventory (`0x1755:0x2e93`) use the
  `drop`/`parser` and `inventory` pools, including `Sie haben nichts.`.
- `3` examine (`0x1755:0x277f`) emits the `TEXT*.REL` id from OBNWOR field `b`,
  the object class state suffix for containers, and the original room-object
  scan from the `examine` pool. Field `a` is the room-listing TEXT id; field
  `b` is the directed-examine TEXT id.
- `4`/`6` open/close (`0x1755:0x31a1`) read the class byte at `id + 0x5140`
  and the state byte at `id + 0x5de4`. State `0` is open, `1` is closed.
- `48` ignite (`0x1755:0x1f87`) and the empty handlers `8`/`9` now match the
  original no-op/message behavior. Other verb ids still fall through to the
  approximated dispatcher.

## Original command menu (`OBLISTE.BIN`)

`FUN_1c89_73be` (0x23c4e) loads `OBLISTE.BIN` on every room change: 256 `u16`
room offsets, then at each offset a `u16 count` and `count + 1` Pascal strings
stored with a duplicated length byte. They are copied into the six 101-byte
slots at `0x7d8e`. `FUN_1c89_50e1` (0x21971) displays those strings and inserts
the selected one into the command buffer; the call site is the `';'` key in the
main input loop (`0x25206.c:364`). The extractor writes them to
`data/action_menu.json` and `lua/action_menu.lua`; the engine exposes them in
`choices()` as a second original alternative to typing, alongside the VORS
hotspot labels. 145 rooms have a menu; room 1 contains `Schau das Gemälde an`,
`Öffne die Haustür`, `Nimm den Zettel`, and five other commands.

## Image and asset flow

- `FUN_1c89_0d91` (0x1d621) builds `hg<NN>.seq` (two-digit, zero padded),
  loads `0x8980` bytes of 320×200×8 pixels at `A000:0000` plus `0x404` bytes of
  VGA palette, then blits to VRAM and copies palette entries `0xb0..0xef` to
  the shadow at `0x2ca2`.
- The BILD loader (0x2bffd) builds `bild<NNN>.seq` (three digit) from the scene
  id and sets the current VORS record in `0x32d0`.
- 57 non-empty conditional `FR<scene><variant>.seq` overlays are selected by
  scene plus byte/dword conditions. The same flags (`0x5e31`, `0xf2fb`,
  `0x5fa7`, `0x5fab`, …) gate the VORS action overrides, which corroborates the
  flag model used by the engine. The extractor emits `data/overlays.json`; the
  X11 frontend draws every matching frame in table order over the BILD
  background using each frame's `(x, y, w, h)` header.
- `FR`/`INTFR`/`MENUEFR` frames have an 8-byte header and no embedded palette;
  a conservative palette-index-to-BGRA conversion is used for display, so
  exact VGA colour parity is not yet established.

Detailed evidence: `docs/reports/hexuma.md`.

## Interpreter and parity findings

- No numeric opcode-dispatch interpreter exists in the analyzed load module.
  Action execution is a compiled pipeline: `0x1755d` tokenizes, `0x17d2f`
  resolves verb/noun ids, `0x184e4` applies hardcoded state fixups,
  `0x1b140` dispatches verb ids, and `0x11be9`/`0x16dbe` dispatch object/action
  effects. Room-specific behavior lives largely as compiled x86 code in
  `HEXUMA.OVR`.
- `cd 3f` is Turbo Pascal's overlay-manager dispatch, installed at vector
  `0x3f` with `CS=0x3a97`. The handler at linear `0x3aa36` manipulates System
  overlay variables at `DS:0x2bc9+0xafe..0xb24`. Every `cd 3f <u16>` in the
  load module is a five-byte descriptor thunk; the following word is the
  routine offset inside the overlay unit, not an overlay number. Main dispatch
  at `0x11d46..0x11e26` maps room ranges to far segments
  `0x328 + 3*i`, so descriptor block `i` corresponds to overlay unit `i`.
- All 11 overlay units were extracted from `HEXUMA.OVR` and decompiled from
  clean entry-point COM slices. `scripts/extract_overlay_rules.py` converts the
  authoritative decompilations in `/tmp/opencode/ovr-entry-only/{i}-dec/` plus
  the main-module dispatcher at `0x13e7d` (retained as
  `docs/reports/HEXPRG_0x13e7d_pseudocode.c`) into
  `extracted/data/overlay_rules.json` (mirrored to `src/data/overlay_rules.json`
  for embedding in the extractor): 6,950 rules with structured guards and
  actions, numeric `room_ranges`, and zero raw guards. Unit 11 is the
  main-module dispatcher block and covers only rooms 17 and 26, which reach it
  after the inline state machines in `0x11be9`. Ghidra names the runtime word-table
  read at `0x1561e` (`field_b[object]` at `0x449e + id*2`) `uRam000146c0`; the
  generator maps that symbol to the `object_gate` variable so the original
  `room == field_b(object)` guard is evaluated against the live OBNINT table.
  `src/overlay_rules.zig` parses that table; `src/overlay_eval.zig` evaluates it in original rule order,
  stopping at terminal `return` actions. The engine applies the dispatcher
  prelude from `0x11be9` (hotspot exclusion flags `0xf2f9`/`0xf2fa`) before
  selecting a unit. Overlay messages append to the verb-handler output in the
  same shared output buffer; they do not replace it.
- The complete `0x11be9` dispatcher path is now modelled. Its top guard
  (`room > 0xa0 && verb == 3 && object == 0x24a`) switches the source segment to
  `0x1c89` and displays TEXT id `0x8e` before the room's normal rules. The
  prelude exclusion list returns early for the rooms named at `0x11be9:88-95`.
  Room `0x11` clears `OBNINT.field_b` for scenery objects whose current gate is
  `-1` (the loop at `0x11be9:111-136` indexes both the gate word table and the
  class-byte table by 1-based object id, not compact vocabulary position), then
  handles `0xf330` states `0` and `2` before calling the main dispatcher; room `0x1a` resets its
  inline byte block, the words `0xf352`/`0xf3b6`, and the word `0xf452`. Rooms
  outside every dispatcher range copy `Keine Action programmiert für diesen
  Raum` into `0xcaea` and display it.
- Overlay fixup tables exist at `/tmp/opencode/ovr-units/unit{i}.fix` as arrays of
  code-relative `u16` offsets to segment words in far pointers. Inspection of
  unit 10's 405 fixups shows the stored segment words are already absolute
  (`0xc89`, `0x2a97`, `0x1bab`, `0xbc0`, and the overlay dispatch segment
  `0x349`), not zero placeholders. Adding a runtime delta to all of them would
  corrupt the main-module far-call targets, so the clean decompilations already
  preserve the needed static semantics. Fixups remain relevant only to a future
  native overlay loader reproduction.
- A deterministic DOSBox-X harness is available at `scripts/dosbox_parity.sh`.
  Fixed cycles, disabled vsync, surface output, and capture-until-stable
  produce byte-identical screenshots. DOSBox-X `AUTOTYPE` lines in `[autoexec]`
  run before `hexuma.bat`; lines after it are blocked until the game exits, so
  in-game command injection needs an external XTest helper. The current Zig GUI
  has a structurally different layout, so semantic/state parity is the
  realistic near-term target rather than pixel identity.
- Full research reports: `docs/reports/interpreter.md` and
  `docs/reports/dosbox-parity.md`.

## Encoding

Plain `.SEQ` tables and `VORS.BIN` labels use DOS CP437/CP850. For the German
letters in the shipped data these code pages agree: `0x94 = ö`, `0x81 = ü`,
`0x84 = ä`, `0xe1 = ß`. The `TEXT*.REL` dispatcher specifically proves CP850.

## Original versus reconstructed save state

The original save/load path uses `sapic.tmp`, `save.tmp`, `hgNN.seq`, `NN.sav`
and `NN.dat`. The engine now emits the original `.dat`/`.sav` pair when the
`--save` path ends in `.dat` or `.sav`:

- `NN.sav` is `0x18d8` bytes of VRAM thumbnail followed by a `0x404`-byte
  graphics-driver block (7,388 bytes total). Load reads only the first
  `0x18d8` bytes. The Zig frontend has no VGA VRAM, so it writes zeroed bytes
  of the exact original length.
- `NN.dat` is unpadded decimal text with CRLF terminators. The 395 static
  call sites of the writer at `0x2d100` are expanded with the `VOREIN.SEQ`
  counts (240 landscapes, 1060 objects, 50 inventory slots) into 10,839
  lines. The compact field table is `src/data/save_layout.json`. Landscape
  words are serialized from the live mutable `land_exits` table, so an opened
  or closed door changes the saved sign; loading restores both the original
  address-keyed word map and `land_exits`. Known word globals (`0xcae8`,
  `0xc9c0`, `0xc9be`, `0x3d94`, `0x3dc6`, `0x3e4a`, `0x7d7e`, `0xf352`,
  `0xf3b6`, `0xf452`) are written as 16-bit values.
- Load validates global ranges but does not clamp, matching the original
  `FUN_3a97_021c` bounds checker. There is no checksum in the examined path.
- The `0x18d8` blob is filled by a 58-step VRAM copy loop
  (`A000:(i*0x140+0x2c0d)`, 107 bytes per step) and populated by the
  screenshot buffer at `DS:0x2c92`.

A portable JSON fallback remains for extensionless paths and `.json` files.
Full byte parity with an original DOSBox save is not claimed: the opaque
graphics block and many positional globals are not modelled by the Zig game
state. Detailed evidence: `docs/reports/save-format.md`.

## Residual gaps

- `OBNBYT` class taxonomy and most `OBNINT.field_a` state uses remain unresolved.
- `OBNWOR.field_a` versus `field_b` selection is heuristic: `field_b` is treated
  as the room-specific description and `field_a` as the generic fallback.
- Original save byte parity is not claimed because the `0x18d8` VRAM thumbnail
  and the `0x404` graphics-driver block are opaque to the Zig state model.
- Overlay rules are verified against static decompilation and targeted CLI
  probes; full DOSBox action-by-action parity remains an open validation task.
  `scripts/dosbox_parity.sh` records the Zig side of a command sequence, but
  this X session leaves every DOSBox window `IsUnMapped`/`_NET_WM_STATE_HIDDEN`,
  so the script now reports a missing original screenshot instead of silently
  claiming parity.
- Font glyph metrics are unresolved, and several flag mutators
  (`0x5e31`, `0x5fab`, `0x6029`, `0x604b`, `0x4b9a`, `0x4a62`, `0xb894`,
  `0x6bc4`) are still tracked as live state without a decoded writer.
- `OBLISTE.BIN`'s trailing byte and parts of `VORS.BIN` padding are inert
  authoring remnants, not decoded game data.
