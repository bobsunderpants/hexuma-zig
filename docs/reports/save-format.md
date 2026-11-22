# DOS Hexuma — original save/load format (research report)

## 0. Scope, method, address conventions

**Target:** shipped `/home/bob/Downloads/Hexuma/HEXPRG.EXE` (208,320 bytes, 2000-02-14). `HEXUMA.OVR` was *not* needed for the save path and was not analysed. No project/asset file was modified; this report is the only output.

Primary sources:

| Source | Meaning |
|---|---|
| `/tmp/opencode/hexuma-decompiled/functions/0x22b1f.c` | REA/Ghidra pseudocode for `FUN_1c89_628f` (`0x1c89:0x628f`), lines 1–565 |
| `/tmp/opencode/save_func_dis_full.txt` | raw `objdump -D -b binary -m i8086` of `0x22b1f..0x23b23`, line numbers used below |
| `/tmp/opencode/dat_writer_complete_intel.txt` | raw disassembly `0x2d100..0x31044` (the `.dat` writer) |
| `/tmp/opencode/dat_reader_full_intel.txt` | raw disassembly `0x31076..0x34431` (the `.dat` reader) |
| `/tmp/opencode/hexuma-decompiled/functions/*.c` | helper pseudocode |

Address mapping (verified by matching bytes):

- REA linear = `0x1c890 + CS offset` for `CS=0x1c89`; file offset = linear − `0x9a00`.
- Raw far call `0x2a97:off` = REA `FUN_3a97_xxxx` at `0x3a970+off` (e.g. `0x2a97:0x100c` → `0x3ba1c`).
- `0x2443:off` = REA `FUN_3443_xxxx` at `0x34430+off`.
- `0x1d0d:0x30` → linear `0x2d100` (file `0x23700`) = `.dat` writer.
- `0x1d0d:0x3fa6` → linear `0x31076` (file `0x27676`) = `.dat` reader.
- Main function entry `0x22b1f` = file `0x1911f`; Pascal string table `0x1905b..0x1911b` in the file.

**No checksum of any kind exists in any save/load write or read path** (observed across the whole `0x22b1f` function and both `.dat` helpers).

---

## 1. Files produced by the save/load screen

All names are Pascal strings (length byte + chars). Decoded from file bytes `0x1905a..0x1911b`:

| CS:offset | string | used for |
|---|---|---|
| `0x61cb` | `SAPIC.TMP` | preview/scratch 0x18d8+0x404 image |
| `0x61d5` | `SAVE.TMP` | full-screen scratch 0x8980+0x404 |
| `0x61de` | `HG00.SEQ` | startup background image |
| `0x61e7` | `SAVEBOX.SEQ` | save-box layout/name template |
| `0x61f3` | `0` | zero prefix for slot numbers < 10 |
| `0x61f5` | `LADEN` | load button/title |
| `0x61fb` | `SPEICHERN ` | save button/title |
| `0x6206` | `.sav` | save-image extension |
| `0x620b` | `Nichts gespeichert!` | nothing-saved message |
| `0x621f` | `SPEICHERN` | save label |
| `0x6229` | `LADEN ` | load label |
| `0x6230` | `Existiert bereits!` | slot already exists |
| `0x6243` | `.dat` | state-data extension |
| `0x6248` | `Fehler beim Laden!` | load error |
| `0x625b` | `Fehler beim Speichern!` | save error |
| `0x6272` | `Platte voll??!` | disk-full writer return 2 |
| `0x6281` | `hg` | HG sequence prefix |
| `0x6284` | `.seq` | HG extension |
| `0x6289` | `>` | prompt |
| `0x628b` | `   ` | spacing |

Raw string bytes: `/home/bob/Downloads/Hexuma/HEXPRG.EXE:0x1905b..0x1911b`.

Slot naming (observed, `0x22b1f.c:206-217`, `502-515`; raw `0x22e00..0x22e60`, `0x23907..`):

- number = `FUN_3a97_0a9d(14, buf, SS, 0, slot, 0)` → decimal ASCII with **length byte = digit count, no padding** (`FUN_0a9d` raw `0x3b40d:0x3b413-0x3b455`, `/tmp/opencode/hexuma-decompiled/functions/0x3b40d.c:13-39`).
- if `slot < 10`, prefix literal `'0'` from `CS:0x61f3`, then append number, then copy at most 10 chars → `"00".."09"`.
- append `.sav` or `.dat` → **`"00.sav" .. "99.sav"` / `"00.dat" .. "99.dat"`**.
- HG image: decimal of global `DS:0xc918`, same optional zero prefix, wrapped `hg` + `.seq` → **`"hg00.seq" .. "hg99.seq"`** (DOS case-insensitive; shipped files are `HG00.SEQ`…).
- `FUN_0a9d`'s `param_1` (10 or 14) is only a *maximum field width*; with `param_3=0` it does not pad.

---

## 2. `.sav` — exact binary layout

Two 16-bit little-endian fields, written with `FUN_3a97_112c`/`func_0x3ba9c` (DOS AH=`0x40`, count × FILE+4) in this exact order:

| Offset in `.sav` | Size | Source | Description |
|---:|---:|---|---|
| `0x0000` | `0x18d8` (6360) | heap far pointer returned by `FUN_3a97_0329(0x18d8)` | sampled VRAM thumbnail buffer |
| `0x18d8` | `0x404` (1028) | `SS:bp-0x438` (decomp name `local_43a`) | opaque graphics/state block from driver subfunction `0x40` |

Total file size = `0x18d8 + 0x404 = 0x1cdc` (7388 bytes).

Evidence:

- final save: `0x22b1f.c:427-435` writes `0x18d8` then `0x404` to the slot `.sav`; raw `/tmp/opencode/save_func_dis_full.txt:1222,1235` (calls at `0x23735`, `0x23753`).
- preview save/load: same two blocks, `0x22b1f.c:239-242` and `290-293`/`321-324`; raw lines `650,663`, `810,823`, `916,929`.
- final **load** reads **only the first `0x18d8` bytes**: `0x22b1f.c:449-456` (raw line 1313, `0x23816`; call to `.dat` reader at line 1340, `0x2385d`). The `0x404` block is **not** read from `.sav` in the final-load path; restoration happens via the `.dat` reader's global writes (no explicit driver `0x3e` call was observed in that reader). (Earlier assumption that final load also read `0x404` was wrong.)
- preview load reads both blocks (`0x22b1f.c:239-242`).

Initial scratch production (`0x22b1f.c:80-122`, raw lines 8–123):

1. `FUN_3443_23dc()` — page/video mode switch.
2. allocate `0x18d8` buffer.
3. sample VRAM: outer counter 32-bit at `bp-0x440/-0x43e`, values `3,6,…≤0xc9` (compare `0xc7`, raw lines 32–39); inner counter at `bp-0x43c/-0x43a`, values `3,6,…≤0x141` (compare `0x13f`, raw lines 43–49). For each pair, read one byte at `A000:(outer*0x140 + inner)` (`FUN_3a97_0279` = 32-bit × 0x10 segment-to-linear multiply, raw `0x3abe5..0x3abff`) and append it to the allocation at index `bp-0xe` (raw lines 50–78).
4. `FUN_3443_0335(state, SS)` → driver subfunction `0x40` fills the `0x404` block (raw `0x34765..0x34778`, `0x379ff..0x37a15`).
5. write `SAPIC.TMP` = `0x18d8` + `0x404`; copy `A000:0000` 0x8980 bytes into far pointer `[0x2c92]`; write `SAVE.TMP` = `0x8980` + `0x404` (`0x22b1f.c:102-122`).
6. read `HG00.SEQ` 0x8980 bytes into `[0x2c92]`, copy to `A000:0000`, then read `SAVEBOX.SEQ`: 2 WORDs (width, height) and `w*h` name bytes into `[0x1cee]` (`0x22b1f.c:123-194`).

---

## 3. `.dat` — exact logical layout

The `.dat` file is **not binary**: it is a fixed-width, line-oriented **decimal text** file written by `0x2d100` and parsed back by `0x31076`. Every numeric line is `AL` = decimal value padded left with spaces to width `0x18` (24) followed by `0x0d 0x0a`. String lines are raw Pascal-string characters followed by `0x0d 0x0a`. There is no header, magic, version, count, or checksum.

Writer mechanics (raw `/tmp/opencode/dat_writer_complete_intel.txt`):

- `0x2d100` allocates a 0x108-byte FILE record via `0x2a97:0x244`, init via `0x2a97:0x644` with name length `0xff`, then a disk-space probe `call 0x29db:0` (line 24). If `DX != 0`, or `DX==0 && AX < 0xc350` (50,000), return AL=`2` (line 30).
- open via `0x2a97:0xb19`/`0xb8e`; if status word `DS:0xb24` is nonzero after `0x207`, return AL=`1` (line 46).
- each numeric field: `mov ax/al,SOURCE; cwd/xor dx,dx; mov di,0x18; call 0x2a97:0x21c` (range validation against a bounds table at `DS:di`); `push dx; push ax; push 0; call 0x2a97:0xfc3` (decimal conversion + pad to 24 + write); `call 0x2a97:0xe65` (CRLF); `call 0x2a97:0x20e` (error check). `FUN_0fc3` raw `0x3b933..0x3b979`; decimal conversion `0x3b2fb..0x3b34c`.
- each string field: `call 0x2a97:0xf2d` with width 0 → chars only, then CRLF (`0x3b89d..0x3b8d8`).
- success: AL=`0` (line 6060), `retf 4` (line 6064).

### 3.1 Field groups in exact file order

`N_A` = WORD `DS:0xa19e`, `N_B` = WORD `DS:0xa19c`. **These counts are runtime globals, not stored in the file**; the reader reuses the values already in memory (raw `0x310c3`, `0x31183`; lines 38, 98).

1. **Group A — `N_A` records.** For `i = 1..N_A` (raw lines 48–116):
   - for `j = 1..7`: WORD at `DS:(0xad50 + 0x0e*i + 0x10*j)` → 24-column decimal line (first write at line 88; `WORD PTR [di-0x52b0]`, `di = 0x10*j + 0x0e*i`; `-0x52b0 ≡ 0xad50` mod 0x10000).
   - BYTE at `DS:(0xcd08 + i)` → line (`BYTE PTR [di-0x32f8]`, raw line 101; `-0x32f8 ≡ 0xcd08`).
   - **8 lines per record.**
2. **Group B — `N_B` records.** For `i = 1..N_B` (raw lines 117–273):
   - WORD `DS:(0x37fc + 2*i)` (line 138)
   - WORD `DS:(0x449e + 2*i)` (line 158)
   - BYTE `DS:(0x5140 + i)` (line 177)
   - BYTE `DS:(0x5de4 + i)` (line 197)
   - WORD `DS:(0x6436 + 2*i)` (line 218)
   - WORD `DS:(0x70d8 + 2*i)` (line 238)
   - BYTE `DS:(0x5792 + i)` (line 257)
   - Pascal string pointed to by far pointer at `DS:(0x8052 + 4*i)` (`les di,[di-0x7fae]`, `di=4*i`; `-0x7fae ≡ 0x8052`, raw lines 284–301) → one string line.
   - **8 lines per record.**
3. Two fixed Pascal strings: `DS:0x36de` (raw line 308, call line 313) and `DS:0xc91a` (line 319, call line 324).
4. Scalar numeric fields, in exactly this order (extracted from the call sites; address = runtime `DS` global, width in bytes):

| Address(es) | Width | Count | first write call |
|---|---:|---:|---|
| `0xbe1b` | 1 | 1 | `0x2d49a` |
| `0xcae2` | 2 | 1 | `0x2d4bf` |
| `0xcae4` | 2 | 1 | `0x2d4e4` |
| `0xcbeb` | 1 | 1 | `0x2d50c` |
| `0xc9bc` | 2 | 1 | `0x2d531` |
| `0xc9aa`–`0xc9ac` | 2 | 2 | `0x2d556` |
| `0xf2a8` | 2 | 1 | `0x2d5a0` |
| `0xc918` | 1 | 1 | `0x2d5c8` |
| `0xf2e3`–`0xf2f3` | 1 | 17 | `0x2d5f0` |
| `0xf2f8`–`0xf30e` | 1 | 23 | `0x2d898` |
| `0xf310` | 2 | 1 | `0x2dc2d` |
| `0xf312`–`0xf331` | 1 | 32 | `0x2dc55` |
| `0xf332`–`0xf338` | 2 | 4 | `0x2e152` |
| `0xf33a`–`0xf350` | 1 | 23 | `0x2e1e9` |
| `0xf352` | 2 | 1 | `0x2e57e` |
| `0xf354`–`0xf391` | 1 | 62 | `0x2e5a6` |
| `0xf396`–`0xf3b5` | 1 | 32 | `0x30cd8` |
| `0xf3b6` | 2 | 1 | `0x3073b` |
| `0xf3b8`–`0xf42e` | 1 | 119 | `0x30763` |
| `0xf430`–`0xf440` | 1 | 17 | `0x300ae` |
| `0xf442`–`0xf450` | 1 | 15 | `0x307b3` |
| `0xf452` | 2 | 1 | `0x30a08` |
| `0xf454`–`0xf464` | 1 | 17 | `0x30a30` |

(379 scalar lines total; `0xf311`, `0xf339`, `0xf351`, `0xf353`, `0xf392`–`0xf395`, `0xf3b7`, `0xf42f`, `0xf441`, `0xf453` are *not* written.)

5. Three fixed Pascal strings: far pointers at `DS:0x81d2`, `DS:0x831a`, `DS:0x865a` (raw lines `0x30ecc`, `0x30ee9`, `0x30f06`; calls at `0x30ed5`, `0x30ef2`, `0x30f0f`).
6. 50 string lines from far pointers at `DS:(0xdaaa + 0x65*k)` for `k = 0..0x31` (raw `0x30f26..0x30f60`; lines 5959–5978: `mul 0x65`, `add di,0xdaaa`, loop until `k==0x31`).
7. Five final scalar bytes: `DS:0xf2f5`, `0xf2c9`, `0xf2ca`, `0xf2cb`, `0xf2cc` (calls `0x30f7b`, `0x30fa3`, `0x30fcb`, `0x30ff3`, `0x3101b`), then close via `0x2a97:0xbe2` and AL=`0`.

Reader symmetry (raw `/tmp/opencode/dat_reader_full_intel.txt`):

- same Group A (`0x310c3..0x31183`, stores `WORD [di-0x52b0]` line 74 and `BYTE [di-0x32f8]`) and Group B (`0x31183..0x31315`, store `WORD [di+0x37fc]` line 123 etc.);
- reads numbers with `0x2a97:0xf6b` (token scanner) and stores to the very same globals (e.g. `mov ds:0xbe1b,al`, line 346);
- string lines are consumed with `0x2a97:0xe3c` (read line);
- returns AL=`0` on success (line 3927), AL=`1` only on open/status failure (line 36). There is no '2' from the reader.

**Observed implication:** `.dat` size depends on runtime `N_A`, `N_B` and on string lengths; each numeric line is at most 24 chars + CRLF (26 bytes), each string line is `len + 2`. There is no self-describing length; a `.dat` from a different game state will desynchronise the reader.

---

## 4. `HG<slot>.SEQ` — exact binary layout

Written on every exit from the save/load screen (`0x22b1f.c:465-560`, raw lines 1416–1536):

| Offset | Size | Source |
|---:|---:|---|
| `0x0000` | `0x8980` (35200) | far pointer `[0x2c92]` (screen buffer), copied to `A000:0000` |
| `0x8980` | `0x404` (1028) | `DS:0x2c9e` state block |

Total `0x8da4` = **36,228 bytes**, matching shipped `HG00.SEQ`…`HG12.SEQ` (36,228 bytes each). Byte inspection confirms the palette-looking block begins exactly at file offset `0x8980` (`xxd -s 0x8980 HG00.SEQ`).

Before restoring, the first two words of the buffer are forced to `0xb0` and `0xef` (`0x22b1f.c:527-529`, raw `0x239e0..0x23a09`), then `FUN_3443_034b` (driver subfunction `0x3e`) writes it back. This patch is only for the HG restore path; `.sav` uses the unmodified buffer.

---

## 5. The `0x404` state block (observed vs inferred)

**Observed:**

- filled at start with `FUN_3443_0335(buf, SS)` → raw `0x34765..0x34778` pushes `DS:0xf46e` and far ptr `ES:DI = SS:buf`, calls `0x379ff`; `0x379ff..0x37a15` sets `ES:BX = buf`, `AX = 0xf46e` value, `DI = DS:0xf504`, `SI = 0x40`, then `call DWORD PTR DS:0xf49a`.
- restored with `FUN_3443_034b` (same but `SI = 0x3e`) at `0x37a18..0x37a2e`.
- vector `DS:0xf49a` is installed from a driver table (raw `0x352ae`, `0x353a9`, and default stub `0x35b13`); it is code loaded/chosen at runtime, so static analysis cannot name the routine.
- `DS:0xf46e` is set by `FUN_3443_0370` (`0x347a0.c:36-37`); `DS:0xf504` is 0x40 or 0x100 depending on mode (`FUN_3443_0143`, `0x34573.c:19-27`).
- the block is copied verbatim into `.sav`, `SAVE.TMP`, `SAPIC.TMP` and `HGxx.SEQ`; nothing in the save code interprets its bytes except the two patched words in the HG path.

**Inferred:** it is a driver/EGA-VGA graphics-state snapshot (palette + mode registers), consistent with the palette-looking bytes in `HG00.SEQ:0x8980` and the `0xb0/0xef` port-like constants.

**Unresolved:** exact byte-to-register mapping of the `0x404` bytes; requires the runtime driver loaded via `DS:0xf49a` (not in `HEXPRG.EXE`, possibly in `HEXUMA.OVR`/external driver).

---

## 6. Load/save control flow from `0x22b1f` (`FUN_1c89_628f`)

Caller: `0x25206.c:369-372` — flag byte `DS:0x20fe` triggers the call; the pushed `0x3443` is ignored by the callee (`retf`, no immediate).

Mode flags (corrected): `cStack_11` (`bp-0x4d2`) = **SAVE**, `cStack_12` (`bp-0x4d0`) = **LOAD** (`0x22b1f.c:363-368`; raw `0x23505`/`0x2351c`). Error flag is byte `[bp-0x4ce]` (Ghidra calls it `local_4d0`; misleading name), initialised at raw line 11.

### 6.1 Setup (always)
`0x22b1f.c:78-200`, raw lines 8–200: scratch files, screenshots, save-box, initial slot from `DS:0x37f6`, pending keyboard input flushed.

### 6.2 UI loop (`0x22b1f.c:201-411`, raw `0x22e60..0x2365e`)
- draws slot number (`FUN_3a97_0a9d(10,…)`) and prefixes `0` if `<10` (lines 209–217).
- keys: `s`→SAVE, `l`→LOAD (only if opposite flag clear, lines 363–368); `H/-/I` decrement, `P/+/Q` increment slot (lines 369–374); `a`/`ESC` abort (line 375); `CR`/`o` confirm (line 376). Mouse regions: load `(0x30,0xe5)-(0x23,0xba)` line 386, save `(0x3f,0xe5)-(0x32,0xba)` line 390, prev/next lines 394/398, cancel line 402, confirm line 410. Slot clamped `0..99` (lines 378–383, 404–409).
- `FUN_3443_2a5f` is the "point inside rectangle" test; `FUN_3443_296e` swaps video pages.

### 6.2a Preview LOAD (`cStack_12`, `0x22b1f.c:218-267`; raw `0x2314e..0x234a5`)
- show `LADEN` / `SPEICHERN ` labels, open `<slot>.sav` with `FUN_3a97_103a` (existing), `FUN_3a97_0207` status check.
- if OK: read `0x18d8` + `0x404`, `FUN_3443_034b` restores graphics state, then the 58-step VRAM loop (§7); close.
- if open failed: show `Nichts gespeichert!`, load `SAPIC.TMP` (both blocks), restore state, run the same 58-step loop.
- **No `.dat` is read in preview.**

### 6.2b Preview SAVE (`cStack_11`, `0x22b1f.c:269-345`; raw `0x2321f..0x233bd`)
- show `SPEICHERN` / `LADEN ` labels; open `<slot>.sav` with `0x103a`.
- if it **exists**: read both blocks, restore state, 58-step loop, show `Existiert bereits!`, close.
- if it does **not** exist: open `SAPIC.TMP`, read both blocks, write them to `<slot>.sav`, restore state, 58-step loop.
- **No `.dat` is written in preview.**

### 6.3 Confirm SAVE (`cStack_11`, `0x22b1f.c:412-442`; raw `0x2365e..0x2379f`)
1. read `SAPIC.TMP` (`0x18d8`+`0x404`).
2. open `<slot>.sav` for writing (`0x1043`), write `0x18d8` then `0x404`, close.
3. build `<slot>.dat`, call `.dat` writer `func_0x0002d100(14999, name)` (line 441; raw `0x2379f`), and copy returned AL into error byte `[bp-0x4ce]`.

### 6.4 Confirm LOAD (`cStack_12`, `0x22b1f.c:443-463`; raw `0x237ac..0x23862`)
1. open `<slot>.sav` existing, check status.
2. if OK: read **only `0x18d8`** into the thumbnail buffer, close.
3. build `<slot>.dat`, call reader `func_0x00031076(14999, name)` (line 462), copy returned AL into `[bp-0x4ce]`.
4. If `.sav` open failed, set `[bp-0x4ce] = 1` (raw `0x237fc`).

### 6.5 Error reporting (`0x22b1f.c:468-501`; raw `0x2387a..0x23907`)
- error flag != 0 and LOAD → `Fehler beim Laden!`.
- error flag == 1 and SAVE → `Fehler beim Speichern!`.
- error flag == 2 and SAVE → `Platte voll??!`.
- otherwise no error box.

### 6.6 Exit path (`0x22b1f.c:465-560`; raw `0x23907..0x23b23`)
- free the `0x18d8` allocation (`0x2a97:0x341`).
- build `HG<slot>.seq` from `DS:0xc918` + zero prefix; patch state words `0x2c9e=0xb0`, `0x2ca0=0xef`; `FUN_3443_034b` restore; write `0x8980` + `0x404`; copy screenshot back to `A000`; store selected slot into `DS:0x37f6`; show 10 text rows from `(slot+0x28)*0x65-0x2556`; append `>` + `DS:0xc9c2` + spaces via `FUN_2bab_145d`.

---

## 7. The 58-step VRAM snapshot/restore loop

Runs after every preview save/load (three copies: `0x22b1f.c:244-259`, `295-310`, `328-343`); raw implementation at `0x231a0..0x23204` (`/tmp/opencode/save_func_dis_full.txt:673-711`).

Decoded raw semantics:

```
i = 0                                  # 32-bit at bp-0x440/-0x43e
do:
    src_linear = i*0x140 + 0x2c0d      # A000:(i*0x140+0x2c0d)
    dst_far    = buf_seg:(buf_off + i*0x6b)
    FUN_3a97_1249(0x6b, A000:src_off, dst_far)   # copy 107 bytes
    i += 1
until i == 0x39
```

- loop count: **58 iterations**, `i = 0..0x39` inclusive (`cmpw $0x39, -0x440(%bp)`, raw line 710).
- each iteration copies **0x6b (107) bytes** (`mov $0x6b,%ax`, raw line 705) from VRAM row `i*0x140 + 0x2c0d` into consecutive bytes of the sampled buffer at offset `i*0x6b` (raw lines 675–691).
- source segment forced to `A000` (`mov $0xa000,%ax; push %ax; pop %es`, raw lines 692–703); destination segment is the heap segment saved at `bp-0x32`, offset from `bp-0x34` (raw lines 675, 682–689).
- total bytes moved: `58*0x6b = 6206` (0x183e), leaving `0x18d8-0x183e = 0x9a` (154) bytes of the 0x18d8 buffer untouched **by this loop** (they are filled by the initial sampling pass of §2).
- `FUN_3a97_1249` (`0x3bbb9.c:13-32`) is a `memmove`-style copy; the decompiler's parameter names are reversed relative to the raw push order observed here.
- direction is **bidirectional in code**: the same loop is used after both "load state" (VRAM ← buffer) and "save state" (buffer ← VRAM) in the preview paths; the raw call order at `0x231cf` and `0x231ec` shows `FUN_1249(count, source_far, dest_far)`. Because the buffer is the sampled thumbnail, the operation is effectively a restore of the 58 VRAM rows in every observed invocation.

Geometry interpretation (`0x140` = 320-byte VRAM row stride, `0x6b` = 107 bytes per thumbnail row, start `0x2c0d`) is **inferred**; the constants themselves are observed.

---

## 8. RAM ranges and runtime-global mapping

| Range/global | Role | Evidence |
|---|---|---|
| `A000:0000..A000:0x897f` (0x8980) | full screen buffer, far pointer at `DS:0x2c92` | `0x22b1f.c:111-112,128-135,520-521`; raw lines 204–215, 1535 |
| `A000:(i*0x140+0x2c0d)`, `i=0..0x39`, 0x6b B each | 58-row VRAM window touched by preview loop | raw lines 675–711 |
| VRAM sample addresses `A000:(3..0xc9)*0x140 + (3..0x141)` | initial thumbnail sampling | raw lines 32–78 |
| `DS:0x2c9e` | 0x404 state block in HG-restore path; words at `0x2c9e/0x2ca0` patched to `0xb0/0xef` | `0x22b1f.c:523-529` |
| `SS:bp-0x438 .. bp-0x35` (0x404) | main state buffer (`local_43a`) | raw line 80; `0x22b1f.c:67` |
| heap far ptr from `FUN_3a97_0329(0x18d8)` | thumbnail buffer (segment `bp-0x32`, offset `bp-0x34`) | raw lines 8–23 |
| `DS:0x1cee` | save-box name-byte matrix (`W*H` from `SAVEBOX.SEQ`) | `0x22b1f.c:145-194` |
| `DS:0x20fe` | save/load screen trigger flag (caller) | `0x25206.c:369-372` |
| `DS:0x37f6` | currently selected slot, persisted | `0x22b1f.c:198,535` |
| `DS:0xc918` | current HG image number | `0x22b1f.c:502-503` |
| `DS:0xc9c2` | flag/text used in final prompt | `0x22b1f.c:557` |
| `DS:0xa19e`, `DS:0xa19c` | `.dat` group counts `N_A`, `N_B` | writer line 48/117; reader lines 38/98 |
| `DS:0xf46e`, `DS:0xf504`, `DS:0xf49a` | graphics-driver selector, mode, call vector for the 0x404 block | `0x347a0.c:37`, `0x34573.c:19-27`, `0x35afa.c` |
| `DS:0xb24` | I/O status word (`0x207` returns-and-clears, `0x20e` error dispatch) | `0x3aa41.c`, `0x3b7d5.c` |
| FILE record at `DS:0xa096`, magic `0xd7b0` init / `0xd7b2` open, `+4 = 1` record size, `+8 =` file position | Pascal-style FILE used by all helpers | `0x3b489.c:20-40`, `0x3b748` raw |

---

## 9. Observed / inferred / unresolved

**Observed (byte- or instruction-level corroborated):**
- `.sav` = `0x18d8` thumbnail + `0x404` state; final load reads only `0x18d8`.
- `HGxx.SEQ` = `0x8980` screen + `0x404` state; file size 36,228.
- slot names `"00".."99"` + `.sav`/`.dat`/`hg`/`.seq`; zero prefix for <10.
- `.dat` is decimal text, width 24 + CRLF per numeric line, with exact field groups and globals listed in §3.
- 58-step loop bounds, strides, segments and byte count.
- all messages, key/mouse regions, flag semantics, error codes 1/2, absence of checksums.
- scratch initialization and SAVEBOX/HG00 handling.

**Inferred:**
- `0x140` and `0x6b` are VRAM row stride / thumbnail row width; `0x2c0d` is the thumbnail's VRAM origin.
- `0x404` block is a VGA/EGA palette/mode snapshot; `0xb0`/`0xef` are hardware port/index constants.
- the space probe `0x29db:0` returning ≥50,000 is a minimum-free-disk check.
- direction of the 58-step loop is always VRAM restore in observed calls (the copy helper itself is direction-agnostic).

**Unresolved:**
- exact byte semantics of the `0x404` state block (runtime driver behind `DS:0xf49a`, not statically available here).
- identity of the `0x29db:0` probe and the bounds tables at `DS:0x00/0x08/0x10/0x18/0x20` used by `FUN_3a97_021c`.
- semantic names of most `.dat` globals (`DS:0xf2xx`/`0xf3xx`/`0xf4xx`); only their order, width and addresses are established.
- `HEXUMA.OVR` was not analysed; no evidence indicates save-format code lives there.
- initial sampling loop writes `67*107 = 7169` bytes into a `0x18d8` (6360-byte) allocation per raw counters — possible overflow or an allocation-size subtlety in `FUN_3a97_0329`/`0x3ad8d`; not fully resolved, but it does not change the on-disk layout.
