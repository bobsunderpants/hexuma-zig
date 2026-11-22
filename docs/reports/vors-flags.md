# VORS.BIN runtime label / flag semantics — DOS Hexuma

Research date: 2026-11-22. Scope: reverse-engineering only; no project files were modified.

## 1. Bottom line

1. **VORS labels are runtime state, not static data.** `FUN_1c89_77fd` (`0x2408d`) loads one VORS record selected by the current picture id in `0x32d0`, clears its local slot buffers, copies the original labels from `VORS.BIN`, then overwrites selected slots using hardcoded Pascal strings gated by current room (`0xbe1b`), byte flags, and dynamic globals (`0x2408d.c:58-90`, `0x2408d.c:93-474`, `0x2408d.c:479-563`).
2. **The displayed label is the parser command.** The caller copies the returned Pascal string into `0xc9c2`, appends a literal `'\r'`, and the main loop parses it (`0x25206.c:612-618`, `0x25206.c:810-826`).
3. **Two global gates dominate the whole mechanism.** `0xf2fa == 1` suppresses all VORS labels immediately (`0x2408d.c:58-60`). `0xf481 == 0` means “draw hover labels for all slots”; `0xf481 == 1` means “return only the hovered slot’s label”; any other value aborts (`0x2408d.c:542-555`).
4. **“Startup zero” is not a valid state model.** The relevant bytes are mutable world state. Some are initialized at startup (`0xf2fb`, `0xf2fa`, `0xf3df` at `0x10b17.c:126-128`, `0x10b17.c:346`; `0x11be9.c:274`), but the same addresses are read dynamically by VORS (`0x2408d.c:94`, `0x2408d.c:113`, `0x2408d.c:222-238`) and by FR overlay selection (`0x2bffd.c:142-175`, `0x2bffd.c:199-215`, `0x2bffd.c:238-291`). Their exact mutators are not fully reconstructed in the analyzed load module (`docs/RE_FINDINGS.md:174-177`), so they must be modeled as persistent, saveable state rather than constants.

## 2. Runtime pipeline (observed)

### 2.1 Record selection

- The mouse-hover/click caller invokes `FUN_1c89_77fd(*(u16 *)0x32d0)` (`0x25206.c:612`).
- `0x32d0` is the picture id read from the BILD resource header, not the room id (`0x2bffd.c:79-80`; `docs/RE_FINDINGS.md:110-112`).
- `0x2408d` builds the filename `vors.bin` from CS string `0x7583` (`0x2408d.c:76-77`).
- The seek offset is `param_1 * 0x377`: the multiply helper returns `AX * CX` (`0x3abe9.c:13-19`) and `0x2408d.c:82-85` seeks and reads `0x377` bytes. This matches `VORS.BIN` being `151677 = 171 * 0x377` bytes and record `n` starting at `n * 0x377` (`docs/RE_FINDINGS.md:113-114`). Record 0 is an unused/corrupt sentinel; record 1 contains `Untersuche den Kamin`.

### 2.2 Slot layout and clearing

- The function clears 15 label buffers (51 bytes each, stride `0x33`) and 15 coordinate groups before loading the record (`0x2408d.c:62-75`; declarations at `0x2408d.c:44-54`).
- It reads `0x377` bytes into that buffer (`0x2408d.c:85`). The first `u16` is the slot count; `count == 0` aborts (`0x2408d.c:89-91`).
- An observed but inert-for-shipped-data clamp sets `count = 1` when `count > 14` (`0x2408d.c:476-478`; confirmed in REA disassembly at `0x24d85-0x24d8c`). All shipped records have `count <= 12`, so this does not affect the table below.
- The iteration bound is `count - 1` (`0x2408d.c:479`, `0x2408d.c:561-562`). Therefore overrides targeting slots `>= count` are never displayed. Several source assignments are inert for that reason; they are called out in the notes.

### 2.3 Override application

- All hardcoded labels are Pascal strings in CS segment `0x1c89`. The file-offset mapping is `segment * 16 + address - 0x9a00` (`docs/RE_FINDINGS.md:98-99`), i.e. `0x12e90 + address` here.
- The override branch chain is `0x2408d.c:93-474`. It uses:
  - current room `R = *(u8 *)0xbe1b` (initialized to `1` at `0x10b17.c:34`, changed by scene logic such as `0x184e4.c:449`);
  - byte flags `F[a] = *(byte *)a`;
  - dynamic 32-bit remembers `U32[a] = *(u32 *)a` (`0x4b3a`, `0x4b3e`, `0x4b5c` are written from the current room under conditions at `0x1b38e.c:168-179`; `0x4b9a` and `0x4a62` have no direct write found in the decompiled load module);
  - `I32[a] = *(int *)a` (`0xb894`, `0x6bc4`).

Hardcoded strings used by the overrides:

| CS address | Decoded string |
|---:|---|
| `0x758c` | `Schließe die Haustüre` |
| `0x75a2` | ` ` (single space, length 1) |
| `0x75a4` | `Untersuche den Lüster` |
| `0x75ba` | `Gehe in die Bibliothek` |
| `0x75d1` | `Gehe Süd` |
| `0x75da` | `Schließe die Tür` |
| `0x75eb` | `Öffne die Tür` |
| `0x75f9` | `Gehe runter` |
| `0x7605` | `Öffne die Tür zur Küche` |
| `0x761d` | `Gehe in die Küche` |
| `0x762f` | `Gehe Nord` |
| `0x7639` | `Gehe ins Kinderzimmer` |
| `0x764f` | `Gehe ins Schlafzimmer` |
| `0x7665` | `Gehe West` |
| `0x766f` | `Gehe nach Süden` |
| `0x767f` | `Gehe Ost` |
| `0x7688` | `Untersuche das Dickicht` |
| `0x76a0` | `Betrachte die Kokospalme` |
| `0x76b9` | `Untersuche den Felskegel` |
| `0x76d2` | `Betrachte den Urwald` |
| `0x76e7` | `Untersuche die Bucht` |
| `0x76fc` | `Untersuche die Gestalt` |
| `0x7713` | `Betrachte die Sandhügel` |
| `0x772b` | `Untersuche die Seekiste` |
| `0x7743` | `Gehe in die Hütte` |
| `0x7755` | `Untersuche die Fußstapfen` |
| `0x776f` | `Untersuche die Blätter` |
| `0x7786` | `Untersuche den Findling` |
| `0x779e` | `Betrachte die Sandbank` |
| `0x77b5` | `Gehe nach Westen` |
| `0x77c6` | `Gehe nach Osten` |
| `0x77d6` | `Untersuche das Holzstück` |
| `0x77ef` | `Tauche runter` |

**Blank semantics matter.** `auStack[...][0] = 0` produces a length-0 Pascal string (`∅`); the caller skips it because `acStack_317[1] == 0` (`0x25206.c:614`). String `0x75a2` is a length-1 Pascal string containing one literal space (`' '`), which is **not** empty and is therefore submitted as a one-space command. The original VORS data itself also contains length-0 blanks (for example record 1 slots 10-14).

### 2.4 Hover, click, and command submission

- Slot rectangles are offset by scroll position `0x30a2` / `0x30a4` and hit-tested with `FUN_3443_2a5f` (`0x2408d.c:482-486`).
- When `0xf481 == 0`, the function draws hover labels for matching slots and continues iterating (`0x2408d.c:502-540`, `0x2408d.c:542-555`).
- When `0xf481 == 1`, it copies the hovered slot’s label into the output parameter and returns (`0x2408d.c:547-554`). Other values set the output empty and return (`0x2408d.c:542-546`).
- The caller copies that output into `0xc9c2`, sets `local_3 = '\r'`, and jumps to the common parser path (`0x25206.c:613-618`). At `LAB_1c89_a116`, the `\r` is appended and the command buffer is parsed/submitted (`0x25206.c:810-826`).

## 3. Notation for the table

- `R` — current room, byte at `0xbe1b`.
- `F[0xNNNN]` — mutable byte flag at that address.
- `U32[0xNNNN]` / `I32[0xNNNN]` — mutable 32-bit global at that address.
- `' '` shown literally as a single space inside backticks: a length-1 command.
- `∅` — length-0 string; no command is submitted.
- Rows are evaluated in the listed order; later assignments overwrite earlier ones. If no row changes a slot, the original VORS label is displayed.
- Only slots `< count` are effective. Notes on the rows identify suppressed inert assignments.

## 4. Complete record / slot / condition / label / command table

| Record | Slot(s) | Condition (evaluated in order) | Original VORS label(s) | Displayed label(s) | Action command | Source |
|---:|:---:|---|---|---|---|---|
| 1 (`0x01`) | 4 | `F[0x5e31] == 0` | 4: `Öffne die Haustür` | 4: `Schließe die Haustüre` | 4: `Schließe die Haustüre` | 0x2408d.c:93-110 |
| 1 (`0x01`) | 6, 7 | `F[0xf2fb] == 1` | 6: `Untersuche den Lüster`; 7: ` ` | 6: ` `; 7: `Untersuche den Lüster` | 6: ` `; 7: `Untersuche den Lüster` | 0x2408d.c:93-110 |
| 1 (`0x01`) | 9 | `F[0x5fa7] == 0` | 9: `Öffne die Tür zur Bibliothek` | 9: `Gehe in die Bibliothek` | 9: `Gehe in die Bibliothek` | 0x2408d.c:93-110 |
| 1 (`0x01`) | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 | `R == 5` — effective only slots 0..9 (count=10) | 0: `Untersuche den Kamin`; 1: `Schau in den Spiegel`; 2: `Gehe rauf`; 3: `Untersuche das Gemälde`; 4: `Öffne die Haustür`; 5: `Süd`; 6: `Untersuche den Lüster`; 7: ` `; 8: `Untersuche das Schildchen`; 9: `Öffne die Tür zur Bibliothek` | 0: `Gehe Süd`; 1: `Gehe Süd`; 2: `Gehe Süd`; 3: `Gehe Süd`; 4: `Gehe Süd`; 5: `Gehe Süd`; 6: `Gehe Süd`; 7: `Gehe Süd`; 8: `Gehe Süd`; 9: `Gehe Süd` | 0: `Gehe Süd`; 1: `Gehe Süd`; 2: `Gehe Süd`; 3: `Gehe Süd`; 4: `Gehe Süd`; 5: `Gehe Süd`; 6: `Gehe Süd`; 7: `Gehe Süd`; 8: `Gehe Süd`; 9: `Gehe Süd` | 0x2408d.c:93-110 |
| 5 (`0x05`) | 0 | `F[0x5fab] == 0` | 0: `Schließe die Tür` | 0: `Schließe die Tür` | 0: `Schließe die Tür` | 0x2408d.c:112-119 |
| 5 (`0x05`) | 0 | `F[0x5fab] == 1` | 0: `Schließe die Tür` | 0: `Öffne die Tür` | 0: `Öffne die Tür` | 0x2408d.c:112-119 |
| 9 (`0x09`) | 0, 2, 3 | `R == 6` | 0: `Gehe runter`; 2: `Öffne die Tür zum Kinderzimmer`; 3: `Öffne die Tür zum Schlafzimmer` | 0: `Gehe runter`; 2: ` `; 3: ` ` | 0: `Gehe runter`; 2: ` `; 3: ` ` | 0x2408d.c:120-150 |
| 9 (`0x09`) | 1 | `R == 6 && F[0x5fb0] == 1` | 1: `Öffne die Tür zur Küche` | 1: `Öffne die Tür zur Küche` | 1: `Öffne die Tür zur Küche` | 0x2408d.c:120-150 |
| 9 (`0x09`) | 1 | `R == 6 && F[0x5fb0] != 1` | 1: `Öffne die Tür zur Küche` | 1: `Gehe in die Küche` | 1: `Gehe in die Küche` | 0x2408d.c:120-150 |
| 9 (`0x09`) | 0, 1, 4 | `R == 9` | 0: `Gehe runter`; 1: `Öffne die Tür zur Küche`; 4: `Gehe Süd` | 0: `Gehe Nord`; 1: ` `; 4: `Gehe Nord` | 0: `Gehe Nord`; 1: ` `; 4: `Gehe Nord` | 0x2408d.c:120-150 |
| 9 (`0x09`) | 2 | `R == 9 && F[0x5fb3] == 0` | 2: `Öffne die Tür zum Kinderzimmer` | 2: `Gehe ins Kinderzimmer` | 2: `Gehe ins Kinderzimmer` | 0x2408d.c:120-150 |
| 9 (`0x09`) | 3 | `R == 9 && F[0x5fb6] == 0` | 3: `Öffne die Tür zum Schlafzimmer` | 3: `Gehe ins Schlafzimmer` | 3: `Gehe ins Schlafzimmer` | 0x2408d.c:120-150 |
| 9 (`0x09`) | 0, 1, 3 | `R == 11` | 0: `Gehe runter`; 1: `Öffne die Tür zur Küche`; 3: `Öffne die Tür zum Schlafzimmer` | 0: `∅`; 1: `∅`; 3: `∅` | 0: ∅ (no command); 1: ∅ (no command); 3: ∅ (no command) | 0x2408d.c:120-150 |
| 9 (`0x09`) | 2, 4 | `R == 11` | 2: `Öffne die Tür zum Kinderzimmer`; 4: `Gehe Süd` | 2: `Gehe West`; 4: `Gehe West` | 2: `Gehe West`; 4: `Gehe West` | 0x2408d.c:120-150 |
| 10 (`0x0a`) | 0 | `R == 7 && F[0x5fb6] == 1` | 0: `Schließe die Tür` | 0: `Öffne die Tür` | 0: `Öffne die Tür` | 0x2408d.c:151-167 |
| 10 (`0x0a`) | 2 | `R == 7 && F[0x525e] != 3` | 2: `Untersuche das Plüschtuch` | 2: ` ` | 2: ` ` | 0x2408d.c:151-167 |
| 10 (`0x0a`) | 0, 1, 2, 3, 4 | `R == 8` | 0: `Schließe die Tür`; 1: `Gehe Ost`; 2: `Untersuche das Plüschtuch`; 3: `Untersuche das Bett`; 4: `Gehe ins Bad` | 0: ` `; 1: ` `; 2: ` `; 3: `Gehe nach Süden`; 4: `Gehe nach Süden` | 0: ` `; 1: ` `; 2: ` `; 3: `Gehe nach Süden`; 4: `Gehe nach Süden` | 0x2408d.c:151-167 |
| 11 (`0x0b`) | 0, 1, 2 | `R == 11` — effective slots 0..2 (count=3) | 0: `Untersuche den Tisch`; 1: `Gehe West`; 2: `Gehe ins Kinderzimmer` | 0: `∅`; 1: `∅`; 2: `∅` | 0: ∅ (no command); 1: ∅ (no command); 2: ∅ (no command) | 0x2408d.c:168-175 |
| 12 (`0x0c`) | 0, 1, 2, 3, 4, 5 | `R == 13` — effective slots 0..5 (count=6) | 0: `Untersuche die Truhe`; 1: `Untersuche den Lattenkasten`; 2: `Schau Dir den Schrankkoffer an`; 3: `Betrachte das Dachgebälk`; 4: `Gehe runter`; 5: `Gehe West` | 0: `Gehe Ost`; 1: `Gehe Ost`; 2: `Gehe Ost`; 3: `Gehe Ost`; 4: `Gehe Ost`; 5: `Gehe Ost` | 0: `Gehe Ost`; 1: `Gehe Ost`; 2: `Gehe Ost`; 3: `Gehe Ost`; 4: `Gehe Ost`; 5: `Gehe Ost` | 0x2408d.c:176-184 |
| 13 (`0x0d`) | 0 | `R == 15` | 0: `Gehe rauf` | 0: `Gehe Ost` | 0: `Gehe Ost` | 0x2408d.c:185-189 |
| 14 (`0x0e`) | 0 | `F[0x52c9] != 3` | 0: `Nimm Hacke` | 0: ` ` | 0: ` ` | 0x2408d.c:190-194 |
| 27 (`0x1b`) | 0, 1, 2, 3, 4 | `always` (unconditional blank) | 0: `Untersuche das Dickicht`; 1: `Betrachte die Kokospalme`; 2: `Untersuche den Felskegel`; 3: `Betrachte den Urwald`; 4: `Untersuche die Bucht` | 0: ` `; 1: ` `; 2: ` `; 3: ` `; 4: ` ` | 0: ` `; 1: ` `; 2: ` `; 3: ` `; 4: ` ` | 0x2408d.c:196-215 |
| 27 (`0x1b`) | 0, 1, 2, 3, 4 | `R == 70` — same text as original; overwrites the blank | 0: `Untersuche das Dickicht`; 1: `Betrachte die Kokospalme`; 2: `Untersuche den Felskegel`; 3: `Betrachte den Urwald`; 4: `Untersuche die Bucht` | 0: `Untersuche das Dickicht`; 1: `Betrachte die Kokospalme`; 2: `Untersuche den Felskegel`; 3: `Betrachte den Urwald`; 4: `Untersuche die Bucht` | 0: `Untersuche das Dickicht`; 1: `Betrachte die Kokospalme`; 2: `Untersuche den Felskegel`; 3: `Betrachte den Urwald`; 4: `Untersuche die Bucht` | 0x2408d.c:196-215 |
| 27 (`0x1b`) | 2 | `R == 72` | 2: `Untersuche den Felskegel` | 2: `Untersuche den Felskegel` | 2: `Untersuche den Felskegel` | 0x2408d.c:196-215 |
| 27 (`0x1b`) | 2 | `R == 74` | 2: `Untersuche den Felskegel` | 2: `Untersuche den Felskegel` | 2: `Untersuche den Felskegel` | 0x2408d.c:196-215 |
| 28 (`0x1c`) | 0, 1, 2 | `always` (unconditional blank) | 0: `Untersuche die Gestalt`; 1: `Betrachte den Sandhügel`; 2: `Untersuche die Seekiste` | 0: ` `; 1: ` `; 2: ` ` | 0: ` `; 1: ` `; 2: ` ` | 0x2408d.c:216-231 |
| 28 (`0x1c`) | 0 | `F[0x6029] == 0` | 0: `Untersuche die Gestalt` | 0: `Untersuche die Gestalt` | 0: `Untersuche die Gestalt` | 0x2408d.c:216-231 |
| 28 (`0x1c`) | 1 | `F[0x6029] == 1` | 1: `Betrachte den Sandhügel` | 1: `Betrachte die Sandhügel` | 1: `Betrachte die Sandhügel` | 0x2408d.c:216-231 |
| 28 (`0x1c`) | 2 | `F[0xf3df] == 1` | 2: `Untersuche die Seekiste` | 2: `Untersuche die Seekiste` | 2: `Untersuche die Seekiste` | 0x2408d.c:216-231 |
| 29 (`0x1d`) | 1 | `F[0x604b] == 0` | 1: `Schließe die Tür` | 1: `Schließe die Tür` | 1: `Schließe die Tür` | 0x2408d.c:232-240 |
| 29 (`0x1d`) | 1 | `F[0x604b] == 1` | 1: `Schließe die Tür` | 1: `Öffne die Tür` | 1: `Öffne die Tür` | 0x2408d.c:232-240 |
| 29 (`0x1d`) | 2 | `always` | 2: `Öffne die Tür` | 2: `Gehe in die Hütte` | 2: `Gehe in die Hütte` | 0x2408d.c:232-240 |
| 35 (`0x23`) | 4 | `R == 88` | 4: `Klettere rauf` | 4: ` ` | 4: ` ` | 0x2408d.c:241-277 |
| 35 (`0x23`) | 1, 2, 3, 4, 5 | `R == 87` | 1: `Betrachte die Felswand`; 2: `Untersuche den Felsvorsprung`; 3: `Untersuche den Felskamin`; 4: `Klettere rauf`; 5: `Klettere runter` | 1: `∅`; 2: `∅`; 3: `∅`; 4: `∅`; 5: `∅` | 1: ∅ (no command); 2: ∅ (no command); 3: ∅ (no command); 4: ∅ (no command); 5: ∅ (no command) | 0x2408d.c:241-277 |
| 35 (`0x23`) | 0, 1, 5, 6, 7 | `R == 89` | 0: `Untersuche den Felspfad`; 1: `Betrachte die Felswand`; 5: `Klettere runter`; 6: `Geh nach Westen`; 7: `Geh nach Westen` | 0: `∅`; 1: `∅`; 5: `∅`; 6: `∅`; 7: `∅` | 0: ∅ (no command); 1: ∅ (no command); 5: ∅ (no command); 6: ∅ (no command); 7: ∅ (no command) | 0x2408d.c:241-277 |
| 35 (`0x23`) | 0, 1, 2, 3, 4, 5, 6, 7 | `R == 90` | 0: `Untersuche den Felspfad`; 1: `Betrachte die Felswand`; 2: `Untersuche den Felsvorsprung`; 3: `Untersuche den Felskamin`; 4: `Klettere rauf`; 5: `Klettere runter`; 6: `Geh nach Westen`; 7: `Geh nach Westen` | 0: `∅`; 1: `∅`; 2: `∅`; 3: `∅`; 4: `∅`; 5: `∅`; 6: `∅`; 7: `∅` | 0: ∅ (no command); 1: ∅ (no command); 2: ∅ (no command); 3: ∅ (no command); 4: ∅ (no command); 5: ∅ (no command); 6: ∅ (no command); 7: ∅ (no command) | 0x2408d.c:241-277 |
| 35 (`0x23`) | 0, 1, 2, 3, 4, 5, 6, 7 | `R == 91` | 0: `Untersuche den Felspfad`; 1: `Betrachte die Felswand`; 2: `Untersuche den Felsvorsprung`; 3: `Untersuche den Felskamin`; 4: `Klettere rauf`; 5: `Klettere runter`; 6: `Geh nach Westen`; 7: `Geh nach Westen` | 0: `∅`; 1: `∅`; 2: `∅`; 3: `∅`; 4: `∅`; 5: `∅`; 6: `∅`; 7: `∅` | 0: ∅ (no command); 1: ∅ (no command); 2: ∅ (no command); 3: ∅ (no command); 4: ∅ (no command); 5: ∅ (no command); 6: ∅ (no command); 7: ∅ (no command) | 0x2408d.c:241-277 |
| 36 (`0x24`) | 1 | `R == 92` | 1: `Untersuche die Felsentür` | 1: `∅` | 1: ∅ (no command) | 0x2408d.c:278-285 |
| 36 (`0x24`) | 0 | `R == 93` | 0: `Untersuche die Konstruktion` | 0: `∅` | 0: ∅ (no command) | 0x2408d.c:278-285 |
| 38 (`0x26`) | 4, 5 | `R == 96` | 4: `Geh runter`; 5: `Nimm den Splitter` | 4: `∅`; 5: `∅` | 4: ∅ (no command); 5: ∅ (no command) | 0x2408d.c:286-295 |
| 38 (`0x26`) | 1, 2 | `R == 97` | 1: `Untersuche die Felsnadel`; 2: `Geh nach Süden` | 1: `∅`; 2: `∅` | 1: ∅ (no command); 2: ∅ (no command) | 0x2408d.c:286-295 |
| 40 (`0x28`) | 6, 8, 9, 10 | `R == 146` | 6: `Geh nach Süden`; 8: `Untersuche die Blätter`; 9: `Untersuche den Findling`; 10: `Betrachte die Sandbank` | 6: ` `; 8: ` `; 9: ` `; 10: ` ` | 6: ` `; 8: ` `; 9: ` `; 10: ` ` | 0x2408d.c:296-349 |
| 40 (`0x28`) | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 | `R == 147` | 0: `Untersuche den Fladen`; 1: `Betrachte den Felsen`; 2: `Untersuche die Gebilde`; 3: `Geh nach Norden`; 4: `Geh nach Westen`; 5: `Geh nach Osten`; 6: `Geh nach Süden`; 7: `Untersuche die Fußstapfen`; 8: `Untersuche die Blätter`; 9: `Untersuche den Findling`; 10: `Betrachte die Sandbank` | 0: ` `; 1: ` `; 2: ` `; 3: ` `; 4: ` `; 5: `Gehe nach Süden`; 6: `Untersuche die Fußstapfen`; 7: `Untersuche die Blätter`; 8: ` `; 9: ` `; 10: ` ` | 0: ` `; 1: ` `; 2: ` `; 3: ` `; 4: ` `; 5: `Gehe nach Süden`; 6: `Untersuche die Fußstapfen`; 7: `Untersuche die Blätter`; 8: ` `; 9: ` `; 10: ` ` | 0x2408d.c:296-349 |
| 40 (`0x28`) | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 | `R == 156` | 0: `Untersuche den Fladen`; 1: `Betrachte den Felsen`; 2: `Untersuche die Gebilde`; 3: `Geh nach Norden`; 4: `Geh nach Westen`; 5: `Geh nach Osten`; 6: `Geh nach Süden`; 7: `Untersuche die Fußstapfen`; 8: `Untersuche die Blätter`; 9: `Untersuche den Findling`; 10: `Betrachte die Sandbank` | 0: ` `; 1: ` `; 2: ` `; 3: ` `; 4: ` `; 5: ` `; 6: ` `; 7: ` `; 8: ` `; 9: `Untersuche den Findling`; 10: `Betrachte die Sandbank` | 0: ` `; 1: ` `; 2: ` `; 3: ` `; 4: ` `; 5: ` `; 6: ` `; 7: ` `; 8: ` `; 9: `Untersuche den Findling`; 10: `Betrachte die Sandbank` | 0x2408d.c:296-349 |
| 40 (`0x28`) | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 | `R == 149` | 0: `Untersuche den Fladen`; 1: `Betrachte den Felsen`; 2: `Untersuche die Gebilde`; 3: `Geh nach Norden`; 4: `Geh nach Westen`; 5: `Geh nach Osten`; 6: `Geh nach Süden`; 7: `Untersuche die Fußstapfen`; 8: `Untersuche die Blätter`; 9: `Untersuche den Findling`; 10: `Betrachte die Sandbank` | 0: ` `; 1: ` `; 2: ` `; 3: ` `; 4: ` `; 5: ` `; 6: ` `; 7: ` `; 8: ` `; 9: ` `; 10: ` ` | 0: ` `; 1: ` `; 2: ` `; 3: ` `; 4: ` `; 5: ` `; 6: ` `; 7: ` `; 8: ` `; 9: ` `; 10: ` ` | 0x2408d.c:296-349 |
| 40 (`0x28`) | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 | `R == 154` | 0: `Untersuche den Fladen`; 1: `Betrachte den Felsen`; 2: `Untersuche die Gebilde`; 3: `Geh nach Norden`; 4: `Geh nach Westen`; 5: `Geh nach Osten`; 6: `Geh nach Süden`; 7: `Untersuche die Fußstapfen`; 8: `Untersuche die Blätter`; 9: `Untersuche den Findling`; 10: `Betrachte die Sandbank` | 0: ` `; 1: ` `; 2: ` `; 3: ` `; 4: `Gehe nach Westen`; 5: `Gehe nach Osten`; 6: ` `; 7: ` `; 8: ` `; 9: ` `; 10: ` ` | 0: ` `; 1: ` `; 2: ` `; 3: ` `; 4: `Gehe nach Westen`; 5: `Gehe nach Osten`; 6: ` `; 7: ` `; 8: ` `; 9: ` `; 10: ` ` | 0x2408d.c:296-349 |
| 40 (`0x28`) | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 | `R == 155` | 0: `Untersuche den Fladen`; 1: `Betrachte den Felsen`; 2: `Untersuche die Gebilde`; 3: `Geh nach Norden`; 4: `Geh nach Westen`; 5: `Geh nach Osten`; 6: `Geh nach Süden`; 7: `Untersuche die Fußstapfen`; 8: `Untersuche die Blätter`; 9: `Untersuche den Findling`; 10: `Betrachte die Sandbank` | 0: ` `; 1: ` `; 2: ` `; 3: ` `; 4: `Gehe nach Westen`; 5: `Gehe nach Osten`; 6: ` `; 7: ` `; 8: ` `; 9: ` `; 10: ` ` | 0: ` `; 1: ` `; 2: ` `; 3: ` `; 4: `Gehe nach Westen`; 5: `Gehe nach Osten`; 6: ` `; 7: ` `; 8: ` `; 9: ` `; 10: ` ` | 0x2408d.c:296-349 |
| 43 (`0x2b`) | 1 | `R != U32[0x4b3a]` | 1: `Schau den Brontosaurus an` | 1: ` ` | 1: ` ` | 0x2408d.c:350-354 |
| 47 (`0x2f`) | 2 | `R != U32[0x4b5c]` | 2: `Betrachte den Triceratops` | 2: ` ` | 2: ` ` | 0x2408d.c:355-359 |
| 48 (`0x30`) | 1 | `R != U32[0x4b3e]` | 1: `Geh nach Norden` | 1: ` ` | 1: ` ` | 0x2408d.c:360-364 |
| 49 (`0x31`) | 1 | `R != U32[0x4b9a]` | 1: `Schau das Saurierbaby an` | 1: ` ` | 1: ` ` | 0x2408d.c:365-369 |
| 60 (`0x3c`) | 0, 1, 2, 3, 4 | `R == 127` | 0: `Geh nach Osten`; 1: `Geh nach Süden`; 2: `Geh nach Norden`; 3: `Betrachte das Schild`; 4: `Untersuche die Kreuzung` | 0: ` `; 1: ` `; 2: ` `; 3: ` `; 4: ` ` | 0: ` `; 1: ` `; 2: ` `; 3: ` `; 4: ` ` | 0x2408d.c:370-378 |
| 71 (`0x47`) | 1 | `R == 124` | 1: `Drücke auf die Taste` | 1: `∅` | 1: ∅ (no command) | 0x2408d.c:380-384 |
| 91 (`0x5b`) | 2 | `F[0xf3a2] == 1` | 2: `Nimm die Fahne` | 2: ` ` | 2: ` ` | 0x2408d.c:385-389 |
| 94 (`0x5e`) | 1, 2, 3, 4 | `R == 31` | 1: `Untersuche den Monolith`; 2: `Untersuche den Schacht`; 3: `Untersuche die Trümmerbrocken`; 4: `Untersuche die Trümmerbrocken` | 1: ` `; 2: ` `; 3: ` `; 4: ` ` | 1: ` `; 2: ` `; 3: ` `; 4: ` ` | 0x2408d.c:390-410 |
| 94 (`0x5e`) | 2, 3, 4 | `R == 32 && F[0xf3b1] != 3` | 2: `Untersuche den Schacht`; 3: `Untersuche die Trümmerbrocken`; 4: `Untersuche die Trümmerbrocken` | 2: ` `; 3: ` `; 4: ` ` | 2: ` `; 3: ` `; 4: ` ` | 0x2408d.c:390-410 |
| 94 (`0x5e`) | 1 | `R == 32 && F[0xf3b1] == 3` | 1: `Untersuche den Monolith` | 1: ` ` | 1: ` ` | 0x2408d.c:390-410 |
| 115 (`0x73`) | 0 | `R == 169` — effective slot 0 (count=1) | 0: `Betrachte den Mann` | 0: `∅` | 0: ∅ (no command) | 0x2408d.c:411-418 |
| 118 (`0x76`) | 0, 1, 2, 3, 4, 5 | `R == 179 \|\| R == 180` — effective slots 0..5 (count=6) | 0: `Untersuche die Brücke`; 1: `Geh nach Süden`; 2: `Geh nach Westen`; 3: `Geh nach Osten`; 4: `Untersuche die Bestie`; 5: `Geh Rauf` | 0: `∅`; 1: `∅`; 2: `∅`; 3: `∅`; 4: `∅`; 5: `∅` | 0: ∅ (no command); 1: ∅ (no command); 2: ∅ (no command); 3: ∅ (no command); 4: ∅ (no command); 5: ∅ (no command) | 0x2408d.c:419-432 |
| 118 (`0x76`) | 4 | `F[0xf431] == 3` | 4: `Untersuche die Bestie` | 4: `∅` | 4: ∅ (no command) | 0x2408d.c:419-432 |
| 118 (`0x76`) | 4 | `R != 175` | 4: `Untersuche die Bestie` | 4: `∅` | 4: ∅ (no command) | 0x2408d.c:419-432 |
| 123 (`0x7b`) | 4 | `F[0x5422] == 1 && R == 189 && R == U32[0x4a62]` | 4: ∅ | 4: `Untersuche das Holzstück` | 4: `Untersuche das Holzstück` | 0x2408d.c:433-442 |
| 123 (`0x7b`) | 4 | `F[0x5422] == 1 && R == 189 && R != U32[0x4a62]` | 4: ∅ | 4: `∅` | 4: ∅ (no command) | 0x2408d.c:433-442 |
| 124 (`0x7c`) | 1 | `F[0xf445] == 1` | 1: `Betrachte die Felsplatte` | 1: `Tauche runter` | 1: `Tauche runter` | 0x2408d.c:443-447 |
| 129 (`0x81`) | 1, 2, 3 | `R == 199 \|\| R == 200` | 1: `Betrachte die SCHWARZE STADT`; 2: `Schau durch das Fenster`; 3: `Untersuche die SCHWARZE STADT` | 1: `∅`; 2: `∅`; 3: `∅` | 1: ∅ (no command); 2: ∅ (no command); 3: ∅ (no command) | 0x2408d.c:448-455 |
| 130 (`0x82`) | 4 | `F[0xf456] == 30 \|\| F[0xf456] == 0` | 4: `Schau Kathaura an` | 4: `∅` | 4: ∅ (no command) | 0x2408d.c:456-460 |
| 132 (`0x84`) | 0 | `R == 205 && I32[0xb894] != 0` | 0: `Untersuche den Pavillion` | 0: `Gehe runter` | 0: `Gehe runter` | 0x2408d.c:461-465 |
| 134 (`0x86`) | 3 | `I32[0x6bc4] == 0` | 3: `Betrachte Khalin` | 3: `∅` | 3: ∅ (no command) | 0x2408d.c:466-473 |

### Records with no override branch

- Records `15`, `16`, `17` are explicitly excluded by `if ((param_1 != 0xf) && (param_1 != 0x10) && (param_1 != 0x11))` (`0x2408d.c:195`).
- Record `65` (`0x41`) reaches `else if (param_1 != 0x41)` and has no body (`0x2408d.c:379`).
- All other records not named in the table simply retain their original VORS labels.

### Inert assignments in the source (not shown as effective rows)

- Record 1 / `R == 5`: loops slots 0..14, but `count == 10` (`0x2408d.c:104-110`).
- Record 11 / `R == 11`: slots 3 and 4 are cleared but `count == 3` (`0x2408d.c:168-175`).
- Record 12 / `R == 13`: assignments to slots 6..14 are beyond `count == 6` (`0x2408d.c:176-184`).
- Record 115 / `R == 169`: slots 1..14 are cleared but `count == 1` (`0x2408d.c:411-418`).
- Record 118 / rooms 179-180: slots 6..14 are cleared but `count == 6` (`0x2408d.c:419-425`).
- Record 134 / `R == 234`: slot 4 is cleared but `count == 4` (`0x2408d.c:470-472`).

## 5. Flag/state model — why startup-zero is insufficient

### 5.1 Observed initialization

- `0xbe1b` starts at `1` (`0x10b17.c:34`).
- `0xf2fb` and `0xf2fa` start at `0` (`0x10b17.c:126-128`).
- `0xf3df` starts at `0` (`0x10b17.c:346`) and is also cleared in a bulk state reset (`0x11be9.c:274`).
- No direct write to `0x5e31`, `0x5fab`, `0x6029`, or `0x604b` appears in the decompiled load module. They are nevertheless read as live bytes in VORS (`0x2408d.c:94`, `0x2408d.c:113`, `0x2408d.c:222-238`) and in overlay selection (`0x2bffd.c:142`, `0x2bffd.c:199-215`).

### 5.2 Observed dynamic behavior

- `0xf2fa` is reset at scene entry (`0x11be9.c:67-68`) and set to `1` for a specific room set when `0xcac2 == 3 && 0xf2f9 == 0` (`0x11be9.c:88-95`). Other handlers also set it (`0x19ccf.c:35-37`, `0x1b38e.c:282-289`). It is therefore a per-scene/mode gate, not a startup constant.
- `0xf481` controls draw-vs-click behavior inside the same VORS call (`0x2408d.c:542-555`); writes are seen in overlay/input code such as `0x369e3.c:79` and `0x36d9e.c:33`.
- The VORS room argument `R` changes during play: `0xbe1b` is assigned from the current scene in `0x184e4.c:449` and read throughout scene dispatch (`0x11be9.c:60`, `0x11be9.c:88-95`).
- `U32[0x4b3a]`, `U32[0x4b3e]`, `U32[0x4b5c]` are assigned from the current room under room/flag conditions (`0x1b38e.c:168-179`), so the “remembered room” comparisons in records 43/47/48/49 are also dynamic.
- The same flag bytes select conditional FR overlays: examples include `F[0x5e31]`, `F[0xf2fb]`, `F[0x5fa7]` at `0x2bffd.c:142-175`; `F[0x5fab]` at `0x2bffd.c:199-215`; and `F[0x5fb0]`, `F[0x5fb3]`, `F[0x5fb6]` at `0x2bffd.c:238-291`. A VORS implementation that assumes they are always zero will show the initial label/overlay combination forever even after the game state changes.

### 5.3 Required model

Model these as one persistent mutable byte/word state with:

1. **Initial/new-game defaults** — apply the observed startup resets, not “all zero” globally (`0x10b17.c:34`, `0x10b17.c:126-128`, `0x10b17.c:346`, `0x11be9.c:274`).
2. **Scene/room inputs** — recompute `R = 0xbe1b`, `P = 0x32d0`, `0xf2f9`, `0xf2fa`, `0xf481` per frame/click (`0x25206.c:612`, `0x11be9.c:67-95`, `0x2408d.c:542-555`).
3. **Persistent world flags** — store `0x5e31`, `0xf2fb`, `0x5fa7`, `0x5fab`, `0x6029`, `0x604b`, `0xf3df`, `0x5fb0`, `0x5fb3`, `0x5fb6`, etc., as mutable bytes, updated by the room/action interpreter and restored by save/load. Exact interpreter opcodes remain unresolved (`docs/RE_FINDINGS.md:174-177`), so do not hardcode them to zero.
4. **Dynamic remembered globals** — treat `U32[0x4b3a]`, `U32[0x4b3e]`, `U32[0x4b5c]`, `U32[0x4b9a]`, `U32[0x4a62]`, `I32[0xb894]`, `I32[0x6bc4]` as state (`0x1b38e.c:168-179` for three of them; others unresolved).
5. **Evaluation order** — clear slot buffers, load original labels, apply branch assignments in source order, then iterate only slots `< count`, then apply `0xf481` output behavior (`0x2408d.c:62-90`, `0x2408d.c:93-474`, `0x2408d.c:476-563`).

## 6. Corrections to the current reconstruction

- `engine.zig:vors_overrides` (`src/engine.zig:37-99`) and `actionForSlot()` (`src/engine.zig:555-571`) are a **partial** model. Missing records from the override chain include `35, 36, 38, 40, 43, 47, 48, 49, 60, 71, 115, 118, 123, 129, 130, 134`.
- The key must remain **picture id** (`0x32d0`), not room id (`docs/RE_FINDINGS.md:110-112`).
- Preserve the distinction between `∅` (length 0, no command) and `' '` (length 1, one-space command) for every slot. The original VORS data and the hardcoded overrides both use both forms.
- `docs/RE_FINDINGS.md:128-130` should be revised: “flags not yet modified keep their startup value zero” is only a new-game snapshot, not a general invariant. The correct statement is that flags are live state read by VORS and overlay selection every call, with mutators partly unresolved.

## 7. Observed vs inferred

| Category | Items |
|---|---|
| **Observed from decompilation / raw data** | Record addressing via `param_1 * 0x377`; 15-slot 51-byte buffers and 4-coordinate groups; slot count gate; all hardcoded branch conditions and labels in `0x2408d.c:93-474`; global gates `0xf2fa` / `0xf481`; caller copies label into `0xc9c2` and submits with `\r`; record 0 sentinel; original labels decoded from `VORS.BIN`; startup values for `0xbe1b`, `0xf2fa`, `0xf2fb`, `0xf3df`; FR overlay reads of the same flags. |
| **Inferred / not yet proven** | Semantic game meaning of individual flags (e.g. which exact action sets `0x5e31`); exact interpreter opcodes or overlay routines that mutate `0x5e31`, `0x5fab`, `0x6029`, `0x604b`, `0x4b9a`, `0x4a62`, `0xb894`, `0x6bc4`; save-file mapping for these bytes. These are inferred to be mutable because they are read dynamically and mirrored by overlay state, but the mutators were not located in the analyzed load module. |
| **Observed but inert in shipped data** | `count > 14 -> count = 1` clamp (`0x2408d.c:476-478`); slot assignments beyond each record’s `count`; record 27 room-70 labels duplicating the original labels after an unconditional blank. |
