# Hexuma asset formats (reverse-engineered)

All offsets are byte offsets from the start of the file. Multi-byte integers are
little-endian unless stated otherwise. Formats were derived empirically from
the shipped assets in `/home/bob/Downloads/Hexuma/` and checked against REA
analysis of `HEXPRG.EXE` / `HEXUMA.OVR`.

## REA context

- `HEXPRG.EXE`: DOS MZ, x86, SHA-256
  `8e792e65fe97d7009cad0728f01af7693d94d48d993d32606edb27d19b4b90ae`.
- Ghidra provider reported 31 segments, 400 procedures, 40 strings.
- Relevant strings:
  - `256 COLOR AGI DRIVER, SERIAL: EVALUATION_COPY... VERSION 3.01, COPYRIGHT (C) 1989 BY: N.HUTH`
  - `titel.aws`
  - `AGIFONT_8x8`, `LORES`, `VGAEXTRA`, `CROSS`
- `HEXUMA.OVR` contains readable German dialogue stored as length-prefixed
  records. REA caveat: an appended DOS overlay is not the initialized load
  module, and static analysis does not emulate BIOS/DOS interrupts.
- Mapped original responsibilities: `0x100f1` asset-name loading, `0x10b17`
  global flag init, `0x1755d` input tokenization, `0x17d2f` noun/verb lookup,
  `0x2408d` VORS action slots, `0x25206` main mouse/keyboard loop, `0x11be9`
  room/hotspot gating, `0x1d621` HG scene loading, `0x2bffd` picture/overlay
  composition, `0x200f9` inventory display, `0x22b1f` save/load.

## `.SEQ` picture container

There are five binary layouts plus a plain-text variant. All share the same
core: an 8-bit palette-index raster, optionally followed by a marker and a
1024-byte VGA palette of `256 × (R,G,B,pad)`.

Let `ps = filesize - 1024` for palette-bearing variants.

### 1. Sprite `M1` (126 files)

```text
0000  u16 width
0002  u16 height
0004  u8  pixels[width*height]
ps-8  4 bytes  30 00 af 00
ps-4  4 bytes  driver/extra word (varies; often 00 00 xx 00)
ps    1024-byte palette
```

Condition: `width*height == ps - 8 - 4`.

### 2. Screen `M2` (2 files with header, 25 full-screen without)

```text
# With header
0000  u16 width
0002  u16 height
0004  u8  pixels[width*height]
ps-4  4 bytes  00 00 ff 00
ps    1024-byte palette

# Without header
0000  u8  pixels[320*N]
...   4 bytes  00 00 ff 00
ps    1024-byte palette
```

Condition with header: `width*height == ps - 4 - 4`.
Condition without header: `(ps - 4) % 320 == 0`, height is `(ps-4)/320`.

### 3. HG screen (12 files)

Same as headerless `M2`, but the marker is `b0 00 ef 00` and the raster is
`320 × 110`.

### 4. Wide `M1` (12 files)

The 4-byte header contains logical sprite dimensions, but the raster is a full
`320 × 110` buffer. Marker is `30 00 af 00` plus 4 extra bytes. Used by
`TAST*.SEQ` and similar UI frames.

### 5. `FR` / `INTFR` / `MENUEFR` frames (98 files)

No palette is stored in the file. The engine shares the most recently loaded
VGA palette.

```text
0000  u16 logical_width
0002  u16 logical_height
0004  u16 pixel_width
0006  u16 pixel_height
0008  u8  pixels[pixel_width*pixel_height]
```

Condition: `filesize == 8 + pixel_width*pixel_height`.

### 6. Plain text `.SEQ` (8 files)

`AUSWOERT.SEQ`, `BILDDAT.SEQ`, `MATR.SEQ`, `OBW*.SEQ`, `VERBEN.SEQ`,
`VOREIN.SEQ` are DOS text with CRLF line endings and sometimes a trailing
`0x1a` EOF byte. CP437/CP850 are identical for the German letters used here:
`0x94 = ö` in `\x94ffne`, `0x81 = ü` in `s\x81den`, and `0xe1 = ß` in
`schlie\xe1e`. REA proves CP850 for the `TEXT*.REL` dispatcher; the plain
vocabulary tables are decoded with the same high-byte mapping. They are emitted
as JSON with UTF-8 text and a `lines` array.

## `.AWS` audio

```text
0000  20 bytes  magic "AUDIOS WAVE SLAVE PC" + padding
0014  u16       header field (e.g. 8046; close to 8 kHz, used as inference)
0016  u16       sample byte count
0018  u16       flags (commonly 0x0800)
0020  492 bytes remaining header/padding
0200  u8        samples[sample_byte_count]
```

Verified relation: `512 + sample_byte_count == filesize` for all 7 files.
Payload is unsigned 8-bit mono PCM. The extractor writes 8000 Hz WAV and marks
the rate as inferred.

## `.FON` fonts

`8X8PROP*.FON` are 16128 bytes = `256 × 63`. Each record is emitted as a hex
string in JSON. The records contain eight 8-byte bitplanes plus width/metric
bytes, but the exact proportional-metric layout was not fully resolved, so bytes
are preserved losslessly rather than guessed into glyph images.

## `.REL` resources

`TEXT1.REL`, `TEXT2.REL`, `TEXT3.REL`, `TEXT4.REL`, `TEXT5.REL`, `TEXT7.REL`,
`TEXT8.REL`, `TEXT9.REL`, and `TEXT10.REL` contain fixed 77-byte (`0x4d`)
records. REA-decoded dispatcher at `0x26c68` selects a file and zero-based
record from a 1-based id:

```text
v = id - 1
t > 0x9c3f -> TEXT10.REL, rec = t - 0x9c41
t > 0x88b7 -> TEXT9.REL,  rec = t - 0x88b9
t > 0x752f -> TEXT8.REL,  rec = t - 0x7531
t > 0x61a7 -> TEXT5.REL,  rec = t - 0x61a9
t > 0x4e1f -> TEXT7.REL,  rec = t - 0x4e1f
t > 0x3a97 -> TEXT4.REL,  rec = t - 0x3a98
t > 0x270f -> TEXT3.REL,  rec = t - 0x2710
t > 0x1387 -> TEXT2.REL,  rec = t - 0x1388
else       -> TEXT1.REL,  rec = t
```

Each record begins with a payload length; stored bytes are decoded as
`(stored + 0x14)` with `0x2f` mapped to space, then interpreted as CP850. The
extractor writes all non-empty records to `data/texts.json` and `lua/texts.lua`,
keyed by the original id. `HEXUMA.OVR` remains a conservative printable-run
scanner; it is not a complete bytecode interpreter.

In-code German parser messages are separate Pascal-string chains in
`HEXPRG.EXE`. The extractor decodes ten pools (`take`, `parser`, `examine`,
`move`, `door`, `ignite`, `openclose`, `drop`, `inventory`, `dispatch`) into
`data/code_strings.json` and `lua/code_strings.lua`. A pool pointer
`segment:offset` maps to file offset `segment * 16 + offset - 0x9a00`. These
fragments, not approximations, are used by the reconstructed verb handlers.

## `.BIN` tables

- `OBNINT*.BIN`: 1060 × 4 bytes = two little-endian `i16` values per noun. The
  second value (`room_gate`) is the room/visibility gate; a negative value aliases
  another noun id, and `0xffff` is globally visible. The generated JSON renders
  bytes in file order, so `"0300"` is the value `3`. The first value (`field_a`)
  is the 1-based LAND loader slot; the live file-word column is `field_a - 1`.
- `OBNBYT*.BIN`: 1060 × 3 bytes; the first byte array at file index `id - 1` is
  the original class byte emitted as `class` in the semantic vocabulary.
- `OBNWOR*.BIN`: 1060 × 4 bytes = two `u16` 1-based `TEXT*.REL` ids (`text_a`,
  `text_b`).
- `LAND.BIN`: 240 × 14 bytes = seven `i16` values. File word 0 is the room id;
  words 1..6 are the directional exits. The loader converts file word `j` to
  loader slot `j + 1`; negative exits are closed doors and are not travel
  targets.
- `OBLISTE.BIN`, `VORS.BIN`: emitted as `u16-le` arrays, plus decoded VORS
  hotspot records.

Some field meanings (especially the exact object-class taxonomy and most
`OBNINT.field_a` state uses) remain unresolved; raw values are preserved.

## `HEXUMA.OVR`

Dialogue strings are stored as:

```text
u8 length
u8 bytes[length]   // DOS CP437
```

The extractor scans plausible length prefixes, converts to UTF-8, and writes
`data/dialogue.json` plus the longest entries into `lua/dialogue.lua`.

## Semantic game data

`data/game.json` and `lua/game.lua` are derived from the raw tables:

- `LAND.BIN` → 240 rooms with six exits indexed by 0-based file words `1..6`.
  The engine retains the sign: a positive value is the destination room, `0`
  emits TEXT id `0x61`, and a negative value leaves the player in place and is
  silent unless a matching class-4 door object exists, in which case TEXT id
  `0x3c` is emitted. Room 1's record `(1,0,-18,-2,-3,6,0)` makes south closed and
  up traversable.
- `VERBEN.SEQ` → 346 verb name/id pairs.
- `OBW.SEQ` / `OBNINT.BIN` / `OBNBYT.BIN` / `OBNWOR.BIN` → 1026 base vocabulary
  entries with `id`, `group`, `prop`, `room_gate`, `class`, `text_a`, `text_b`.
- `OBW5.SEQ` + `OBNINT5.BIN` + `OBNBYT5.BIN` + `OBNWOR5.BIN` → 338 ship-scenario
  entries in `vocabulary_5`.
- `OBW6.SEQ` + `OBNINT6.BIN` + `OBNBYT6.BIN` + `OBNWOR6.BIN` → 583 mine-scenario
  entries in `vocabulary_6`.
- `TEXT*.REL` → 9131 decoded strings keyed by original id in `data/texts.json`.
- `BILDDAT.SEQ` → 271 picture-table values.
- `VORS.BIN` → 418 `click_regions` from records 1..170, including slots whose
  original Pascal string is empty or a single space (see below).
- `HEXUMA.OVR` compiled units → `data/overlay_rules.json`, 6,183 structured
  room/action rules with numeric `room_ranges` derived from the main dispatch
  at `0x11d46`. A twelfth rule block (`unit: 11`) comes from the main-module
  dispatcher at `0x13e7d` and covers only rooms 17 and 26, for a total of 6,950
  rules. Guards and actions are AST nodes; the runtime parser is
  `src/overlay_rules.zig` and the evaluator is `src/overlay_eval.zig`. The
  generated JSON is mirrored as `src/data/overlay_rules.json` for embedding, so
  `hexuma extract --input <original> --output <dir>` also writes a playable
  `data/overlay_rules.json`. Overlay fixup tables mark far-pointer segment words
  whose stored values are already absolute in the extracted code, so static rule
  extraction does not need a runtime relocation pass.

This layer is locale-independent. German labels come from the shipped tables;
English labels are authored in `src/locale_data.zig` and emitted as
`lua/locale.lua`.

## `VORS.BIN` click regions

`VORS.BIN` is `151677 = 171 × 0x377` bytes. Record `n` starts at file offset
`n * 0x377`; record 0 is anomalous. Records 1..170 are hotspot tables selected
by the current picture id (runtime global `0x32d0`), not by the room id:

```text
0000  u16                     active region count (values > 14 clamp to 1)
0002  15 × (i16,i16,i16,i16)   x1,y1,x2,y2 rectangles, logical 320x96 space
007a  15 × 51 bytes            Pascal string: u8 len, len CP437 bytes, padding
```

Each emitted `click_regions` item includes the original `slot` index so the
runtime can apply the flag/room-gated slot overwrites from `0x2408d`.

Only `len` bytes of each slot are meaningful; the remaining padding contains
stale authoring-tool data (including inert `LINEREL`/`PUTIMAGE` token names).
The extractor emits every slot with a valid rectangle, including labels with
length zero or one literal space. This is required because `0x2408d` clears and
overwrites slots by index: an initially blank slot can later become a command.
The X11 frontend uses these rectangles directly for mouse hit-testing; the
text parser receives the effective German label as the command.

## `OBLISTE.BIN` command menus

`data/action_menu.json` and `lua/action_menu.lua` contain the original `';'`
command menus. The binary layout is:

```text
0000  256 × u16 LE          byte offset of each room's block, 0 = no menu
....  u16 LE                count n (the original reads n + 1 strings)
....  (n + 1) × Pascal       u8 len, u8 len (repeated), len CP437 bytes
```

These are distinct from `VORS.BIN`: VORS supplies screen hit rectangles and
tooltips, OBLISTE supplies the text-command menu. Both are exposed by
`choices()` and use the same German parser commands.

## GUI image sibling format

Each decoded image also gets an `images/<name>.raw` file:

```text
0    6 bytes   "HXRAW2"
6    u16 LE    x
8    u16 LE    y
10   u16 LE    width
12   u16 LE    height
14   u8[]      BGRA pixels (4 bytes per pixel)
```

BGRA order matches a little-endian TrueColor visual. The GUI fits the picture
into the hotspot canvas with nearest-neighbour scaling.

## Engine save state

`hexuma play --save NN.dat --load NN.dat` writes and reads the original
two-file save state:

- `NN.dat`: 10,839 unpadded decimal lines with CRLF endings, emitted in the
  order of the 395 static call sites of `FUN_1d0d_0030` (`0x2d100`). Loops
  expand to 8 lines per landscape, 8 lines per object (7 numeric plus one
  Pascal string), and 50 inventory-name strings. Field descriptors live in
  `src/data/save_layout.json`. Landscape words are taken from the live mutable
  LAND table, so door state changes are saved; known 16-bit globals are written
  as words.
- `NN.sav`: `0x18d8` bytes of sampled VRAM plus a `0x404`-byte graphics-state
  block (7,388 bytes). The thumbnail is zeroed in the Zig frontend because no
  VGA framebuffer is available.

Paths without a `.dat`/`.sav` extension still use the portable JSON fallback:

```json
{"room":1,"moves":0,"score":0,"inventory":["wand"]}
```
