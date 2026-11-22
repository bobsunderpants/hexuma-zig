# Hexuma DOS rendering / asset / inventory reconstruction (read-only report)

## 0. Scope, method, and trust model

* **No project, source, or asset file was modified.** All extraction was read-only. Scratch
  disassembly/text files live only under `/tmp/opencode/` (`hexuma_probe.bin`,
  `probe2.bin`…`probe7.bin`, `hexuma-inventory-slots.txt`, this report).
* Evidence sources:
  * Ghidra/REA decompiled functions: `/tmp/opencode/hexuma-decompiled/functions/0x*.c`
  * Raw shipped files: `/home/bob/Downloads/Hexuma/` (`HEXPRG.EXE`, `HEXUMA.OVR`,
    `HEXUMA.BAT`, and the `.SEQ`/`.FON`/`.AWS` assets)
* Decompiler output is **provider pseudocode, not original source**. Numeric second
  arguments such as `14999` (`0x3a97`) and `0x3443` are frequently **segment artifacts**:
  Pascal string literals live in the **caller's CS**, not in the segment printed as the
  second argument. Raw bytes are authoritative for strings and call arguments
  (`file_offset = (caller_CS << 4) + literal_offset - 0x9A00`, with MZ header `0x6600`,
  load segment `0x1000`, Ghidra address = file offset + `0x9A00`).
* Everything below is labelled **Observed** (directly in decompiled code / raw bytes /
  asset names) or **Inferred** (interpretation of those facts).

---

## 1. Filename construction

### 1.1 Background images `HG`

**Observed** (`/tmp/opencode/hexuma-decompiled/functions/0x1d621.c:30-73`,
`FUN_1c89_0d91`):

```text
if byte[0x37f8] == 1: return                         ; line 30
pascal := int_to_pascal(param_1, maxlen=14)          ; line 35
if param_1 < 10: pascal := "0" + pascal              ; lines 36-42  (literal 0xd87 -> file 0x13c17)
name  := "hg" + pascal + ".seq"                      ; lines 43-49  (0xd89 -> 0x13c19, 0xd8c -> 0x13c1c)
ascii := pascal_to_ascii(name)                       ; line 50   (FUN_3a97_100c)
open ascii; read 0x8980 bytes at 0:A000 and 0x404 bytes palette; close  ; lines 51-60
bank_set; copy A000->VRAM; bank_restore              ; lines 61-64
copy palette[0xb0..0xef] into shadow 0x2ca2          ; lines 65-73
```

**Result:** `hg<NN>.seq`, zero-padded to two digits: `hg00.seq` … `hg09.seq`,
`hg10.seq` … (`0x1d621.c:35-49`).
**Raw corroboration:** those exact Pascal fragments exist at file offsets
`0x13c17` = `"0"`, `0x13c19` = `"hg"`, `0x13c1c` = `".seq"`.
**Assets:** `HG00.SEQ`…`HG12.SEQ` exist. `HG1.SEQ` also exists but is **not** produced by
this rule (anomaly; likely legacy/unused).

### 1.2 Scene backgrounds `BILD`

**Observed** (`/tmp/opencode/hexuma-decompiled/functions/0x2bffd.c:45-78,79-106,107-140`):

* A pre-load branch runs only when `dword[0xf2b0] != 1` and `byte[0x37f8] != 1`
  (`0x2bffd.c:45-46`). It reads a scene ID from the current stream
  (`FUN_3a97_021c`, line 48), converts it to decimal (line 49), prepends `"0"` when
  `byte[0xc918] < 10` (lines 50-56 — the decompiler compares a global, not the ID;
  **Inferred**: this is a zero-padding gate), then builds `"hg" + id + ".seq"`
  (lines 57-62; literals `0x27a`, `0x27c`, `0x27f` → file `0x2232A`, `0x2232C`,
  `0x2232F`) and loads/blits it (lines 63-78).
* Main path: `id := int_to_pascal(param_2)`; if `param_2 < 10` prepend one `"0"`;
  if `param_2 < 100` prepend another `"0"`; then `name := "bild" + id + ".seq"`
  (`0x2bffd.c:79-106`; literals `0x27a`, `0x28c`, `0x27f` → file `0x2232A`,
  `0x2233C`, `0x2232F`).

**Result:** `bild<NNN>.seq`, zero-padded to three digits: `bild001.seq`,
`bild021.seq`, `bild134.seq` … (`0x2bffd.c:83-106`).
**Raw corroboration:** file `0x2232A` = `"0"`, `0x2232F` = `".seq"`, `0x2233C` = `"bild"`.
**Assets:** 123 `BILD*.SEQ` files, including all scene numbers used by the overlay table.

### 1.3 Conditional `FR` overlays (58 entries)

**Observed** (`/tmp/opencode/hexuma-decompiled/functions/0x2bffd.c:141-693`): a table of
58 Pascal strings at caller CS `0x2bab`, offsets `0x299 + 12*i`, file `0x22349 + 12*i`,
first entry `fr00101.seq`, last `fr13401.seq`. Each is loaded and handed to
`FUN_2bab_0010` (`/tmp/opencode/hexuma-decompiled/functions/0x2bac0.c:41-92`).

The effective gate is `param_2 == scene` **and** the listed flag test. The long
`param_2 != …` clauses in the decompiled `else if` chain are just chain guards and are
omitted below; the source line is given for exact reconstruction.

| scene | file | gate (effective) | line |
|---:|---|---|---:|
| 1 | `fr00101.seq` | `byte[0x5e31] == 0` | 145 |
| 1 | `fr00103.seq` | `byte[0xf2fb] == 0` | 154 |
| 1 | `fr00104.seq` | `byte[0xf2fb] == 1` | 163 |
| 1 | `fr00107.seq` | `byte[0x5fa7] == 0` | 171 |
| 4 | `fr04!01.seq` | `byte[0xf306] == 0` | 183 |
| 4 | `fr04!02.seq` | `byte[0xf306] == 1` | 191 |
| 5 | `fr05!02.seq` | `byte[0x5fab] == 0` | 202 |
| 5 | `fr05!01.seq` | `byte[0x5fab] == 1` | 210 |
| 8 | `fr08!01.seq` | `byte[0xf319] == 1` | 221 |
| 9 | `fr00901.seq` | `dword[0x6658] == 0x42d` | 232 |
| 9 | `fr00902.seq` | `byte[0x5ef2] == 0` | 241 |
| 9 | `fr00903.seq` | `byte[0x5fb6] == 0` | 250 |
| 9 | `fr00904.seq` | `byte[0x5fb3] == 0` | 259 |
| 9 | `fr00905.seq` | `byte[0x5fb0] == 0` | 267 |
| 10 | `fr10!01.seq` | `byte[0x525e] != 3` | 278 |
| 10 | `fr10!02.seq` | `byte[0x5fb6] == 0` | 286 |
| 11 | `fr11!01.seq` | `dword[0x46c0] != 10` | 296 |
| 14 | `fr14!01.seq` | `byte[0x52c9] != 3` | 308 |
| 14 | `fr14!02.seq` | `byte[0xf329] == 3` | 316 |
| 21 | `fr02101.seq` | `byte[0xbe1b] == 'D' && dword[0x685a] == 0x62be` | 328 |
| 21 | `fr02102.seq` | `byte[0xbe1b] == 'E'` | 337 |
| 21 | `fr02103.seq` | `byte[0xbe1b] == 'E' && byte[0x5ff9] == 2` | 346 |
| 21 | `fr02104.seq` | `byte[0xbe1b] == 'E' && byte[0x5ff9] == 4` | 355 |
| 21 | `fr02105.seq` | `byte[0xbe1b] == 'E' && dword[0x686a] == 0x62f5` | 363 |
| 28 | `fr02801.seq` | `byte[0xbe1b] == byte[0x4928]` | 374 |
| 28 | `fr02802.seq` | `byte[0xbe1b] != byte[0x4928]` | 382 |
| 36 | `fr03601.seq` | `byte[0xf3f3] == 1` | 392 |
| 37 | `fr03701.seq` | `byte[0xf3f8] == 1` | 402 |
| 38 | `fr03802.seq` | `byte[0xf3ff] == 1` | 412 |
| 43 | `fr04301.seq` | `byte[0xf385] == byte[0xbe1b]` | 423 |
| 47 | `fr04701.seq` | `byte[0xbe1b] == byte[0x4b5c]` | 433 |
| 48 | `fr04801.seq` | `byte[0xf386] == byte[0xbe1b]` | 443 |
| 49 | `fr04901.seq` | `byte[0xbe1b] == byte[0x4b9a]` | 454 |
| 49 | `fr04902.seq` | `byte[0xf38d] == 2` | 462 |
| 91 | `fr09101.seq` | `byte[0xf3a2] == 0` | 472 |
| 94 | `fr09401.seq` | `byte[0xf3b1] == 3` | 482 |
| 65 | `fr06501.seq` | `dword[0xb41e] == 0x7d` | 492 |
| 75 | `fr07501.seq` | `byte[0x605f] == 0` | 502 |
| 78 | `fr07801.seq` | `byte[0xf36c] == 2` | 513 |
| 78 | `fr07802.seq` | `byte[0xf36c] == 0 || byte[0xf36c] == 3` | 521 |
| 111 | `fr11102.seq` | `byte[0xf41c] == 0 && byte[0xf418] == 0` | 533 |
| 111 | `fr11101.seq` | `byte[0xf41c] == 0 && byte[0xf418] == 1` | 541 |
| 118 | `fr11801.seq` | `byte[0xf439] == 0` | 553 |
| 118 | `fr11802.seq` | `byte[0xf431] != 3 && byte[0xbe1b] != -0x51` | 561 |
| 122 | `fr12201.seq` | `byte[0xf440] == 1` | 571 |
| 124 | `fr12401.seq` | `byte[0xf445] == 1` | 581 |
| 125 | `fr12501.seq` | `byte[0xf449] == 1` | 591 |
| 126 | `fr12601.seq` | `byte[0x6103] == 0` | 601 |
| 127 | `fr12701.seq` | `byte[0xf44e] == 0` | 612 |
| 127 | `fr12704.seq` | `dword[0xf452] == 0xc3 && byte[0xf44f] == 0` | 622 |
| 127 | `fr12703.seq` | `dword[0xf452] == 0xc3 && byte[0xf44f] == 1` | 630 |
| 127 | `fr12702.seq` | `byte[0xf44f] == 0` (else branch) | 639 |
| 130 | `fr13001.seq` | `byte[0xf456] != 0 && byte[0xf456] < 3` | 650 |
| 130 | `fr13002.seq` | `byte[0xf456] == 0x1e` | 658 |
| 132 | `fr13201.seq` | `dword[0xb894] == 0xe9` | 668 |
| 134 | `fr13402.seq` | `byte[0xf45e] == 1` | 679 |
| 134 | `fr13401.seq` | `dword[0x6bc4] != 0` | 687 |

After the overlays, if `byte[0xf2fa] == 1` palette indices `0x30..0xaf` are zeroed;
then `FUN_3443_034b(0x2c9e)` restores the palette, the VRAM bank is set, a final
stream-driven blit loop runs, and the bank is restored
(`/tmp/opencode/hexuma-decompiled/functions/0x2bffd.c:694-734`).

### 1.4 Intro / `INTFR`

**Observed** (`/tmp/opencode/hexuma-decompiled/functions/0x27419.c:48-148`):

* Fixed loads: `intro00.seq` (offset `0xab34`, line 48), `intro01.seq` (`0xab40`, line 56),
  `intfr01.seq` (`0xab4c`, line 67), `intfr02.seq` (`0xab58`, line 76),
  `intfr00.seq` (`0xab64`, line 87), then `intro02.seq` (`0xab7d`, line 146).
* Variable frames: `n := 3`; while `n != 0x16` and no key pressed:
  `name := "intfr" + (n < 10 ? "0" : "") + decimal(n) + ".seq"`.
  Literals: `"0"` at `0xab70`, `"intfr"` at `0xab72`, `".seq"` at `0xab78`
  (raw file `0x1da00`, `0x1da02`, `0x1da08`); `int_to_pascal` at lines 93 and 118,
  concatenation at lines 94-106 / 119-131, load+blit at 107-109 / 132-134.
  Loop/exit at lines 114-140.

**Result:** `intfrNN.seq` with two-digit zero padding, `N = 3..22`.
**Assets:** `INTFR00.SEQ`…`INTFR22.SEQ`, `INTRO00..02.SEQ` all exist.

### 1.5 Menu frames `MENUEFR`

* **Observed (raw only):** `HEXPRG.EXE` file `0x14166` = Pascal `"menuefr"` (len 7),
  `0x1416e` = `".seq"` (len 4). Assets `MENUEFR1.SEQ`…`MENUEFR6.SEQ` exist.
* **Inferred:** the menu loader builds `menuefr<N>.seq` with **no zero padding**
  (single-digit IDs 1–6), by the same `int_to_pascal` + append pattern used for
  `intfr`/`bild`. No call site for these two literals appears in the 398 exported
  decompiled functions, and REA `xrefs`/`trace_feature` return no references at
  Ghidra `0x1db66`; therefore the exact call site is **not confirmed**. Treat the
  filename shape as strongly supported by the raw string pair + asset names, but the
  builder location as unresolved.

### 1.6 Inventory / status assets

**Observed** (`/tmp/opencode/hexuma-decompiled/functions/0x200f9.c:38-46,618-633`):

* Background: `"land" + decimal(param_2) + ".seq"` (no padding; literals `0x384f`,
  `0x3854` in CS `0x3443` → raw `0x166df` `"land"`, `0x166e4` `".seq"`;
  `int_to_pascal(maxlen=14)` at line 39, append at 43-45).
  Assets `LAND1.SEQ`…`LAND7.SEQ` exist; `LAND.BIN` also exists.
* On exit: `"obfl.seq"` (literal `0x3859` → raw `0x166e9`) is loaded via
  `FUN_2bab_0de0` (lines 619-622), and the status line is built as
  `">" + string[0xc9c2] + "    "` (literals `0x3862` → raw `0x166f2`,
  `0x3864` → raw `0x166f4`) and passed to `FUN_2bab_145d` (lines 629-633).
* Startup also loads `obfl.seq` (`0x278a3.c:226-231`, literal `0xb004` → raw
  `0x1de94`) and `menue1.seq` (`0x278a3.c:201-217`, literal `0xaff9` → raw
  `0x1de89`), plus `8X8prop.fon` / `8X8prop1.fon` / `8X8prop2.fon`
  (`0xafd3`, `0xafdf`, `0xafec` → raw `0x1de63`, `0x1de6f`, `0x1de7c`) and
  `house.aws` (`0xafc9` → raw `0x1de59`, used at `0x278a3.c:114`).
  Literal `0xb00d` → raw `0x1de9d` = `"CROSS"` (5 bytes), used at `0x278a3.c:232`.

---

## 2. Palette, screen, and blit rules

**Observed facts**

* Screen is **320×200, 8 bits/pixel, 64,000 bytes at `A000:0000`**: startup reads
  width/height words into `0x1cdc`/`0x1cde`, multiplies them into `0x1cd0`, reads that
  many bytes into the buffer at `0x1ce0`, and computes `dword[0x2c92] = 0x1cde * 0x140`
  (`/tmp/opencode/hexuma-decompiled/functions/0x278a3.c:201-224`; `0x140` = 320).
  Inventory clears exactly `64000` bytes at `A000:0000`
  (`/tmp/opencode/hexuma-decompiled/functions/0x200f9.c:35-37`).
* Every VRAM access is bracketed by `FUN_3443_23dc()` / `FUN_3443_23b2()` — VRAM
  bank/page select and restore (e.g. `0x1d621.c:61-64`, `0x200f9.c:27-30`,
  `0x200f9.c:35-37`, `0x2bffd.c:74-77`; definitions
  `/tmp/opencode/hexuma-decompiled/functions/0x3680c.c:13-25`,
  `0x367e2.c:13-25`).
* Palette RAM is addressed through an indirect vector at `0xf46e`:
  `FUN_3443_0335(ptr)` sets, `FUN_3443_034b(ptr)` restores
  (`/tmp/opencode/hexuma-decompiled/functions/0x34765.c:13-20`,
  `0x3477b.c:13-20`).
* Palette state is a **1024-byte shadow at `0x2c9e`** (256 entries × 4 bytes, only
  bytes 0–2 used): inventory copies it to a local backup (`0x200f9.c:38`), HG sets
  indices `0xb0..0xef` before load (`0x1d621.c:31-34`) and restores exactly that
  range from the loaded file afterwards (`0x1d621.c:65-73`, stride 4 at `+0x2ca2`).
  Intro code uses ranges `0xfc..0xfe`, `0xfb..0xfc`, `0xfd..0xfe`
  (`0x27419.c:61-63,90-92,111-113`). BILD normalizes `0x30..0xaf` when
  `byte[0xf2fa] == 1` (`0x2bffd.c:697-708`, same pattern in `0x2c890.c:31-39`).
* Generic SEQ blit helper `FUN_2bab_0010`
  (`/tmp/opencode/hexuma-decompiled/functions/0x2bac0.c:41-92`): converts the Pascal
  name to an ASCII file buffer, opens it, reads four 2-byte header fields
  (lines 50-57), reads a 16-bit length, reads that many bytes (lines 58-65), then
  iterates a record loop of 16-bit coordinates plus a byte-run copied with
  `FUN_3a97_1249` (lines 68-87), and finally applies the palette with
  `FUN_3a97_0341` (line 92). **Inferred:** the 4 header words are the
  destination rectangle/dimensions and the records are RLE-like pixel runs; the
  exact field names cannot be recovered from the mangled decompilation.
* Buffers: `FUN_3a97_100c` = Pascal→ASCII filename (`0x3b97c.c:13-45`),
  `FUN_3a97_103a` = open (`0x3b9aa.c:13-46`), `FUN_3a97_1125` = counted read/allocate
  (`0x3ba95.c:14-63`), `FUN_3a97_10bb` = free/close (`0x3ba2b.c:13-35`),
  `FUN_3a97_1249` = memcpy (`0x3bbb9.c:13-38`), `FUN_3a97_126c` = memset
  (`0x3bbdc.c:13-26`), `FUN_3a97_0a9d` = integer→Pascal decimal
  (`0x3b40d.c:13-54`), `FUN_3a97_062a` = length-prefixed copy (`0x3af9a.c:13-33`),
  `FUN_3a97_06b7` = append (`0x3b027.c:13-41`), `FUN_3a97_0644` = clamped copy
  (`0x3afb4.c:13-36`), `FUN_3a97_0207/020e` = get/clear DOS error
  (`0x3ab77.c:13-24`, `0x3ab7e.c:13-23`).

---

## 3. Inventory display and input

**Observed** (`/tmp/opencode/hexuma-decompiled/functions/0x200f9.c`,
`FUN_1c89_3869`, lines 27-637):

1. `27-31`: select VRAM bank, copy 64,000 bytes from the saved screen buffer at
   `[0x2c92]` to `A000:0000`, restore bank.
2. `31-37`: set palette from `0x2c9e`, zero the two palette-range words, call
   `FUN_2bab_10db(0x2c9e)`, then clear all 64,000 bytes of `A000:0000`.
3. `38`: back up 0x404 bytes of palette `0x2c9e` into a local.
4. `39-46`: build `land<param_2>.seq` and load it with `FUN_2bab_0de0`.
5. `47-603`: for page `param_2 ∈ 1..7`, for each item-flag word, if
   `dword[flag] == 0`, call `FUN_3443_2ee4(x1,y1,x2,y2)`.
   `FUN_3443_2ee4` is an indirect call through `word[0xf496]`
   (`/tmp/opencode/hexuma-decompiled/functions/0x37314.c:13-20`) — **Inferred**: it
   clears/marks an inventory slot rectangle.
   There are **181 slot calls**: page 1 = 22, page 2 = 27, page 3 = 10, page 4 = 34,
   page 5 = 11, page 6 = 24, page 7 = 53. The complete machine-generated table
   (page | coordinates | source line | flag address) is in
   `/tmp/opencode/hexuma-inventory-slots.txt`. Example: page 1, `0x38c2 == 0` →
   `(0x98,0xf4,0x7b,0xcd)` at `0x200f9.c:48-50`.
6. `604-605`: restore bank, call `FUN_2bab_0e7a(0x2c9e)` (palette refresh).
7. `606-617`: input wait — poll `FUN_3443_296e()` (mouse/key) then
   `FUN_39df_02fa()` until a key is returned; if a key exists,
   `local_41b = FUN_39df_030c()`; then poll until `byte[0xf481] == 0`
   (key-release). Input poll helper: `/tmp/opencode/hexuma-decompiled/functions/0x36d9e.c:13-46`.
8. `618-637`: `FUN_2bab_10db`, bank select, load `obfl.seq`, copy the screen buffer
   back from `A000`, find the selected text slot with `FUN_2bab_12fa`, construct
   `">" + [0xc9c2] + "    "` and pass it to `FUN_2bab_145d`, restore bank, restore
   saved palette, call `FUN_2bab_0e7a`.

**Inferred interpretation:** the inventory is a full-screen 320×200 `LAND<n>`
image with per-slot rectangles blanked for flags that are zero; the loop is a
modal wait for one key/selection; on exit the object-flag overlay (`obfl.seq`) and
a textual status/prompt line are restored.

---

## 4. Startup order and resident assets

**Observed** (`/tmp/opencode/hexuma-decompiled/functions/0x278a3.c:28-266`,
`FUN_1c89_b013`):

| order | lines | action |
|---:|---|---|
| 1 | 28-33 | save old `0xb16` vector into `0xf2a0/0xf2a2`; install `0x1c89:0xaf44`; init runtime (`FUN_39df_01c2`) |
| 2 | 34-77 | clear 10×256-byte table at `0x2100`; set defaults: `0x2c00=10`, window geometry `0x19c0=0x7a`, `0x19c4=0xc0`, `0x19c8=0x128`, `0x19cc=0x1a`, `0x37f0=(0x19c8-0x19cc)-0x36`; zero several flags; copy version string into `0x36de` from `0x2ae7:0xaf98`; clear font tables `0x19d0` (256 words) and object flags `0x1838` |
| 3 | 79-86 | graphics/mode check `FUN_3443_0cf1(0xb7d4,0x1c89)`; on failure print message at `0x3443:0xafa2` and set `byte[0x34d8]=1` |
| 4 | 88-126 | `FUN_3443_1763(45000,…)`, `FUN_3443_0143(1)`; clear 256×4-byte tables `0x1cfe`; set palette range `0x1cfa=0`, `0x1cfc=0xff`, `FUN_3443_034b`; optional save-slot count from `FUN_2ae7_0014`; call intro/INTFR routine `FUN_1c89_ab89()` (`0x27419.c`); optional re-query; clear/set `byte[0x36ed]` based on save presence |
| 5 | 127-149 | allocate three 256-entry pointer tables at `0x1438`, `0x1038`, `0xc38` using `FUN_3443_06db(7,6,…)` + `FUN_3443_0a88` and the font buffer at `0x1938` |
| 6 | 150-200 | open/load three font tables via files at `0xafd3` (`8X8prop.fon`), `0xafdf` (`8X8prop1.fon`), `0xafec` (`8X8prop2.fon`), each: 256-byte header at `0x1838` then 256 pointers of `word[0x193a]` bytes |
| 7 | 201-224 | open `menue1.seq` (`0xaff9`), read width/height `0x1cdc/0x1cde`, total pixels `0x1cd0`, pixel buffer at `0x1ce0`; compute screen bytes `dword[0x2c92] = 0x1cde*0x140` and `0x1cee` |
| 8 | 225-231 | build/load `obfl.seq` (`0xb004`) via `FUN_2bab_0de0`; set palette `0x2c9e=0`, `0x2ca0=0xff`, `FUN_2bab_0e7a`, `FUN_3443_034b` |
| 9 | 232-247 | set cursor/sprite `FUN_3443_1b59(0xb00d /* "CROSS" */, 0x1c89)` and `FUN_3443_1c1a(0xe529,0x1c89)`; center it with `FUN_3443_04e6/04f9/25b3`; count three tables with stride `0x65` |
| 10 | 248-265 | on any load failure set `byte[0x34d8]=1` (error state); return |

**Resident after startup (Inferred from the writes):** 320×200 screen buffer size in
`0x2c92`; palette shadow `0x2c9e`; three 256-entry font glyph-pointer tables;
`menue1.seq` pixel data; `obfl.seq` object flags; menu cursor `CROSS`. All are
referenced later by the inventory/HG/BILD paths.

---

## 5. Reconstructed pseudocode (analysis form, not original source)

```c
// HG background — 0x1d621.c:30-73
void load_hg(int id) {
    if (flags.37f8 == 1) return;
    p = dec_pascal(id, 14);                 // 0x1d621.c:35
    if (id < 10) p = prepend(p, "0");       // 0x1d621.c:36-42
    name = append(append("hg", p), ".seq"); // 0x1d621.c:43-49
    load_seq_to_screen_and_palette(name, A000, screen_size); // 51-60
    select_bank(); memcpy(vram, A000, screen_size); restore_bank(); // 61-64
    for (i = 0xb0; i <= 0xef; i++)          // 65-73
        palette_shadow[0x2ca2 + i*4 .. +2] = file_palette[i*4 .. +2];
}

// BILD scene — 0x2bffd.c:45-140, 141-693, 694-734
void load_bild(int scene) {
    if (flags.f2b0 != 1 && flags.37f8 != 1) {
        id = stream_read_word();            // pre-load branch; 45-78
        p  = dec_pascal(id, 14);
        if (flags.c918 < 10) p = prepend(p, "0");   // decompiler-observed gate
        load_hg_like("hg" + p + ".seq");
    }
    p = dec_pascal(scene, 14);               // 79-106
    if (scene < 10)  p = prepend(p, "0");
    if (scene < 100) p = prepend(p, "0");
    load_seq("bild" + p + ".seq");           // header + palette at 107-140
    for each (scene, flag_test, filename) in OVERLAY_58_TABLE:  // 141-693
        if (scene == param_2 && flag_test) blit_seq(filename); // 0x2bac0.c:41-92
    if (flags.f2fa == 1) clear_palette_range(0x30, 0xaf);       // 697-708
    restore_palette(0x2c9e);
    select_bank(); final_stream_blit_loop(); restore_bank();    // 712-730
}

// Intro frames — 0x27419.c:48-148
void play_intro(void) {
    blit("intro00.seq"); blit("intro01.seq"); blit("intfr01.seq");
    blit("intfr02.seq"); blit("intfr00.seq");
    for (n = 3; n != 0x16 && !key_pressed(); n++) {
        p  = dec_pascal(n, 16);
        if (n < 10) p = prepend(p, "0");
        blit("intfr" + p + ".seq");          // 0x27419.c:93-109,118-134
    }
    blit("intro02.seq");
}

// Inventory — 0x200f9.c:27-637
void show_inventory(int page) {
    select_bank(); memcpy(vram, saved_screen, 64000); restore_bank(); // 27-30
    set_palette(0x2c9e); clear_vram(64000); backup_palette();         // 31-38
    blit("land" + dec_pascal(page,14) + ".seq");                     // 39-46
    if (page == 1) { if (flag[0x38c2]==0) fill_rect(0x98,0xf4,0x7b,0xcd); /* ... */ }
    /* ... pages 2..7; 181 total (flag==0) slot tests ... */          // 47-603
    restore_bank(); refresh_palette(0x2c9e);                         // 604-605
    do { poll_input(); } while (!key && !some_other_key());           // 606-610
    if (key) selected = read_selection();                             // 611-614
    do { poll_input(); } while (key_down);                            // 615-617
    refresh_palette(0x2c9e); select_bank(); blit("obfl.seq");         // 618-622
    /* find selected text slot */                                     // 625-628
    status = ">" + text[0xc9c2] + "    "; show_status(status);        // 629-633
    restore_bank(); restore_saved_palette(); refresh_palette(0x2c9e); // 634-636
}
```

---

## 6. Globals table (addresses are Ghidra linear/DOS data addresses)

| address | meaning (Observed / Inferred) | mutations seen |
|---|---|---|
| `0x2c92` (dword) | **O** screen byte count, `height * 320` (64000) | set at startup `0x278a3.c:219-221`; used for all A000 copies |
| `0x2c9e`, `0x2ca0` (words) | **O** active palette range start/end | HG `0xb0/0xef` (`0x1d621.c:32-33`); BILD `0x30/0xaf` (`0x2bffd.c:139-140`); inventory `0/0xff` (`0x200f9.c:32-34`); intro `0xfb..0xfe` (`0x27419.c:61-63,90-92,111-113`) |
| `0x2ca2` + `4*i` | **O** 1024-byte palette shadow (3 used bytes per entry) | HG restore `0x1d621.c:65-73`; BILD/inventory zeroing |
| `0x37f8` (byte) | **O** background/HG suppression flag | tested `0x1d621.c:30`, `0x2bffd.c:45`; cleared startup `0x278a3.c:59` |
| `0xf2b0` (dword) | **O** BILD pre-load suppression | tested `0x2bffd.c:45`; cleared startup `0x278a3.c:57` |
| `0x37f9` (byte) | **O** alternate pre-load header source | `0x2bffd.c:46,128-132`; cleared startup `0x278a3.c:51` |
| `0xc918` (byte) | **O** pre-load zero-pad counter/gate | `0x2bffd.c:50`; set to 1 at startup `0x278a3.c:58` |
| `0x32d0` (word) | **O** stream id from BILD pre-load | `0x2bffd.c:80` |
| `0x2c96`, `0x2c98` | **O** 16-bit BILD header fields | `0x2bffd.c:109-112` |
| `0x30a2`, `0x30a4` | **O** alternate BILD header fields | `0x2bffd.c:134-137` |
| `0xbe1b` (byte) | **O** current object/character id; gates many FR overlays and inventory status | read `0x2bffd.c:325-363,371-387,421-459,561`; written elsewhere (not in these functions) |
| `0xf2fb` | **O** scene-1 flag choosing `fr00103`/`fr00104` | `0x2bffd.c:151,160` |
| `0xf306` | **O** scene-4 flag | `0x2bffd.c:180,189` |
| `0x5fab` | **O** scene-5 flag | `0x2bffd.c:199,208` |
| `0xf319` | **O** scene-8 flag | `0x2bffd.c:219` |
| `0x6658`, `0x46c0`, `0xb41e`, `0xb894`, `0x6bc4` (dword) | **O** scene 9/11/65/132/134 gates | `0x2bffd.c:229,294,490,666,685` |
| `0x5e31`, `0x5fa7`, `0x5ef2`, `0x5fb6`, `0x5fb3`, `0x5fb0`, `0x525e`, `0x52c9`, `0xf329`, `0x5ff9`, `0x686a` | **O** scene-1/9/10/14/21 flags | `0x2bffd.c:142,169,238,247,256,264,275,284,305,314,343-368` |
| `0x4928`, `0x4b5c`, `0x4b9a`, `0xf385`, `0xf386`, `0xf38d` | **O** scene 28/43/47/48/49 equality gates | `0x2bffd.c:371,380,421,431,441,451,460` |
| `0xf3f3`, `0xf3f8`, `0xf3ff`, `0xf3a2`, `0xf3b1`, `0x605f`, `0xf36c` | **O** scene 36/37/38/91/94/75/78 gates | `0x2bffd.c:390,400,410,470,480,500,510,519` |
| `0xf41c`, `0xf418`, `0xf439`, `0xf431`, `0xf440`, `0xf445`, `0xf449`, `0x6103`, `0xf44e`, `0xf452`, `0xf44f`, `0xf456`, `0xf45e` | **O** scene 111/118/122/124/125/126/127/130/134 gates | `0x2bffd.c:529-684` |
| `0xf2fa` (byte) | **O** palette-normalization enable | `0x2bffd.c:697`, `0x2c890.c:31` |
| `0x1cdc`, `0x1cde` (words) | **O** screen width/height from `menue1.seq` | `0x278a3.c:205-207` |
| `0x1cd0` (dword), `0x1cd2` (word) | **O** pixel count / high word | `0x278a3.c:209-210` |
| `0x1ce0` (far ptr), `0x1cee` | **O** pixel buffer and normalized pointer | `0x278a3.c:211-224` |
| `0x1938`, `0x193a`, `0x193c` | **O** font load segment, per-glyph byte count, file handle | `0x278a3.c:129-199` |
| `0x1438`, `0x1038`, `0xc38` (word arrays) | **O** three 256-entry font glyph pointer tables | allocated `0x278a3.c:127-149`, filled 150-200 |
| `0x19c0/0x19c4/0x19c8`, `0x19cc` | **O** window geometry | set `0x278a3.c:39-46` |
| `0x37f0` | **O** derived width `(0x19c8-0x19cc)-0x36` | `0x278a3.c:47` |
| `0x19d0` (word[256]) | **O** font width/offset table | cleared `0x278a3.c:74-76`; read by `0x1c89_078e`/`0x1c89_0490` |
| `0x1838` (byte[256]) | **O** object/flag width table | zeroed in startup loop `0x278a3.c:146`; read `0x1cd20.c:26` |
| `0x36dc`, `0x36de` | **O** savefile presence and filename (`house.aws`) | `0x278a3.c:64-66,103-125` |
| `0x1cfa`, `0x1cfc` | **O** startup palette range | `0x278a3.c:98-101` |
| `0x34d8` (byte) | **O** error/failure flag | set on every startup load failure `0x278a3.c:85,250-262` |
| `0xf481` (byte) | **O** key-down/poll byte | `0x200f9.c:608,616-617`; polled by `0x36d9e.c:13-46` |
| `0xc9c2` | **O** current status text pointer | used `0x200f9.c:631` |
| `0x38c2 … 0x402c` | **O** item-flag word array; 181 tested addresses, some reused across pages/slots | only read (`== 0`) in `0x200f9.c:47-603`; full list in `hexuma-inventory-slots.txt` |
| `0xf496` (word) | **O** indirect vector for slot fill/clear routine | called by `FUN_3443_2ee4`, `0x37314.c:18` |
| `0xf46e` (word) | **O** indirect vector for palette set/restore | `0x34765.c:18`, `0x3477b.c:18` |

---

## 7. Limitations / unresolved points

* **MENUEFR builder call site unresolved** (see §1.5). Filename shape is inferred from
  raw fragments + assets, not from a located decompiled call.
* `FUN_2bab_0010` record semantics and `FUN_3443_2ee4` rectangle semantics are
  **Inferred**; their decompiled forms are thunks/indirect calls and raw record
  layout was not fully reconstructed.
* The BILD pre-load padding test uses `byte[0xc918]` rather than the streamed ID in
  the decompiled text (`0x2bffd.c:50`); this may be a decompiler artifact.
* `HG1.SEQ` is an extra asset not generated by the coded `hg<NN>.seq` rule.
* Ghidra/REA string inventory does not index Pascal strings; `trace_feature("menuefr")`
  and `xrefs(0x1db66)` returned empty, which is **not** proof that no reference exists
  outside the exported 398 functions.
* All Ghidra names/comments/types were treated as untrusted; raw bytes and shipped
  filenames were used as corroboration throughout.
