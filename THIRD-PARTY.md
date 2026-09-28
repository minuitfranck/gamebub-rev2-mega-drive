# Third-party notices

This core is a port of other people's work. Every component keeps its own copyright headers and license text in
the source tree; this page lists them in one place. The port as a whole is distributed under the GNU General Public
License, version 3 (`LICENSE`), the license of the core it is built from.

| Component | Where | Authors | License |
|---|---|---|---|
| MiSTer Genesis core (`Genesis_MiSTer` @ adc0c42, "Release 20230224") | `fpga/verilog/md/rtl/` | Gregory Estrade (FPGAGen, 2010 to 2013); MiSTer port and maintenance: Sorgelig (Alexey Melnikov), srg320, greyrogue, Kitrinx, dshadoff, Till Harbaum and the MiSTer contributors | GPL-3.0-only (`fpga/verilog/md/LICENSE`) |
| Save-state engine (`Genesis_MiSTer_Savestates` R58) | `fpga/verilog/md/rtl/savestate/`, changes in `system.sv`, `vdp.vhd`, the Z80 and memory paths | keFEAR89 | Published as a fork of the GPL-3.0 core; no separate license file in that repository |
| FX68K, 68000 CPU | `fpga/verilog/md/rtl/FX68K/` | Jorge Cwik | GPL (see the file headers) |
| T80, Z80 CPU | `fpga/verilog/md/rtl/T80/` | Daniel Wallner; MiSTer changes by Sorgelig | BSD-style (see the file headers) |
| jt12 (YM2612) and jt89 (SN76489) | `fpga/verilog/md/rtl/jt12/`, `rtl/jt89/` | Jose Tejada Gomez (jotego) | GPL-3.0 (`fpga/verilog/md/rtl/jt12/LICENSE`) |
| Game Bub FPGA framework and boot design | `fpga/framework/`, `fpga/src/main/scala/platform/`, `lib/`, `net/gamebub/core/boot/`, `fpga/verilog/handheld/`, `picorv32.v` | Eli Lipsitz and Game Bub contributors | CERN-OHL-S-2.0 (`LICENSE-CERN-OHL-S`); firmware-side code GPL-3.0 (`LICENSE-GPL-V3`) |
| PicoRV32 (the boot design's soft CPU) | `fpga/verilog/picorv32.v` | Claire Xenia Wolf | ISC |
| Chisel, mill and their dependencies | build time only | The Chisel and mill projects | Apache-2.0 and others |

The Game Bub glue for this core (`fpga/src/main/scala/net/gamebub/core/md/`, `fpga/verilog/md/rtl/gamebub/`, the
bench under `fpga/verilog/md/sim/`, the notes under `docs/`) was written for this port by minuitfranck with Claude
(Anthropic) and is released under the same GPL-3.0.

"Game Bub" is the name of Eli Lipsitz's project; this port is unofficial and uses neither the name nor the logo as
its own. "Mega Drive", "Genesis" and "Sega" are trademarks of Sega; the core contains no Sega code and no games.
