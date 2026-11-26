# hexuma-zig

A Zig rewrite/host for the 1989 DOS adventure **Hexuma**. It understands the
original proprietary asset formats and exposes them in convenient, inspectable
formats:

- `.SEQ` pictures → indexed **PNG**
- `.AWS` audio → 8-bit PCM **WAV**
- fonts and tables → **JSON**
- text tables and recovered overlay dialogue → **JSON** and **Lua**
- game-logic data modules → **Lua**

The engine host is written in Zig; Lua 5.4.8 is vendored so the project builds
without system Lua packages.

## Requirements

- Zig 0.15.2 (the API used here targets 0.15.x)
- A C compiler (for the vendored Lua sources)
- X11 headers/libraries for the optional point-and-click window
- The original `Hexuma` directory (default: `/home/bob/Downloads/Hexuma`)

## Build

```sh
cd hexuma-zig
zig build
```

In this environment Zig was downloaded locally, so the equivalent command is:

```sh
/tmp/opencode/toolchain/zig-x86_64-linux-0.15.2/zig build
```

## Commands

```sh
# Decode every original asset
./zig-out/bin/hexuma extract \
  --input /home/bob/Downloads/Hexuma \
  --output extracted

# Describe one asset
./zig-out/bin/hexuma info /home/bob/Downloads/Hexuma/BILD001.SEQ

# Run the generated Lua entry point
./zig-out/bin/hexuma run extracted/lua/init.lua

# Play from extracted assets with the original German parser vocabulary
./zig-out/bin/hexuma play

# Numbered click-target mode / English alternative
./zig-out/bin/hexuma play --choices
./zig-out/bin/hexuma play --lang en --choices

# Portable JSON save state (use .json; .sav/.dat select the original format)
./zig-out/bin/hexuma play --save game.json
./zig-out/bin/hexuma play --load game.json

# True point-and-click X11 window (buttons map to the same action executor)
./zig-out/bin/hexuma gui --lang en
```

A smoke test is available:

```sh
./scripts/smoke.sh /home/bob/Downloads/Hexuma
```

## Output layout

```text
extracted/
  manifest.json          # source, size, SHA-256, decoded kind, output path
  images/*.png           # 263 decoded pictures/sprites/frames
  images/*.raw           # HXRAW1/BGRA siblings used by the X11 GUI
  audio/*.wav            # 7 decoded AWS sounds
  data/
    game.json            # semantic rooms, verbs, OBN*/VORS vocabulary and
                         # picture table, plus VORS.BIN click regions
    texts.json           # decoded TEXT*.REL records keyed by original text id
    dialogue.json        # length-prefixed strings recovered from HEXUMA.OVR
    text/*.json          # TEXT*.REL runs + original plain-text .SEQ tables
    tables/*.json        # fonts, LAND.BIN, OBLISTE.BIN, OBN* tables
  lua/
    init.lua             # engine entry point
    assets.lua           # image registry (dimensions + paths)
    dialogue.lua         # recovered German dialogue strings
    verbs.lua            # VERBEN.SEQ name/id pairs
    game.lua             # semantic game data for Lua consumers
    texts.lua            # decoded TEXT*.REL records keyed by original text id
    locale.lua           # German/English verb, noun and UI labels
    config.lua           # VOREIN.SEQ defaults
  original/              # verbatim copies of unresolved/extra files
```

## Verified extraction results

Against the supplied game directory:

- 271 `.SEQ` files: **263 binary images decoded**, 8 plain-text tables decoded
- 7 `.AWS` files decoded to WAV
- 34 JSON files, all parse successfully
- 263 PNG files, all pass signature/chunk/CRC validation
- 7 WAV files, all valid RIFF/WAVE
- Lua entry point loads all generated modules successfully
- 402 click regions recovered from `VORS.BIN` and wired into the X11 frontend
- 9131 `TEXT*.REL` records decoded with their original 1-based ids
- Base, ship (5) and mine (6) vocabulary tables decoded from OBN*/OBW files
- German `OBNWOR` descriptions are used by the engine's `untersuche` command
- German is the original language; English labels are authored alternatives

## Reverse-engineering notes

`HEXPRG.EXE` was opened with REA (Ghidra provider, 31 segments / 400
procedures). Its AGI driver string identifies the graphics path:

```text
256 COLOR AGI DRIVER, SERIAL: EVALUATION_COPY
VERSION 3.01,  COPYRIGHT (C) 1989 BY:  N.HUTH
```

`HEXUMA.OVR` contains the original German dialogue as `u8 length + bytes`
records. Public format documentation was not found, so the container layouts
were derived empirically from the asset bytes and corroborated with REA
strings/disassembly hints.

REA also identified the original subsystems: asset loading at `0x100f1`,
global flag initialization at `0x10b17`, input tokenization at `0x1755d`,
noun/verb lookup at `0x17d2f`, the main mouse/keyboard loop at `0x25206`,
VORS action initialization at `0x2408d`, room/hotspot gates at `0x11be9`,
scene rendering at `0x2bffd`, and save/load at `0x22b1f`. `TEXT*.REL` records
use `stored byte + 0x14` and CP850, with ids from `OBNWOR*.BIN`.

See [docs/FORMATS.md](docs/FORMATS.md) for exact byte layouts and caveats, and
[docs/RE_FINDINGS.md](docs/RE_FINDINGS.md) for the REA function map and evidence.

## Limitations

- The generated Lua modules are **data and orchestration scaffolding**, not a
  complete decompilation of every original opcode. The original room/action
  interpreter still needs to be reconstructed from the overlay bytecode.
- `TEXT*.REL` records are decoded exactly, but `HEXUMA.OVR` extraction remains a
  conservative printable-run scanner, not a full bytecode decoder.
- Font glyph metrics and some `.BIN` table semantics remain unresolved; their
  bytes are preserved losslessly as JSON hex records/tables.
- AWS sample rate (8000 Hz) is inferred and marked as such in `manifest.json`.
- There was no English release; all English text is newly authored, so it is an
  alternative rather than a restored original localization.
- The GUI draws original `VORS.BIN` hotspot rectangles over the room picture,
  but the original adds runtime screen offsets before hit-testing; exact pixel
  alignment still needs validation against DOSBox screenshots.
