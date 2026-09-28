# Mega Drive / Genesis port design for Game Bub rev2 — 2026-09-17

Personal-use build of the archived MiSTer Genesis core (GPL-3.0) for the rev2
(vertical) Game Bub, SD-card core `minuitfranck.MD`. Template: the NGPC port
(`docs/ngpc-port-design.md`), which solved the same central problem — a CPU
executing straight out of cartridge ROM in the framework's SDRAM. Progress,
build and simulation results live in `docs/md-port-status.md`.

**The goal is Comix Zone (USA).** Everything below is ordered by what that
game needs. Breadth is explicitly not a goal.

Sources read for this design:

- `Genesis_MiSTer` @ adc0c42 (the archived core; Gregory Estrade's FPGAGen
  lineage, ported and maintained by Sorgelig, with srg320, greyrogue, Kitrinx
  and dshadoff): `Genesis.sv`, `rtl/system.sv`, `rtl/vdp.vhd`,
  `rtl/vdp_common.vhd`, `rtl/FX68K/*`, `rtl/T80/*`, `rtl/jt12/*`,
  `rtl/jt89/*`, `rtl/gen_io.sv`, `rtl/multitap.sv`, `rtl/bram.vhd`,
  `rtl/sdram.sv`, `Genesis.sdc`, `rtl/FX68K/fx68k.sdc`.
- `Genesis_MiSTer_Savestates` @ 3cd5380 — read for section 12 only.
- Game Bub framework at this worktree: `HandheldTop.scala`,
  `BurstSdramController`, `PipelineMemoryArbiter`, `AudioRateAdapter`,
  firmware `core/info.rs` and `core/mod.rs` at tag `rev2-local8`.
- The three finished ports: `core-ngpc` (closest in shape), `core-nes`,
  `core-pce`.

## 0. Go / no-go

GO. Three properties of this core make it a better fit than it looks:

1. **The machine is one synchronous design on one clock with clock enables.**
   `system.sv` runs everything on `MCLK` = 53.693175 MHz and derives
   `M68K_CLKENp/n` (/7), `Z80_CLKENp/n` (/15), `PSG_CLKEN` (/15) and
   `FM_CLKEN` (/7) from it. There is no gated clock to build, exactly as on
   the NGPC and unlike the NES.
2. **The cartridge bus already has a full request / acknowledge handshake.**
   `MBUS_ROM_READ` sits on `if (ROM_REQ == ROM_ACK)` and only then moves to
   `MBUS_FINISH`, which is where `M68K_MBUS_DTACK_N` is asserted. A slow
   answer inserts 68000 wait states; it can never return wrong data and never
   needs a stall mechanism. This is the same argument as the NGPC's, with a
   tighter budget (section 4).
3. **Every machine memory is small enough for block RAM**: 64 KiB work RAM,
   64 KiB VRAM, 8 KiB Z80 RAM, 64 KiB cartridge save RAM, and the VDP's own
   line and sprite buffers. The 512 KiB asynchronous SRAM is not needed and
   stays free (it is the first fallback if BRAM runs short, section 3).

Two real risks, both measured in milestone 1 and build 1:

- **Timing at 53.693 MHz** with FX68K + the VDP + JT12 on an Artix-7 -1.
  MiSTer closes this on a Cyclone V. *Measured (build 1): it closes here with
  no timing exception at all, WNS +2.473 ns over the machine clock's 26,640
  endpoints, and upstream's own FX68K exceptions turn out to be unnecessary
  (section 1).*
- **Block RAM.** The estimate lands at the edge of the device (section 3).
  *Measured (build 1): 82 of 135 tiles, 61 %. The by-hand count was too
  pessimistic — Vivado packs the small memories much better — and none of the
  fallbacks is needed.*

## 1. Clocks

Mega Drive master clock (NTSC) = 53.693175 MHz = 15 x the NTSC colour
subcarrier. Against the board's 50 MHz oscillator that is exactly

    53.693175 / 50 = 189 / 176   (to 0.13 ppm: 50 x 189/176 = 53.6931818 MHz)

and 189/176 = (21/11) x (9/16) splits cleanly across the framework's
MMCM + PLL pair with integer dividers only:

    MMCM  D=1  (PFD 50 MHz)     x21   -> VCO 1050 MHz
          CLKOUT0 /11 = 95.4545 MHz   -> PLL input
          CLKOUT1 /64 = 16.406 MHz    -> display (ILI9488 range 12-17 MHz)
    PLL   D=1  (PFD 95.4545 MHz)  x9  -> VCO 859.0909 MHz
          CLKOUT0 /16 = 53.6932 MHz   -> system: machine, glue, SDRAM controller (1x)
          CLKOUT1 /16 @ 230.625 deg (11.93 ns) -> SDRAM chip clock pin
          CLKOUT2 /5  = 171.8 MHz     -> host SPI (> 160 MHz)

All four numbers are inside the Artix-7 -1 limits (MMCM VCO 600-1200, PLL VCO
800-1600, PFD 10-450 / 19-450). The display divider is computed the same way
as in the other cores, from the MMCM VCO and the frame period.

**SDRAM pin phase.** The system period is 18.624 ns, shorter than the PCE's
23.28 ns and the NGPC's 20.35 ns, so the PCE's 14 ns pin phase leaves only
3.6 ns of output hold. 11.93 ns (230.625 degrees, the nearest step of
360/(8 x 16) = 2.8125 degrees) balances the four checks against a PC133-class
chip (setup 2.0 / hold 1.0 in, clock-to-data 6.0 / hold 2.5 out):

| Check | Budget |
| --- | --- |
| Output setup (launch 0 -> pin edge 11.93, minus 2.0) | 9.9 ns |
| Output hold (next launch 18.62 - pin edge 11.93 - 1.0) | 5.7 ns |
| Input setup (falling capture 27.94 - (11.93 + 6.0)) | 10.0 ns |
| Input hold ((11.93 + 18.62 + 2.5) - 27.94) | 5.1 ns |

`core_md.xdc` is `core_pce.xdc` with this phase; the routed report is checked
after every build, as the other cores do.

**Frame period.** One NTSC frame is 262 lines x 3420 master clocks
(`vdp.vhd`'s `HV_PIXDIV` makes both H32 — 342 x 10 — and H40 —
28x10 + 4x9 + 388x8 — come to 3420) = **896,040 clocks = 16.6882 ms =
59.922 Hz**. PAL is 313 lines = 1,070,460 clocks = 50.15 Hz; the framework's
frame pacing is a compile-time constant, so it is set for NTSC and PAL is
documented as "pacing is 60 Hz" (section 8).

**FX68K multicycle paths: carried over, measured, and kept.**
`rtl/FX68K/fx68k.sdc` declares four families — `Ir` → `microAddr`,
`Ir` → `nanoAddr`, `nanoLatch` → `alu/pswCcr` and `alu/oper` →
`alu/pswCcr`, each a Quartus `-start -setup 2` / `-start -hold 1` pair. They
are correct: the 68000 runs on MCLK/7, so both ends of all four change only on
a phase enable and the real requirement is seven periods, not one. Build 2
carried them over as Vivado's canonical `2 -setup` / `1 -hold`, and a probe of
its routed checkpoint showed that the paths they relax are nowhere near
critical: against the **one**-period requirement of 18.624 ns the four data
paths measure 9.748, 11.235, 10.022 and 10.101 ns, and the worst path through
the whole of FX68K is 5.989 ns against a 9.312 ns half-period requirement (the
phase enables are generated on the negative edge of MCLK, so parts of the CPU
are half-cycle paths).

They are kept anyway, because the A/B on the routed result is clear: with them
the machine clock closes at WNS +2.473 ns, without them at +0.555 ns. The
critical path in both cases is elsewhere (jt12's clock enable, section 7), so
what the exceptions buy is the router's effort budget rather than these paths
themselves -- but four times the margin on a constraint that is correct and
upstream's own is worth having. Build 1 ran with none of them, by accident: an
`if` in an XDC file is silently rejected (Designutils 20-1307), and an XDC file
does not accept `puts` either, so the collections have to be used directly.

Upstream's fifth exception (`sdram|dout*` → `system|data*`) does not apply
either: our ROM data comes from the store's own registers through the
`ROM_REQ`/`ROM_ACK` handshake, not from a raw SDRAM output.

## 2. Vendored RTL (`fpga/verilog/md/`)

Kept (MiSTer paths under `rtl/`): `system.sv`, `vdp.vhd`, `vdp_common.vhd`,
`FX68K/{fx68k,fx68kAlu,uaddrPla}.sv` + the two `.mem` ROM images,
`T80/{T80,T80_ALU,T80_MCode,T80_Reg,T80s}.vhd`, the `jt12` subset the
YM2612 needs, `jt89/*` (PSG), `gen_io.sv`, `multitap.sv`, `fourway.v`,
`teamplayer.sv`, `audio_iir_filter.v`, `genesis_lpf.v`, `LICENSE`, and
`Genesis.sv` as a read-only `.reference`.

Not kept: the MiSTer framework (`sys/`), `sdram.sv` / `ddram.sv` / `pll*`
(the framework's controller replaces them), `bram.vhd` and `mlab.vhd` (they
instantiate `altsyncram`; replaced, below), `SVP/*`, `cheatcodes.sv`,
`EEPROM_STM95.sv`, `cofi.sv`, `lightgun.sv`, `miracle.sv`, `T80pa.vhd`
(not instantiated), the jt12 ADPCM tree (YM2610 only).

New, in `rtl/xilinx/bram.vhd` (GPL-3.0, marked `Game Bub:`): a
Vivado-inferable replacement for `rtl/bram.vhd` providing `dpram`,
`dpram_dif`, `DualPortRAM` and `obj_cache` with the same entity
names, generics and port names. Built on the SNES/PCE ports'
`tdp_ram_bank` (same-port read-during-write returns new data, as
`NEW_DATA_NO_NBE_READ` does; mixed-port collisions read the old data). The
one asymmetric shape the core uses — the
cartridge save RAM, 8-bit on port A and 16-bit on port B — is implemented
explicitly as an even-byte and an odd-byte bank so the byte order is
visible and provable: **port A byte `n` is port B word `n/2`, bits `7:0`
for even `n` and `15:8` for odd `n`**, which is `altsyncram`'s mixed-width
convention and therefore makes our `.sav` byte-for-byte a MiSTer `.sav`
(section 9).

New, in `rtl/gamebub/md_gamebub_core.sv` (GPL-3.0): a thin Game Bub top
level around `system`, bound from Chisel as the ExtModule `MdCore`. It ties
off everything in section 11, maps the Game Bub buttons onto `JOY_1`,
carries the region straps, and passes the video, audio and ROM ports
through unchanged. Everything else — the ROM store, the video capture, the
audio resampling, the host protocol — is Chisel, as in the other ports.

Planned changes to the vendored SystemVerilog, each marked `Game Bub:` in
the file and listed in `fpga/verilog/md/README.md`:

- `system.sv`: `RAM_INIT` replaces `LOADING` as the port-B clear condition of
  the work RAM, VRAM and save RAM (upstream ties the clear to the whole
  cartridge download; we need the save RAM's port B free for the host's
  `.sav` window while the core is still in setup — section 9). `LOADING`
  keeps every other role it has.
- `system.sv`: `ifndef MD_NO_CHEATS` around the `CODES` instance (it sits on
  the 68000 read path and holds block RAM tables; nothing can deliver a cheat
  file), `ifndef MD_NO_SVP` around the `SVP` instance and its DRAM mux, and
  `ifndef MD_NO_PIER` around `STM95XXX`. These three hold memories, so
  constant propagation would not remove them; everything else excluded in
  section 11 is left in the source and disappears because its enable is a
  constant 0.
- `FX68K/fx68k.sv`: the two `$readmemb` calls become assignments from a
  generated include file (`rtl/generated/fx68k_roms.svh`, written by
  `tools/gen_fx68k_roms.py` from the vendored `.mem` files), so the microcode
  and nanocode ROMs load identically in xsim and in Vivado without depending
  on either tool's search path for a relative filename.
- Any Vivado / xsim portability fixes found while building, recorded as they
  come (the NES and NGPC ports both needed declaration hoisting).

Build defines: `MD_NO_CHEATS`, `MD_NO_SVP`, `MD_NO_PIER`.

## 3. Memory map and budget

| Memory | Contents | Where | Size |
| --- | --- | --- | --- |
| Cartridge ROM | the loaded file | SDRAM 0x000000 | up to 10 MiB |
| Work RAM | 0xE00000-0xFFFFFF | BRAM (`ram68k_u/l`) | 64 KiB |
| VRAM | | BRAM (4 banks) | 64 KiB |
| Z80 RAM | 0xA00000-0xA01FFF | BRAM (`ramZ80`) | 8 KiB |
| Cartridge save RAM | 0x200000-0x20FFFF odd bytes | BRAM (`sram`), host window on port B | 64 KiB |
| CRAM, VSRAM, line and sprite buffers | | BRAM / LUT RAM inside `vdp` | ~3 KiB |
| FX68K microcode / nanocode | | BRAM ROM | 1024x17 + 336x68 |
| Framebuffers | 2 x 320 x 224 RGB565 | framework BRAM | |

**BRAM estimate (RAMB36 equivalents).** The two framebuffers dominate and
are depth-bound, not width-bound: 320 x 224 = 71,680 pixels needs
71,680 / 2048 = 35 tiles per buffer whatever the pixel format, so RGB565 is
used (it is free relative to the VDP's RGB444 and carries MiSTer's colour
curve better, section 7).

| | tiles |
| --- | --- |
| Framebuffers 2 x 35 | 70 |
| Work RAM 2 x 32Ki x 8 | 16 |
| VRAM 4 x 16Ki x 8 | 16 |
| Save RAM 64 KiB | 16 |
| Z80 RAM 8Ki x 8 | 2 |
| VDP buffers, FX68K ROMs, jt12 tables | ~8 |
| Overlay 240 x 160 x 2, SPI FIFOs, display | ~7 |
| **total** | **~135 of 135** |

**What it actually came to: 82 of 135 (61 %)** in build 1, so none of the
fallbacks below was needed. The by-hand count is too pessimistic because
Vivado packs the VDP's small buffers, the FX68K ROMs and the jt12 tables far
better than a tile-per-memory estimate assumes.

That estimate was at the edge, and it is only as good as Vivado's choices for
the small memories. Build 1 measures it. **Fallbacks, in order**, each
independent of the others:

1. Save RAM 64 KiB -> 32 KiB (`sram_addr` loses a bit): -8 tiles. Covers
   every common battery game (8 KiB or 32 KiB); a 64 KiB saver would lose
   the upper half.
2. Save RAM into the free 512 KiB asynchronous SRAM (the SNES port's
   `AsyncSramController` + `BytePortBridge` precedent): -16 tiles, at the
   cost of a wait state in `MBUS_SRAM_READ` and a second host path.
3. Pack three 12-bit pixels per 36-bit framebuffer word in `HandheldTop`:
   -22 tiles, but it touches shared framework code.

None of them is needed for Comix Zone, which has no battery save at all.

## 4. Cartridge ROM path

`system.sv` presents one port: `ROM_ADDR[24:1]` (word address), `ROM_BE`,
`ROM_WDATA`, `ROM_WE`, and a toggle handshake — a transaction is outstanding
while `ROM_REQ != ROM_ACK`, and `MBUS_ROM_READ` waits for equality before it
latches `ROM_DATA` and moves to `MBUS_FINISH`.

**MdRomStore** (Chisel) serves it from the SDRAM:

- The SDRAM holds the file as the host wrote it: 32-bit little-endian words
  at 4-aligned byte addresses (the controller maps a 32-bit access onto two
  chip words in its own order, so every access stays 4-aligned). A Mega Drive
  ROM is big-endian, so the 16-bit word at byte address `W` is
  `{sdram[7:0], sdram[15:8]}` and the one at `W+2` is
  `{sdram[23:16], sdram[31:24]}`. The byte swap is the store's, not the
  loader's: the file in SDRAM stays identical to the file on the card.
- **A four-entry fully associative cache of 4-byte windows with sequential
  prefetch.** After any fill, the store speculatively reads the next window
  while the bus is idle. The 68000 fetches two bytes at a time and mostly
  sequentially, and VDP DMA reads ROM sequentially too, so four entries let
  the two streams interleave without evicting each other, and the prefetch
  hides the SDRAM behind the 68000's 28-clock bus cycle. The cache is
  invalidated by the host window and by any `ROM_WE`.
- Writes (`ROM_WE`, reachable only through the Game no Kanzume quirk we do
  not enable) are read-modify-write of the window and update the cached copy.

**Latency budget (why no stall, and why the cache).** A 68000 read is four
CPU clocks = 28 master clocks. `M68K_AS_N` falls about one CPU clock in;
`MBUS_IDLE -> MBUS_SELECT -> MBUS_ROM_READ` costs two clocks, `MBUS_FINISH`
one, and DTACK must be low before the falling edge of S4, roughly 14 clocks
after AS. So the store has **about 11 clocks** to answer for a zero-wait-state
cycle, against the NGPC's 20. A miss under refresh can take longer than that;
the consequence is one 68000 wait state (two CPU clocks), never wrong data.
The cache and the prefetch exist to keep that from happening often: a
sequential stream costs one SDRAM access per four bytes and the access is
issued a whole bus cycle early.

Verification, exactly as the NGPC did it: the store counts transactions,
SDRAM reads, cache hits, prefetch hits, its worst answer latency and the
number of answers slower than the budget (registers 0x1000-), and the
simulation counts 68000 wait states caused by a late DTACK. If hardware ever
disagrees with simulation, those registers are readable with the firmware's
DBGREG logger.

## 5. Loading, region and quirks

`files.json`:

| id | label | file | address | size | flags |
| --- | --- | --- | --- | --- | --- |
| 0 | Cartridge | .md .bin .gen (user selected) | 0x30000000 | max 0xA00000 | required, read-only |
| 1 | Save | .sav | 0x40000000 | exact 0x10000 | optional, dependent on 0 |
| 2 | States | .ss | 0x50000000 | (section 12) | optional, dependent on 0 |

The glue captures, from the cartridge stream as it goes by, exactly what
`Genesis.sv` captures from its ioctl stream: bytes 0x180-0x18F (the cartridge
serial, for the quirk table) and 0x1F0-0x1F3 (the region characters). The
quirk table is kept for the entries that are cheap and correct —
`SRAM_QUIRK`, `SRAM00_QUIRK`, `EEPROM_QUIRK`, `NORAM_QUIRK`, `FIFO_QUIRK`,
`FMBUSY_QUIRK`, `SCHAN_QUIRK` — and dropped for `PIER_QUIRK` and `SVP_QUIRK`,
which name hardware we do not build (section 11).

Region follows `Genesis.sv`: the header's region characters give J / U / E,
and the setting picks the preference order. `PAL` and `EXPORT` are straps
sampled in reset; changing either resets the machine.

RAM initialisation follows upstream: `RAM_INIT` (section 2) runs for 65,536
clocks at the start of every setup, writing 0 into the work RAM and VRAM and
0xFF (or 0x00 under `SRAM00_QUIRK`) into the save RAM, before the `.sav`
window can write anything.

## 6. Video capture (320 x 224 and 256 x 224)

The VDP's output port with `BORDER_EN = 0` is exactly the active area:
`CE_PIX` is a one-clock enable at the pixel rate, `HBL` is low over
`H_DISP_WIDTH` pixels (320 in H40, 256 in H32) and `VBL` is low over
`V_DISP_HEIGHT_R` lines (224 in V28, 240 in V30). `RESOLUTION` = `{V30, H40}`.

The framework's framebuffer is a compile-time 320 x 224, so the capture:

- writes a pixel on each `CE_PIX` where `HBL` and `VBL` are both low;
- **centres H32**: a 256-pixel line is written at columns 32-287 and the 32
  columns on each side are written black, so a game that switches modes (many
  do, between menus and play) keeps a stable, centred picture instead of a
  stretched one;
- **centres V30**: the middle 224 of the 240 lines are kept. NTSC V30 has no
  vertical blanking at all on real hardware and is not a mode games ship in;
  PAL V30 games lose 8 lines top and bottom. Documented, not fixed.

Colour: `vdp.vhd` gives 4 bits per channel (the 3-bit CRAM value plus the
shadow / highlight dimension). `Genesis.sv`'s `color_lut` maps those 16 levels
onto the Mega Drive's real, non-linear DAC levels (0, 27, 49, 71, 87, 103,
119, 130, 146, 157, 174, 190, 206, 228, 255, 255); the glue applies the same
table and stores RGB565. Frame period as section 1. LCD scaling register
0xF1001018: the default here is **4:3**, not the other cores' 1x — a Mega
Drive's 320 x 224 was meant to fill a 4:3 frame, which on the 480 x 320 panel
is 427 x 320. Fit (square pixels, 457 x 320), Stretch and 1x are offered too.

MiSTer's composite blending (`cofi`), scanlines, hq2x and `ascal` are not
built (section 11).

## 7. Audio

`DAC_LDATA` / `DAC_RDATA` are signed 16-bit, updated on `MCLK`, and already
carry MiSTer's whole chain: the YM2612's `jt12` output scaled by 22.25/16 to
match the PSG, `genesis_fm_lpf`, `jt12_genmix`, and `genesis_lpf` (the LPF
Mode setting: none / model 1 / model 2). The Mega Drive's own low-pass is
part of how it sounds, so all of it is kept.

53,693,175 is not a multiple of 48,000, so the NGPC's exact CIC ratio is not
available. The glue does what the NES does instead: sample on a /8 enable
(6.71 MHz, well above the YM2612's own 53 kHz output rate), decimate with a
3-stage CIC of ratio 128 to 52,434 Hz, and feed `AudioRateAdapter`
(`nominalPeriod = 1024` system clocks), whose phase accumulator and FIFO
servo hand the framework a smooth 48 kHz stream. Muted without focus.

Settings: LPF Mode (default "Model 1", MiSTer's default), FM enable and PSG
enable (debug), and a Mono / Stereo mix for headphones.

**The YM2612 turned out to hold the design's critical path**, which was worth
finding. `jt12_div` registers `clk_en` � the chip's main clock enable � on the
*negative* edge of the clock, deliberately: its comment says "It's important to
leave the negedge to use the physical clock enable input", which on an Altera
part means the enable reaches the LAB's dedicated clock-enable input. On a
7-series part it means the enable is a **half-cycle** path, 9.312 ns here, and
it drives the CE pin of several thousand flip-flops; 7.9 of those 9.3 ns went
into routing one unreplicated net and left the machine clock at WNS +0.555 ns.
`(* max_fanout = 100 *)` on the driver brings the path to 6.893 ns and the
clock to +1.784 ns. Nothing about the chip's behaviour changes � replication is
the standard answer to a high-fanout enable � and Quartus ignores an attribute
it does not recognise.

## 8. Joypad, region and settings

`multitap` + `gen_io` give the real I/O chip and a 3- or 6-button pad
(`J3BUT`). The Game Bub has nine buttons and the 6-button pad needs eight, so
the 6-button pad is nearly free and is built:

| Game Bub | 3-button | 6-button |
| --- | --- | --- |
| d-pad | Up/Down/Left/Right | same |
| B | A | A |
| A | B | B |
| X (or R) | C | C |
| Y | - | X |
| L | - | Y |
| R | - | Z |
| Start | Start | Start |
| Select | - | Mode |

Default is the **6-button pad**, because Comix Zone uses C to attack and the
6-button pad is what a modern player expects; a "Pad" setting switches to
3-button for the handful of games that misread a 6-button pad. A "Buttons"
setting swaps the A/B/C row onto B/A/X for players who prefer the Mega Drive's
physical layout. Home stays the firmware's.

Settings (`settings.json`): Reset, Scaling (default 4:3), Region
(Auto / Japan / USA / Europe), Video (Auto / 60 Hz / 50 Hz), Pad
(6-button / 3-button), Buttons, LPF Mode, Mono, Sprite Limit,
Border, and — only if section 12 says so — Save State / Load State /
State Slot.

## 9. Battery saves

The cartridge save RAM is `system.sv`'s `sram`, with port B wired to the host
window as MiSTer wires it to the SD-card buffer. Because our `dpram_dif`
reproduces `altsyncram`'s mixed-width byte order (section 2), the file is the
save RAM's byte array in address order — **byte-for-byte a MiSTer `.sav`**.

- Size: 64 KiB, always, as MiSTer writes it (`sd_lba[6:0]`).
- Load: the host writes the file through port B during setup, after
  `RAM_INIT` has finished (section 5). No validation: a Mega Drive save has
  no header to check, and the firmware only ever offers the `.sav` that sits
  next to the ROM.
- Save on exit (`FILE_READ_START 1`): the size answered is 0x10000 if the
  game wrote the save RAM this session (`BRAM_CHANGE`) or a `.sav` was
  loaded, and 0 otherwise, so a game without a battery never leaves a file.
- `NORAM_QUIRK` (Puggsy) disables the save RAM entirely, as upstream does.

None of the four test ROMs has a battery. Sonic the Hedgehog 3 and
Phantasy Star IV are the usual test cases; the tester would have to supply
one. The path is verified in simulation instead, by writing the save RAM
from the host, reading it back and comparing (`docs/md-port-status.md`).

## 10. Reset, focus pause, host protocol

- Machine reset = FPGA reset, or the core in setup (`coldReset`, until
  `SETUP_COMPLETE`), or halted (`CoreHalt`), or the Reset action, or a region
  strap change. `LOADING` is asserted through setup, which is upstream's own
  cartridge-download reset.
- Focus pause: `NotifyFocus 0` raises `PAUSE_EN`, which `system.sv` already
  uses to withhold every clock enable (`M68K_CLKENp/n`, `Z80_CLKENp/n`,
  `PSG_CLKEN`, `FM_CLKEN`) while leaving the dividers running. The VDP keeps
  its raster running, so the framework keeps getting frames; audio is muted.
  This is upstream's own debug pause, which is what MiSTer's own save states
  park the machine with.
- Commands as in the NGPC glue: `FILE_WRITE_START 0` enters setup and starts
  `RAM_INIT`; `FILE_WRITE_END 0` latches the size, the header registers and
  the quirks; `SETUP_COMPLETE` fails without a cartridge; `GET_STATUS`
  reports setup while `RAM_INIT` is running; `FILE_READ_START 1` answers the
  `.sav` size.

## 11. What is deliberately left out

Each of these is a decision, not a gap:

| Left out | Why |
| --- | --- |
| **SVP** (Virtua Racing) | a second 736-line DSP with its own memories, for one game |
| **Sega CD, 32X** | not in this core at all |
| **Pier Solar** hardware (`PIER_QUIRK`, `EEPROM_STM95`) | one homebrew game, an SPI EEPROM and a bank mapper |
| **Multitap, 4-way, Team Player, J-Cart** | one player on a handheld. Left in the source with a constant 0 enable; constant propagation removes them |
| **Mouse, light gun, Miracle Piano** | no input for them |
| **Serial joystick** (`SERJOYSTICK_*`) | MiSTer's second-board link |
| **SMS compatibility mode** | not in this core |
| **Cheats / Game Genie** | nothing can deliver a code file; the engine holds BRAM and sits on the CPU read path |
| **Composite blending (`cofi`), scanlines, hq2x, `ascal`, gamma** | the framework owns scaling, and the panel is 480x320 |
| **Turbo, debug layer toggles** | kept as registers but not exposed as settings, except Sprite Limit |

## 12. Save states (r2.10 to r2.19)

The engine is keFEAR89's `Genesis_MiSTer_Savestates` R58 (@ 3cd5380,
GPL-3.0), a fork of the same archived core, assessed in
`docs/md-savestates-assessment.md` and studied in simulation in
`build/STUDY-md-savestates-kefear89-2026-09-27.md`. Unlike MiSTer's generic
`savestates.sv`, the machine takes its own snapshot.

**What the engine does.** A save waits for a quiet point (VBlank, the 68000
bus idle, no DMA, the VDP FIFO empty, the renderer idle, the Z80 at an opcode
fetch), forces a level-7 interrupt, answers the interrupt acknowledge itself
and feeds the 68000 a handler at 0xA14000 that stores D0-D7, A0-A7, SR and
PC into a scratch area at 0xA14100; the SSP is caught from the bus, and the
68000 is held in reset. The Z80 is paused and read through the T80's register
port (widened by the fork to 230 bits). In a fresh blank the VDP's 64 KiB
VRAM, CRAM, VSRAM and its sprite cache are copied at a byte a clock into a
shadow (`ss_vram_shadow`, `ss_vdp_local_shadow` in `system.sv`), and a
64-byte bank of VDP registers is latched; each is read twice and CRC-checked.
Work RAM, Z80 RAM, the shadows, the bank, the 68000 scratch, the Z80
registers, the I/O chip, the mapper and the shadows of every YM2612 and PSG
register write make the 141,312-byte state, which `ss_slot_engine.sv` streams
out through its slot memory channel and reads back against its CRC. Resuming,
after a save as after a load, resets the 68000 into a second handler at
0xA14008 that reloads the registers and `RTE`s; the sound chips are reset and
their shadowed registers written back, so a held FM note restarts and a
sample in progress is lost. The fork's README marks it beta: a game with a
tight stack or its own use of level 7 can be disturbed by the capture.

**What is ours.** `rtl/savestate/` and the fork's changes to `system.sv`,
`vdp.vhd`, the T80 and `gen_io.sv` are merged as they are
(`fpga/verilog/md/README.md` lists the merge); `md_gamebub_core.sv` carries
the fork's `Genesis.sv` glue without its OSD tests; the rest is in the Chisel
glue (`MdSaveState.scala`, `HandheldMd.scala`):

- **Slots.** The engine addresses its four slots as 64-bit words from
  MiSTer's 0x3E000000 (slot n at word 0x20000 + n x 0x8000, a 256 KiB
  stride). `MdSaveStatePort` puts that channel (a toggle handshake) on the
  SDRAM at 0x1000000 + (word - 0x20000) x 8, each 64-bit word as two 32-bit
  little-endian accesses, so the 1 MiB area is byte for byte what a MiSTer
  holds and writes to the `.ss` file. The firmware's States file (id 2, host
  window 0x5xxx_xxxx, `initialize`d to 0xFF when there is none) is that area;
  `FileReadStart` reports the slots up to the last one holding a state.
- **Which slots hold a state.** `MdSaveSlotScanner` reads each slot's size
  word (bytes 4..7 == 35,336 body words) and magic (bytes 12..15 == "R58S")
  after the file is loaded and after every save, and clears the size word of
  slots beyond the loaded file. A load of an empty slot is refused in the glue
  ("No state in slot"); behind that come the engine's own checks: the
  cartridge identity (the file size and the header words 0x180-0x18F latched
  from the host stream), the straps (PAL, export), the header and the CRCs.
- **SDRAM priority.** The scanner and the slot channel share a
  `PipelineMemoryLowPriorityMux` side port behind the ROM store. The transfers
  happen while the engine holds the CPUs, except a load's first pass: before
  a load freezes the machine, the engine reads the whole slot once to check
  its CRC (141 KB, about 2 ms), which delays a few hundred cartridge fetches
  by a few clocks. r2.17 tried to hide that by holding the machine paused for
  that pass; on the handheld its first load failed at the hold, as r2.16 did
  in the same scene (finding D), so it was withdrawn as unproven and the late
  fetches stay: each is one fetch a few clocks late. The engine's periodic
  probe of the slot header (two reads every 2^20 clocks, for MiSTer's OSD)
  cost a few ROM fetches a second the same way, so r2.16 instantiates the
  engine with `PROBE = 0`: the scanner is the only reader of the headers
  outside a request.
- **Commands.** Registers 0x14 and 0x18 and status bits 6-15 of 0x100 as in
  the NES and PCE ports (section "Registers" in `HandheldMd`). The engine
  edge-detects its command and misses an edge that lands while it drains a
  probe, so the glue re-edges an unanswered request every 1024 clocks until
  the engine goes busy or refuses; a request is given up after 3 s (the
  engine's own watchdog is 2.5 s). While a request runs the focus pause is
  lifted (`ssRunPending`): the 68000 has to enter the handler and the VDP
  reach a blank, so the game runs unfocused for a few frames with the menu
  open (a save took 4 frames in simulation).
- **Errors.** The engine's error code is in status bits 31:24 (1 blocked,
  2 unsupported cartridge, 3 no state, 4 bad header, 5 capture failed, 6 slot
  CRC, 7 restore failed, 0x0A timeout, 0x0B imported data CRC, 0x1A another
  cartridge, 0x1B other straps).
- **Resources.** The fork's three shadows are LUT RAM (`ram_style =
  "distributed"`): the build has 1.5 block RAM tiles free.

**Packages.** r2.10 has all of this built in and no menu entry (a regression
test of the merged machine); r2.11 adds the three `settings.json` entries:

```json
{ "id": 13, "label": "Save State", "hotkey": "save_state", "address": "0x14", "type": "action", "value": "0x11",
  "status": { "address": "0x0100", "busy_mask": "0x680", "done_mask": "0x100", "fail_mask": "0x8000",
              "timeout_ms": 6000, "done_text": "State saved", "fail_text": "Save failed" },
  "visible_if": { "address": "0x0100", "mask": "0x40" } },
{ "id": 14, "label": "Load State", "hotkey": "load_state", "address": "0x14", "type": "action", "value": "0x12",
  "status": { "address": "0x0100", "busy_mask": "0x680", "start_mask": "0x80", "fail_mask": "0x8000",
              "timeout_ms": 6000, "done_text": "State loaded", "fail_text": "Load failed", "refused_text": "No state in slot" },
  "visible_if": { "address": "0x0100", "mask": "0x40" } },
{ "id": 15, "label": "State Slot", "address": "0x18", "mask": "0xFFFFFFFC", "default": 0, "type": "list",
  "items": [ { "label": "1", "value": 0 }, { "label": "2", "value": 1 }, { "label": "3", "value": 2 }, { "label": "4", "value": 3 } ],
  "visible_if": { "address": "0x0100", "mask": "0x40" } }
```

**Diagnostics** (r2.12 to r2.18). Register 0x0020 is a live word: bits 31:26
the orchestrator's state, 23:20 its capture error, 19:16 the handler's state,
15:0 the safe point and its terms (VBlank, MBUS idle, AS high, no Z80 access
to the 68000 bus, VDP memory idle, renderer idle, no hold, Z80 M1, Z80 MREQ,
Z80 ISET 0, Z80 out of reset, Z80 not bus-requested, IRQ7, CPU held, INTACK,
safe point). 0x0024 holds that word from the end of the last request, or,
when the 68000 handler timed out, from its last waiting clock (r2.16). 0x0028
counts the clocks in which every bit of the mask in 0x002C is 1 in the live
word. 0x0030 / 0x0034 (r2.18) show the nine terms of the VDP's `SS_MEM_IDLE`
one by one, 1 = busy: FIFO not empty, DMA in progress, the data-transfer and
DMA controllers busy, a VRAM data access in flight, the VDP on the 68000 bus,
a CRAM / VSRAM0 / VSRAM1 write.

**Findings on the handheld (2026-09-27).** r2.11 saved 1.5 s and 8 s after a
Reset and failed 66 s into Comix Zone's intro after 1,277 ms, the 68000
capture handler's 1.25 s timeout (`ss_m68k_handler_test.sv`, `TIMEOUT_MAX`);
after one failure every later request failed at once until a Reset.

- **(B) A stale failure wedged the engine** (r2.13). The orchestrator samples
  the handler's `fail` on the clock after it raises `start`, one clock before
  the handler accepts the request and clears the flag, so the previous
  attempt's `fail` counted against the new one. The handler now clears `pass`
  and `fail` whenever `start` is low (`ST_IDLE` and `ST_DONE`).
- **(C) A failed save wiped the slot** (r2.13). The slot engine zeroed the
  slot's size word before the capture. The size word is now written with the
  rest of the header, after the data.
- **(A) The capture point** (r2.15). Measured in the intro, per second of
  clocks: VBlank 14.5 %; VBlank with the 68000 quiet 14.49 %; VBlank with the
  renderer idle 13.3 %; VBlank with the VDP's memory idle 0.000 %. r2.15 keeps
  the fork's strict point first and, after 2^22 clocks (78 ms) without it,
  also takes the same point outside the blank (`ss_m68k_safe_start` in
  `system.sv`). The VDP scan still waits for a fresh blank after the 68000 is
  held, so a load can show one partial frame. The 0.000 % reading was most
  likely finding D's parity rather than a DMA through every blank; to be
  re-measured with r2.19 (mask 0x0011 in 0x002C).
- **(D) The "VDP memory idle" term read a toggle's parity** (r2.18, r2.19).
  Mid-stage in Comix Zone (stage 1, running or paused by Start) most saves and
  loads failed after the hold: the 68000 parked at 0xA14102, the orchestrator
  waiting for `SS_MEM_IDLE` until its 2.5 s watchdog (also seen in Gunstar
  Heroes). Register 0x0030 showed one busy term through every failing save:
  `DT_VRAM_SEL`, busy also in the intro with the game running. In `vdp.vhd`
  that signal is a toggle request (`vram_req <= DT_VRAM_SEL`; the access is
  done when `vram_ack = DT_VRAM_SEL`, one clock later with the VRAM in block
  RAM), so its level is the parity of the data-port accesses so far. The
  fork's condition `DT_VRAM_SEL = '0'` read "idle" only after an even number
  of transfers; after an odd number no capture point came (the 1.25 s
  timeout), or a transfer between the point and the hold flipped it and the
  held machine could never flip it back (the 2.5 s watchdog). r2.19 makes the
  term `DT_VRAM_SEL = vram_ack` and bit 4 of 0x0030 report the same. On the
  handheld, Comix Zone stage 1: paused, 3 of 3 saves; running, 3 of 3 saves
  and a load; 183 ms each (before: 1 of 8 in that scene).

Open: after a failed hold the release restarted the game (r2.16 and r2.18,
three times, the SEGA logo). Failures are rare since r2.19; the release path
(the handler's RESET_HOLD / RESET_BOOT, the orchestrator's abort) is next.

## 13. Verification plan

1. `xvlog` / `xvhdl` / `xelab` of the vendored set plus `md_gamebub_core`
   (mixed VHDL and SystemVerilog), then `synth_design -rtl` for elaboration
   warnings and memory inference.
2. Core-only xsim (`sim/tb_core.sv`): the machine with a behavioural ROM store
   of configurable latency, frames dumped as PNG into
   `build/md/sim-frames`. Checks: the Sega screen, the Comix Zone title
   screen, gameplay after Start, and zero wrong-data events at the store's
   worst latency.
3. Whole-system xsim (`sim/system/tb_system.sv`): the generated `HandheldMd`,
   the real `BurstSdramController` with `sdram_model.sv`, and the host
   protocol driven exactly as the firmware drives it, including the `.sav`
   round trip.
4. Vivado build for `gamebub_rev2`: timing met (WNS/WHS >= 0), UserID
   B0100002, utilisation recorded; then the package.
