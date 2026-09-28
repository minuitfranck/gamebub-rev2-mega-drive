# Mega Drive / Genesis core for the Game Bub rev2

An FPGA core for the rev2 (vertical) [Game Bub](https://github.com/elipsitz/gamebub) handheld: the archived MiSTer
Genesis core on the Game Bub's FPGA framework, with save states. Current build: **r2.19**.

Not affiliated with, endorsed by or supported by Eli Lipsitz or the Game Bub project. The rev4 has its own
official releases; this core runs on a rev2 with the rev2 community firmware.

## What is in it

- **The MiSTer Genesis core** (`Genesis_MiSTer` @ adc0c42, "Release 20230224"), unchanged where possible. The
  changes made for this port are listed in [`fpga/verilog/md/README.md`](fpga/verilog/md/README.md).
- **Save states**: keFEAR89's [Genesis_MiSTer_Savestates](https://github.com/keFEAR89/Genesis_MiSTer_Savestates)
  engine (R58), merged and adapted. Four slots, saved as `.ss` files in MiSTer's format. Four defects found on the
  hardware and in simulation are described in [`docs/md-port-design.md`](docs/md-port-design.md), section 12,
  findings A to D. Finding D (r2.19) is the one that made saves fail in busy scenes: the engine's "VDP memory idle"
  test read a toggle request line as a level. It applies to that engine on any platform.
- **The Game Bub glue** (Chisel, [`fpga/src/main/scala/net/gamebub/core/md/`](fpga/src/main/scala/net/gamebub/core/md/)):
  the cartridge in SDRAM behind a pipelined store, battery saves, the States file, the screen and audio paths,
  the settings, and diagnostics registers for the save-state engine.
- **A whole-system simulation bench** ([`fpga/verilog/md/sim/system/`](fpga/verilog/md/sim/system/)): the core,
  the SDRAM controller with a chip model and the firmware's protocol, with a save and a load; it can preload a
  States file from a handheld to start inside a saved scene.

## Installing on a rev2

Needs a rev2 Game Bub running the rev2 community firmware, which loads cores from the SD card. From the release
package, copy the folder `minuitfranck.MD` (with `md_rev2.bit`, `core.json`, `files.json`, `settings.json`) into
`cores/` on the card. Games go in `roms/MD/` as `.md`, `.gen` or `.bin`; battery saves are written next to them as
`.sav`, save states as one `.ss` file per game.

In a game, Home opens the menu. Its settings page has Reset, Save State, Load State, State Slot (1 to 4), Scaling
(4:3, Fit, 1x, Stretch), Screen Filter (Off, Smooth) and Region (Auto from the header, Japan, USA, Europe). Home + R
saves a state and Home + L loads it without opening the menu.

## Building

Vivado 2023.2, target `xc7a100tcsg324-1` (the rev2's FPGA). From `fpga/`:

```
./mill root.runMain platform.handheld.HandheldTop net.gamebub.core.md.HandheldMd 2 --target-dir=build/md-elab
```

elaborates the Chisel design; `fpga/scripts/build_core.py` builds the Vivado project from it and the Verilog under
`fpga/verilog/md/`. The framework's own notes are in [`fpga/framework/README.md`](fpga/framework/README.md).

## Known limits

- A state saved in the middle of a note restarts the note on load: the engine resets the sound chips.
- After a failed save or load, rare since r2.19, the game can restart from its logo. Under investigation.
- The picture is 320 x 224 (or 256 x 224) on a 320 x 240 screen; PAL games run at 50 Hz.

## Credits

- Gregory Estrade: FPGAGen, the Genesis core this descends from.
- Sorgelig (Alexey Melnikov), srg320, greyrogue, Kitrinx, dshadoff, Till Harbaum and the MiSTer contributors:
  the MiSTer Genesis core.
- Jorge Cwik: FX68K (68000). Daniel Wallner: T80 (Z80). Jose Tejada Gomez: jt12 and jt89 (sound).
- keFEAR89: the save-state engine.
- Eli Lipsitz: the Game Bub, its FPGA framework and firmware.
- minuitfranck, with Claude (Anthropic): the port, its fixes and these notes.

## License

GPL-3.0-only ([`LICENSE`](LICENSE)), the license of the core it is built from. Component licenses and copyright
notices: [`THIRD-PARTY.md`](THIRD-PARTY.md). The Game Bub framework files are under CERN-OHL-S-2.0
([`LICENSE-CERN-OHL-S`](LICENSE-CERN-OHL-S)). No games, BIOS or Sega code are included.
