# Hexuma room/action interpreter — reverse-engineering report

**Status:** research report only. No project or asset files were modified. All scratch artifacts are under `/tmp/opencode/`.

## 1. Executive conclusion

The requested “room/action bytecode interpreter with an opcode dispatch table” was **not found as such** in the analyzed load module. The observed design is instead:

1. a **hardcoded, compiled parser/action pipeline** in the DOS executable, driven by verb id, object/noun id, room id, and many fixed global state bytes;
2. **data-driven vocabulary/tables** (`VERBEN.SEQ`, `OBW*.SEQ`, `OBNINT*.BIN`, `OBNBYT*.BIN`, `OBNWOR*.BIN`, `LAND.BIN`, `OBLISTE.BIN`, `TEXT*.REL`);
3. a large body of **compiled x86 room/action code in `HEXUMA.OVR`**, not a flat opcode stream;
4. `cd 3f`-marked records/thunks in the EXE whose exact dispatch mechanism is still unresolved, and which Ghidra misclassifies as tiny “functions.”

Therefore, no defensible opcode table can be produced from the current evidence. What can be mapped precisely are the **action primitives** (print text, show picture/overlay, wait/flush message, change room/object globals, set flags, choose menu commands) and the call sites that use them.

Evidence labels below: **[O]** = directly observed in bytes/disassembly/decompiler output; **[I]** = inference or interpretation; **[?]** = unresolved.

---

## 2. Address, file, and evidence conventions

- **Ghidra address** in `hexuma-decompiled/functions/*.c` is the post-relocation linear address printed by REA/Ghidra.
- **Runtime far segment:offset** → Ghidra linear address: `linear = runtime_segment * 16 + offset`.
- **Raw EXE/OVR far-call segment word** is 0x1000 less than the runtime segment because the MZ loader adds load segment 0x1000. Example: raw `9a 7b 4e 89 0c` at `0x11c0a` is `0x0c89:0x4e7b`; runtime segment is `0x1c89`; Ghidra address is `0x1fdcf` (`/tmp/opencode/hex_full.asm:13881`; `0x1fdcf.c:1-5`).
- **File offset** for a load-module pointer: `file_offset = runtime_segment * 16 + offset - 0x9a00` (`docs/RE_FINDINGS.md:98-99`).
- Overlay far calls were counted by reading raw segment words in `HEXUMA.OVR`, adding 0x1000, and mapping to decompiled helper addresses. This arithmetic is consistent across thousands of calls, but the overlay loader itself remains undecoded.
- Ghidra pseudocode is provider output, **not original source**. Raw bytes/disassembly are authoritative for call targets, constants, and strings.
- `14999` / `0x3a97` in Ghidra pseudocode is the containing `CS` segment artifact, not a literal data segment (`docs/RE_FINDINGS.md:40-47`).

---

## 3. Requested focus functions: observed roles

| Supplied address | Decompiler name | Observed role | Key evidence |
|---|---|---|---|
| `0x11be9` | `FUN_119c_0229` | **Object/action effect dispatcher.** Branches on current object id `byte[0xbe1b]`, verb id `int[0xcac2]`, and noun/object globals; writes room/object/flag globals; calls per-object handlers and message/picture helpers. | `0x11be9.c:59-107`, `481-521`, `572-574`, `686-688`, `831-833`, `869-913`; raw `0x11be9` prologue and far calls at `hex_full.asm:13881`, `13995-14094`. |
| `0x184e4` | `FUN_1755_0f94` | **Condition/fixup preprocessor.** Long chain of hardcoded state corrections before action execution; not a bytecode dispatcher. Rewrites verb id, noun ids, and parser flags. | `0x184e4.c:38-56`, `59-177`, `181-438`, `447-485`. |
| `0x1b140` | `FUN_1755_3bf0` | **Verb-id dispatcher.** Switches on `int[0xcac2]`; unknown verbs print message `id - 1` or `0x39`. | `0x1b140.c:24-91`. |
| `0x17d2f` | `FUN_1755_07df` | **Verb/noun token matcher.** Uses 31-byte token records, verb table lookups, noun gate `0x449e`, aliases, and `LAND.BIN`-style adjacency `room*0xe + slot*2 - 0x52b0`. | `0x17d2f.c:35-40`, `67-72`, `124-129`, `152-221`, `244-256`. |
| `0x23c4e` | `FUN_1c89_73be` | **Room command-menu loader.** Opens `OBLISTE.BIN`, reads 256 `u16` offsets, seeks to current room, reads `u16 count`, then `count + 1` Pascal strings into `idx*0x65 + 0x7d8e`. | `0x23c4e.c:27-66`; layout in `docs/FORMATS.md:223-236`. |
| `0x21971` | `FUN_1c89_50e1` | **Command-menu UI.** Reads menu dimensions from `0x1cee`, draws menu, accepts selection, displays `OBLISTE.BIN` strings. Selected by main loop on `';'` or flag `0x1ce8`. | `0x21971.c:59-75`, `123-132`, `135-241`; `0x25206.c:363-365`. |
| `0x25206` | `FUN_1c89_8976` | **Main input loop.** Reloads room commands on room change, handles GUI/VORS regions, inventory-like displays, `';'` menu, command submission, and parser helpers. | `0x25206.c:57-60`, `88-111`, `363-367`, `450-550`, `558-680`. |

---

## 4. Parser and action flow

### 4.1 Input parsing and verb selection

**[O]** `0x1755d` (`FUN_1755_000d`) splits input into 31-byte token records and maps verb ids from `VERBEN.SEQ` into parser flags:

- `0xe → 0xcad4 = 1` (`0x1755d.c:101-102`)
- `9 → 0xf2b7`, `0x10 → 0xf2b9`, `0x11 → 0xf2ba`, `0x12 → 0xf2bb`, `0x15 → 0xf2c0`, `7 → 0xf2bf`, `0x17 → 0xf2bc`, `0x16 → 0xf2bd`, `0x18 → 0xf2be`, `0x19 → 0xf2c1`, `0x1a → 0xf2c2` (`0x1755d.c:104-135`)
- `0x1b..0x20 → 0xc9be = 1..6` and `0x21..0x26 → 0xf2c3 = 1..6` (`0x1755d.c:137-171`)
- `0x27..0x2a → 0xf2c4..0xf2c7`; `0x1b` also sets `0xf2c8` (`0x1755d.c:173-186`)

**[O]** `0x17d2f` reads token strings with stride `0x1f` at `-0x40da`, writes the selected verb id to `0xcac2` from `byte[verb_idx - 0x58f0]` (`0x17d2f.c:67-72`). It later resolves nouns using:

- room/alias gate `idx*2 + 0x449e` (`0x17d2f.c:156-170`),
- alias chain `(gate < -1) → -gate*2 + 0x449e` (`0x17d2f.c:165-170`),
- adjacency test `current_room*0xe + candidate_slot*2 - 0x52b0` (`0x17d2f.c:181-182`, `220-221`),
- selected noun stored to `idx*2 - 0x41a6` via `0x7d8c` (`0x17d2f.c:159`, `170`, `201`, `209`, `245`, `251`).

**[O]** `0x1b140` then dispatches the verb id (`0x1b140.c:45-87`):

| `int[0xcac2]` | Target |
|---:|---|
| `1` | `FUN_1755_203d` |
| `2` | `FUN_1755_2362` |
| `3` | `FUN_1755_277f` |
| `5` | `FUN_1755_2e93` |
| `4`, `6` | `FUN_1755_31a1` |
| `7` | `FUN_1b27_011e` |
| `8` | `FUN_1755_38cf` |
| `9` | `FUN_1755_373a` |
| `0x32` | `FUN_1755_37b5` |
| `0x30` | `FUN_1755_1f87` |
| `99` | `FUN_1755_39f8` |
| other `< 0x3d` | `FUN_1c89_a3d8(verb - 1)` |
| other `>= 0x3d` | `FUN_1c89_a3d8(0x39)`, set `0xcae0 = 1` |

`0x43` and `0x41` are explicitly excluded from the fallback error path (`0x1b140.c:79-87`).

### 4.2 State fixups before action execution

**[O]** `0x184e4` (`FUN_1755_0f94`) performs numerous hardcoded repairs. Examples:

- `0xb7 < byte[0xbe1b] < 0xbd && int[0xcac2] == 0x9a → 0xcac2 = 0xcac8` (`0x184e4.c:39-40`).
- `byte[0xbe1b] == 'S'`: `be5c 0x2b7 → 0x2b8`, with follow-up handling through `be5e`, `be60` (`0x184e4.c:42-56`).
- Verb-id rewrites for specific noun pairs, e.g. `0x49 + {0x282,0x283} → 2` (`0x184e4.c:188-196`), `0x49 + cad0 20 → 0x13` (`0x184e4.c:210-211`), `0x75 + cad0 2 → 6` (`0x184e4.c:267-268`).
- Parser flag loops over `f2b9/f2ba/f2bb` set `be5c` from candidate objects (`0x184e4.c:227-254`).
- Invalid/unknown combinations print message `0x56`, `0x57`, `0x58`, or `0x59` through `FUN_1c89_a3d8` (`0x184e4.c:377-438`).
- Large condition chains compare verb id `0xcac2` against many constants (`0x184e4.c:387-413`), again showing direct-coded rules rather than an opcode table.

---

## 5. `0x11be9`: object/action effect dispatcher

### 5.1 Entry gates

**[O]** At entry, `uVar4 = 0x119c` (default message segment). A special gate changes it to `0x1c89` and calls `FUN_1c89_4e7b(0x8e)` when:

```text
byte[0xbe1b] > 0xa0 && int[0xcac2] == 3 && int[0xbe5c] == 0x24a
```

(`0x11be9.c:59-63`; raw `cmpb $0xa0,0xbe1b`, `cmpw $3,0xcac2`, `cmpw $0x24a,0xbe5c`, `lcall 0xc89:4e7b` at `hex_full.asm:13881-13890`).

**[O]** It clears temporary state `0xcae8`, `0xcaea`, `0xc9c0`, `0xf2f9`, `0xf2fa` (`0x11be9.c:64-68`), sets special object flags for object ids `0xb8`, `0xbd`, `0xc2` (`0x11be9.c:69-77`), and computes `f2f9/f2fa` from flags `0x5e03`, `0x5f71` and room/object comparisons against `0x44dc`, `0x47b8` (`0x11be9.c:78-93`). If `f2fa == 1` with verb `3` and certain object ids, it returns early (`0x11be9.c:88-95`).

### 5.2 Object-id → handler ranges

**[O]** The main dispatch is a chain of hardcoded object-id ranges. Decompiler names embed runtime segment and offset; the raw far calls store segment values 0x1000 lower.

| Object id (`byte[0xbe1b]`) | Called target | Decompiler name | Exact evidence |
|---|---|---|---|
| `1..0x10`, `0x12..0x14`, `0x16`, `0x18` | runtime `0x1346:0x25` | `FUN_1346_0025` | `0x11be9.c:101-104`; raw `lcall $0x346,$0x25` at `11d46` (`hex_full.asm:13995`) |
| `0x1b..0x25` | `0x133a:0x25` | `FUN_133a_0025` | `0x11be9.c:106-108`; `11d59` (`hex_full.asm:14002`) |
| `0x41..0x51` | `0x1337:0x25` | `FUN_1337_0025` | `0x11be9.c:877-879`; `11d80` (`hex_full.asm:14017`) |
| `0x52..0x61` | `0x1334:0x25` | `FUN_1334_0025` | `0x11be9.c:881-883`; `11d93` (`hex_full.asm:14024`) |
| `0x77..0x83` | `0x1343:0x25` | `FUN_1343_0025` | `0x11be9.c:885-887`; `11da6` (`hex_full.asm:14031`) |
| `0x84..0x91` | `0x1340:0x25` | `FUN_1340_0025` | `0x11be9.c:889-891`; `11db8` (`hex_full.asm:14038`) |
| `0x92..0x9d` | `0x133d:0x25` | `FUN_133d_0025` | `0x11be9.c:893-895`; `11dca` (`hex_full.asm:14045`) |
| `0xa0..0xa9`, `0xb0` | `0x1331:0x25` | `FUN_1331_0025` | `0x11be9.c:897-899`; `11de0` (`hex_full.asm:14054`) |
| `0xaa..0xaf`, `0xb1..0xb7`, `0xef` | `0x1328:0x25` | `FUN_1328_0025` | `0x11be9.c:901-904`; `11dfe` (`hex_full.asm:14067`) |
| `0xb8..0xc6` | `0x132e:0x25` | `FUN_132e_0025` | `0x11be9.c:906-908`; `11e10` (`hex_full.asm:14074`) |
| `0xc7..0xee`, `0xf0` | `0x132b:0x25` | `FUN_132b_0025` | `0x11be9.c:910-912`; `11e26` (`hex_full.asm:14083`) |
| `0` | — | message `0` via `FUN_3a97_0644`, then `FUN_1c89_2fdc` | `0x11be9.c:915-917` |

**[?]** These targets are not ordinary compiled procedures. At Ghidra address `0x13485` (runtime `0x1346:0x25`, file offset `0x9a85`) the raw bytes are:

```text
cd 3f dc 0d 00 00 00 00 00 00 00 1b 4c 61 73 73 65 6e ...
```

i.e. `int 3f`, a 16-bit word `0x0ddc`, zeros, then German message strings. The same pattern appears at the other target addresses (`0x132a5`, `0x132d5`, `...`, `0x13455`): `cd 3f <id> ...` (`hex_full.asm:15754-15958`; raw dump at EXE file `0x9880-0x9a95`). **[I]** These are `INT 3F`-marked descriptors/thunks or overlay call records; the exact handler/dispatch path is unresolved. Ghidra’s `swi(0x3f)` pseudocode for `0x132a5.c`–`0x13455.c` is garbled and unusable.

### 5.3 Observed side effects

**[O]** `0x11be9` directly changes world state. Examples:

- `0xcac2 = 3`, `0xbe5c = 0`, `0xbe1b = 0xa0` (`0x11be9.c:572-574`).
- `0xbe1b = 0x78`, `0xcac2 = 3`, `0xbe5c = 0` (`0x11be9.c:686-688`).
- `0xbe1b = 0x41` (`0x11be9.c:716`).
- `0xbe1b = 0x92`, `0xcac2 = 3`, `0xbe5c = 0` (`0x11be9.c:831-833`).
- `0xbe1b = 0x1b`, `0xcac2 = 3`, `0xbe5c = 0`, then message `0x3a99` and picture refresh via `FUN_1c89_353f` (`0x11be9.c:869-874`).
- Special verb/object gates: verb `7` with object `0x1cb` (`0x11be9.c:481`), verb `0x37` with object `0x1ce` (`0x11be9.c:521-522`).

**[I]** Because `0xbe1b` is compared with the cached room in `0x25206.c:57-60` and used to reload `OBLISTE.BIN`, writes to `0xbe1b` are room/current-scene changes. They are not opcode-immediate “move room” operands; they are compiled assignments inside per-object handlers.

---

## 6. Action primitives that *are* identifiable

No generic opcode numbers were recovered, but the following primitives are directly observable.

| Primitive | Observed implementation | Evidence |
|---|---|---|
| **Set/clear flag** | Direct writes to global bytes/words: `0xcae8`, `0xcaea`, `0xc9c0`, `0xf2f9`, `0xf2fa`, `0xcad4`, `0xf2b7..0xf2c8`, `0x3d94`, `0x3dc6`, `0x3e4a`, etc. | `0x11be9.c:64-77`; `0x1755d.c:101-187`; `0x184e4.c:38-56`, `227-254`. |
| **Change room / current object** | Writes to `byte[0xbe1b]`; main loop detects change via `0xc916` and reloads commands. | `0x11be9.c:572-574`, `686-688`, `831-833`, `869-871`; `0x25206.c:57-60`. |
| **Print TEXT*.REL message** | `FUN_1c89_a3d8(id)` reads id, subtracts 1, selects one of `TEXT1/2/3/4/5/7/8/9/10.REL`, reads a 0x4d-byte record. | `0x26c68.c:54-116`; `docs/FORMATS.md:124-148`; `docs/RE_FINDINGS.md:76-80`. |
| **Print in-code Pascal message** | `FUN_3a97_0644(dest, len, far_ptr)` bounded copy; many far pointers to German strings in code. | `docs/RE_FINDINGS.md:82-99`; `0x11be9.c:915`; `0x184e4.c:84-85`, `106-107`, `309-310`. |
| **Flush/wait message buffer** | `FUN_1c89_2fdc` clears `0xcaea`, splits long buffer into screen-width chunks, waits/accepts key, then clears. | `0x1f86c.c:33-92`. |
| **Picture / conditional overlay** | `FUN_2bab_054d` builds `bild<id>.seq` plus conditional `FR*` overlays; called by `FUN_1c89_353f` and heavily from overlay code. | `docs/RE_FINDINGS.md:35`; `0x1fdcf.c:18-25`; overlay far-call histogram below. |
| **Room command menu** | `';'` sets `0x1ce8`; main loop calls `FUN_1c89_50e1`, which reads `OBLISTE.BIN` strings. | `0x25206.c:363-365`, `665-666`; `0x23c4e.c:27-66`; `0x21971.c:59-75`, `123-132`. |
| **Inventory-like display** | Main loop checks `0xf2b0` and calls `FUN_3443_2a5f`/`FUN_3443_2a98` with rectangular regions; no separate “inventory opcode” found. | `0x25206.c:147-345`. |
| **Conditional jumps** | Hardcoded x86/Ghidra `if` chains on verb/object/room/flags; overlay code uses ordinary x86 branches. No numeric condition opcodes found. | `0x184e4.c:38-438`; `0x11be9.c:59-95`, `481-521`, `877-913`; `ovr_block0.asm`. |
| **Sound** | **Not identified.** No sound/audio dispatch helper or opcode was found in the decompiled set; the only direct match is the overlay string about leaving the loudspeaker alone. | `HEXUMA.OVR` string at file `0x13e`; grep of `functions/*.c` for `sound|audio|speaker|music|beep` returned no matches. |

---

## 7. Data tables and assets decoded

### 7.1 Vocabulary and world tables

**[O]** Prior format work established:

- `VOREIN.SEQ` sets counts/limits including `0xa196=245`, `0xa198=345`, `0xa19a=10`, `0xa19c=1060`, `0xa19e=240` (`docs/FORMATS.md:183-194` context; `0x1755d.c:87`, `0x184e4.c:347` use `0xa19c`).
- `VERBEN.SEQ`: 345 real verb records plus terminator (`docs/FORMATS.md:187`).
- `OBNINT*.BIN`: 1060 × 4 bytes = two `i16`; `field_b` is room gate, `0xffff` global, negative aliases another noun (`docs/FORMATS.md:152-154`; matching checks at `0x17d2f.c:156-170`).
- `OBNBYT*.BIN`: 1060 × 3 class-flag bytes; exact taxonomy unresolved (`docs/FORMATS.md:155-156`, `164-165`).
- `OBNWOR*.BIN`: 1060 × 4 = two 1-based `TEXT*.REL` ids (`docs/FORMATS.md:157-158`).
- `LAND.BIN`: 240 × 14 = seven `i16`; six directional exits plus room id/slot data (`docs/FORMATS.md:159-160`; `docs/RE_FINDINGS.md:72-74`; adjacency use at `0x17d2f.c:181-182`).
- `OBLISTE.BIN`: 256 `u16` room offsets, then `u16 count`, then `count + 1` Pascal strings (`docs/FORMATS.md:223-232`; loader `0x23c4e.c:27-66`).
- `TEXT*.REL`: 77-byte records; stored bytes decoded as `(stored + 0x14)` with `0x2f → space`, CP850; `@` terminates display (`docs/FORMATS.md:126-148`; `docs/RE_FINDINGS.md:76-80`).

**[?]** Remaining table ambiguities: `OBNBYT` class meanings, `OBNINT.field_a` uses, and which `OBNWOR` field is selected in different noun states.

### 7.2 `HEXUMA.OVR` is compiled code, not a bytecode blob

**[O]** File `/home/bob/Downloads/Hexuma/HEXUMA.OVR` is 0x18c65 bytes. It begins with 12 Pascal strings at file offsets `0x4..0x243`, then code. The strings are:

```text
0x004 Keine Action programmiert für diesen Raum
0x02e Einen alten Mann so anlügen! Wo gibts denn sowas?
0x060 "Sag mir doch den Namen dessen, den Du suchst!"
0x090 tell
0x095 Hey! So geht es ja nicht! Die Arbeit eines ehrlichen Programmieres zu umgehen! Neiiiinnn So nicht!!!
0x0fa Kaum setzen Sie sich in Bewegung ziehen Sie gleichzeitig am Seil...
0x13e Lassen Sie den Lautsprecher jetzt lieber liegen!
0x16f Hoopla! Haben wir Ihn schon...
0x18e So leicht kann man die Tür nicht öffnen!
0x1b7 Bitte geben Sie die exakte Richtung ein!
0x1e0 Sie haben den kleinen Pit ja gar nicht in der Hand!
0x214 Das Amulett alleine hilft Ihnen da gar nichts!
```

**[O]** Code starts at file offset `0x243` with:

```text
55 89 e5 83 ec 0a 31 c0 a3 e8 ca c6 06 ea ca 00 31 c0 a3 c0 c9 ...
```

Eleven `55 89 e5` (`push bp; mov bp,sp`) prologues were found at overlay file offsets:

```text
0x243, 0x2aa8, 0x465f, 0x742d, 0x8c96, 0xaa22, 0xd627,
0xf2a5, 0x10414, 0x127d0, 0x15744
```

**[O]** Far calls from these code blocks to the main EXE map, after adding the 0x1000 load segment, to these helpers (aggregate counts across all 11 blocks; scanning may include some false positives in data, but the dominant calls are consistent):

| Decompiled helper | Raw far target in OVR | Count | Likely role |
|---|---:|---:|---|
| `FUN_1c89_a3d8` (`0x26c68`) | `0x0c89:0xa3d8` | 1354 | print `TEXT*.REL` id |
| `FUN_3a97_0644` (`0x3afb4`) | `0x2a97:0x0644` | 382 | bounded far-string copy |
| `FUN_1c89_2fdc` (`0x1f86c`) | `0x0c89:0x2fdc` | 368 | flush/wait message buffer |
| `FUN_1346_0025` | `0x0346:0x0025` | 166 | `cd3f` action descriptor/thunk (unresolved) |
| `FUN_2bab_054d` (`0x2bffd`) | `0x1bab:0x054d` | 54 | picture + conditional overlays |
| `FUN_1c89_353f` (`0x1fdcf`) | `0x0c89:0x353f` | 44 | picture refresh for current object |
| `FUN_1c89_8976` (`0x25206`) | `0x0c89:0x8976` | 21 | main loop / command handling |
| `FUN_1c89_0d91` (`0x1d621`) | `0x0c89:0x0d91` | 10 | unresolved |
| `FUN_1c89_4e7b` (`0x2170b`) | `0x0c89:0x4e7b` | 1 | special action branch used by `0x11be9` |

**[O]** Example overlay call bytes: at overlay file `0x2c7`, `9a 3f 35 89 0c` = raw `0x0c89:0x353f` (`ovr_block0.asm:41`). At `0x3ee`, `9a 44 06 97 2a` = raw `0x2a97:0x0644` (`ovr_block0.asm:150`).

**[I]** The overlay therefore contains **compiled action bodies** for rooms/objects, calling shared runtime helpers. It is not evidence for a numeric opcode interpreter. Branch conditions in overlay code are ordinary x86 comparisons and jumps against the same globals (`0xbe1b`, `0xcac2`, `0xbe5c`, `0xf2fa`, etc.).

---

## 8. Overlay/loader and `cd 3f` state of knowledge

**[O]** The string `hexuma.ovr` appears in `HEXPRG.EXE` at file offset `0x7e37` (decimal 32311), near a far-call sequence; the entry area at Ghidra `0x11841` begins with far calls to runtime segments `0x2a97`, `0x29df`, `0x2443`, `0x1d09`, `0x1c89` (`entry.asm:5-12`). No decompiled `0x11841.c` body is present.

**[O]** The main EXE installs interrupt vectors including `0x253f` (`mov ax,0x253f; int 21`) in the startup code at Ghidra `0x3a9db` (`hex_full.asm` disassembly around `0x3a9c0-0x3a9e3`). The handler reached with raw segment `0x2a97`, offset `0xc6` (Ghidra `0x3aa36`) manipulates a saved far continuation pointer at `0xb16:0xb18` and can `lret` to it, otherwise prints diagnostics and exits via DOS `AH=4Ch` (`0x3aa36-0x3ab02`).

**[?]** It remains unproven whether INT 3F is the normal action-thunk dispatch path, an exception/continuation mechanism, or both. The `cd 3f <id>` records in the EXE and the overlay far-call records are consistent with a thunk/descriptor scheme, but the exact table lookup and overlay load segment are not decoded. This is the largest remaining blocker to a complete action-semantics reconstruction.

---

## 9. What was *not* found (negative results)

- **No opcode dispatch table** with numeric opcodes mapped to set/clear flag, move room, print text, inventory, picture/overlay, sound, or conditional jump.
- **No generic “inventory opcode.”** Inventory-like behavior is composed from object-id dispatch, noun/object tables, flags, and UI region checks.
- **No sound helper or sound opcode** in the decompiled function set.
- **No meaningful bytecode in `HEXUMA.OVR`.** It is x86 machine code plus strings.
- **No usable pseudocode for `0x132a5`–`0x13455`.** Raw bytes begin with `cd 3f` and are followed by data/strings; decompiler output is garbled.

Negative results are limited to the analyzed load module and supplied decompiled corpus; they do not prove absence in an unexamined overlay path, a save file, or an undecoded runtime-generated table.

---

## 10. Unresolved items / recommended next steps

1. **Decode the INT 3F mechanism.** Trace `0x3aa36`, `0xb16:0xb18`, and the `cd 3f <id>` descriptors at EXE Ghidra addresses `0x13280..0x13485`. Determine how a call to raw `0x0346:0x25` reaches an overlay body.
2. **Establish overlay load segment and relocation.** The `HEXUMA.OVR` far calls only map correctly after adding 0x1000 to raw segment words; the loader code around `HEXPRG.EXE:0x7e37` and entry `0x11841` must be decoded to confirm where the 11 code prologues are loaded.
3. **Reconstruct overlay block boundaries semantically.** The 11 `55 89 e5` prologues are observed, but their association to specific rooms/object groups is not proven.
4. **Finish helper semantics.** `FUN_2bab_054d`, `FUN_1c89_353f`, `FUN_1c89_0d91`, `FUN_1bc0_00a6`, `FUN_1c89_a3d8`, and `FUN_1c89_2fdc` are partially understood; exact side effects and argument conventions still need manual confirmation.
5. **Resolve table field meanings.** Especially `OBNBYT` taxonomy, `OBNINT.field_a`, and `OBNWOR` field selection.
6. **Do not treat Ghidra `FUN_1328..FUN_1346` names as real functions** until the `cd 3f` records are decoded; they are almost certainly descriptor/thunk artifacts.

---

## 11. Evidence inventory

Primary artifacts:

- `/home/bob/Downloads/Hexuma/HEXPRG.EXE`
- `/home/bob/Downloads/Hexuma/HEXUMA.OVR`
- `/tmp/opencode/hex_full.asm`
- `/tmp/opencode/entry.asm`
- `/tmp/opencode/hexuma-decompiled/decompile-index.json`
- `/tmp/opencode/hexuma-decompiled/functions/0x11be9.c`, `0x184e4.c`, `0x1b140.c`, `0x17d2f.c`, `0x23c4e.c`, `0x21971.c`, `0x25206.c`, `0x1755d.c`, `0x26c68.c`, `0x1f86c.c`, `0x1fdcf.c`, `0x2170b.c`
- `/home/bob/Documents/Default Project/hexuma-zig/docs/RE_FINDINGS.md`
- `/home/bob/Documents/Default Project/hexuma-zig/docs/FORMATS.md`

All conclusions above are research findings only; no implementation or file modification was performed.
