# Mega Drive / Genesis port status (resume here)

Worktree `gamebub-rev2/core-md`, branch `md` (from `ngpc` @ a922d66b).
Design: `docs/md-port-design.md`. Upstream: `Genesis_MiSTer` @ adc0c42, clone
in the session scratchpad `refs/Genesis_MiSTer`; save-state fork
`refs/Genesis_MiSTer_Savestates` @ 3cd5380 (read for the assessment only).
Test ROMs in `refs/md-test-roms/`.

**The goal is Comix Zone (USA).**

## Done

- Design (`docs/md-port-design.md`).
- Vendored RTL subset `fpga/verilog/md/` (pristine commit `01102f46`, then the
  Game Bub changes; README with the modification table). `rtl/xilinx/bram.vhd`
  replaces the `altsyncram` memories, with the asymmetric 8/16 cartridge save
  RAM built from an even and an odd byte bank so the `.sav` byte order is
  provable; the FX68K microcode ROMs come in through a generated include.
- Game Bub top level `rtl/gamebub/md_gamebub_core.sv`; `MD_NO_CHEATS`,
  `MD_NO_SVP`, `MD_NO_PIER`; the save RAM halved to 64 KiB now that the SVP's
  DRAM is gone.
- Chisel glue `fpga/src/main/scala/net/gamebub/core/md/`: `HandheldMd`,
  `MdCore`, `MdRomStore`, `MdVideoCapture`, `MdSaveRamWindow`. The clock tree
  comes out as designed (MMCM x21 /11, PLL x9 /16 = 53.693182 MHz, SDRAM pin
  230.625 degrees, display 12.07 MHz, SPI 171.8 MHz).
- `build_core.py` entry and defines, `verilog/handheld/core_md.xdc`,
  `cores/md/{core,files,settings}.json`.
- Tools in `C:\Users\jen\tools\gamebub-build`: `mill-md.cmd`,
  `run_build_core_md.py`, `fpga-build-md-rev2.ps1`, `package-md.ps1`.
- Simulation: `sim/tb_core.sv` + `run_core.sh` (the machine with a
  behavioural ROM store), `sim/system/tb_system.sv` + `run_system.sh` (the
  whole core as the firmware drives it), `sim/tb_bsram.sv` and
  `sim/tb_video.sv` (unit tests that run in seconds), `make_hex.py`,
  `frames_to_png.py`.
- `docs/md-savestates-assessment.md`: **do not adopt, do not adapt**, with the
  reasons. Registers 0x0014 and 0x0018 are left free anyway.

## Bugs found and fixed

- **Nothing ran in xsim** (`d6b9f87d`). xsim gives a variable declared inside
  an `always` block automatic lifetime: with an initializer it is
  re-initialized on every execution, without one it is X on every execution.
  Quartus and Vivado synthesis both give it static lifetime, so the hardware
  was never affected -- but in simulation `system.sv`'s clock-enable divider
  kept reading `VCLKCNT == VCLKMAX == 0`, so `M68K_CLKENp` and `M68K_CLKENn`
  were both high on every negedge; in `fx68k.sv` the `else if (enPhi2)` branch
  then always won over `else if (enPhi1)`, so `BeI` was never loaded from
  `rBerr`, `wClk` stayed high and `tState` oscillated T0-T4 forever. The 68000
  never drove its address bus. Fixed with the `static` keyword on the 30
  declarations in `system.sv`, `gen_io.sv` and `teamplayer.sv` (naming the
  block is **not** enough -- verified both ways in a minimal testbench).
- **The real critical path is jt12's clock enable, not the 68000**
  (`56087cff`). `jt12_div` registers `clk_en` on the *negative* edge on
  purpose ("It's important to leave the negedge to use the physical clock
  enable input" -- an Altera LAB feature), so on a 7-series part the YM2612's
  main clock enable is a **half-cycle** path (9.312 ns here) driving the CE pin
  of several thousand flip-flops, and 7.9 of those 9.3 ns went into routing one
  unreplicated net. `(* max_fanout = 100 *)` on the driver brings the path to
  6.893 ns and the machine clock from WNS +0.555 to +1.784 ns.
- **`T80.vhd` would not synthesise**: `ioq := (ioq and x"7") xor ('0'&BusA)`
  is 9 bits against a 4-bit hex literal. Quartus extends it silently, Vivado
  refuses (Synth 8-509). Masked with `"000000111"`.
- **`T80.vhd` / `T80s.vhd` would not compile**: `x : work.E` without `entity`
  is a Quartus extension.
- **`jt12_top.v`, `fourway.v`, `system.sv`**: SystemVerilog constructs Quartus
  accepts in a Verilog file and Vivado does not (single-value unpacked ranges,
  a declaration in an unnamed block, `always_comb` driving a net), plus two
  port widths that were only defined by accident across the VHDL boundary.
- **An `if` in an XDC file is silently rejected** (Designutils 20-1307), so
  build 1's FX68K timing exceptions were never applied -- which is how we
  learned what the design does without them.
- **The vdp.vhd debug writers** (`vdp.out` is one line per pixel, about 1 MB of
  text per emulated frame) dominated the run time of a whole-machine
  simulation; they are inside `synthesis translate_off` and are commented out.
- The `fpga/verilog/hdmi` submodule was not checked out in this worktree; its
  files are copied from `core-ngpc`'s (same commit 380c974).

## Build results

Vivado 2023.2, xc7a100tcsg324-1, target `gamebub_rev2`, system clock
53.693182 MHz (period 18.624 ns). `clk_sys` is the machine's own clock domain;
the design's overall WNS is on `handheld_top_n_2`, the 171.8 MHz host SPI
domain, which belongs to the framework.

| # | Commit | Result | LUT | FF | BRAM | DSP |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | aa932150 + T80 fix | routed, all met. Overall WNS +0.320 / WHS +0.034. The XDC's `if` guards meant **no timing exception was applied at all** | 15,031 (23.7 %) | 10,347 | 82 / 135 (60.7 %) | 24 |
| 2 | (same, XDC fixed) | routed, all met. Overall WNS +0.292, **clk_sys +2.473** with the four FX68K families applied | 15,030 | 10,346 | 82 | 24 |
| 3 | 622fe216 | routed, all met. Overall WNS +0.387, **clk_sys +0.555** with the families removed. Critical path found: jt12's `clk_en` | 15,029 | 10,346 | 82 | 24 |
| 4 | (56087cff working tree) | routed, all met. Overall WNS +0.415, **clk_sys +1.784** with `max_fanout` and the families back | 15,030 | 10,346 | 82 | 24 |

The block RAM budget the design worried about is not a problem: 82 of 135
tiles, so none of section 3's fallbacks is needed. SDRAM pins measured
+3.68 / +5.43 ns out and +3.16 / +6.17 ns in, so the 11.93 ns pin phase is
right.

## Simulation results

**Core-only** (`tb_core`, behavioural ROM store on the toggle handshake, flat
latency 8 clocks and no cache -- pessimistic against the real
`MdRomStore`), Comix Zone (USA), 2 MiB:

- Fetches its reset vector (SSP 0x00000000, PC 0x001E3B1A), jumps there and
  runs its work RAM clear; back in code by frame 2.
- H40 from the first frame (`RESOLUTION` = 01), 320 x 224 pixels and 224 rows
  captured per frame, frames exactly 16.688 ms apart (59.92 Hz).
- By frame 14 the Z80 is out of reset, with 302 VDP writes, 8,270 Z80-bus
  accesses, 60 YM2612 and 24 PSG register writes: the whole machine is
  running, and the black frames before that are the game booting.
- First non-black frame at **38** (0.63 s); the backdrop, then a wipe-in
  animation from frame ~54; **the SEGA logo is fully drawn at frame 80**
  (1.33 s) -- 320 wide, correct shapes, outline and shading.
  `build/md/sim-frames/cz_frame_0080.png`.
- About 14,300 cartridge reads per frame.

- **The focus pause is exact.** Held for 896,040 clocks (one whole frame
  period) from frame 5, the machine did **0 cartridge reads and 0 VDP writes** --
  the 68000, the Z80 and the sound chips are completely stopped -- while the
  display kept refreshing at 59.92 Hz with a frozen picture (frames 4, 5 and 6
  exactly 16.688 ms apart). That is the designed behaviour: `PAUSE_EN` is
  upstream's own debug pause and deliberately does not stop the VDP's raster,
  so the framework keeps getting frames and the Home menu has something to show.

A note on what the core simulations did **not** reach, so nobody assumes they
did: Comix Zone was run to frame ~110 (1.8 s of emulated time) and stops at the
SEGA logo -- xsim runs this design at roughly 20,000 clocks a second, so a
frame costs about 40 seconds of wall clock and the title screen is an hour
away. The other three test ROMs were started and read plausible reset vectors
(Sonic 2 SSP 0xFFFFFE00 / PC 0x00000206, Streets of Rage 2 0x00000000 /
0x00000208, Altered Beast 0x00FFFE00 / 0x0000A5D4). Sonic 2 was taken furthest
-- 50 frames (0.83 s), about 22,000 cartridge reads a frame, the VDP running at
59.92 Hz in H40 and the 68000 in its own code -- but its picture had not
started yet, so none of the three has been seen to draw. **No music has played in any simulation**, so nothing has been
through the audio resampler -- the chain is wired and the chips answer the
CPU, but sound is the least-verified part of this port and the first thing to
listen to on hardware.

**Unit tests** (seconds each, run on their own):

- `sim/tb_bsram.sv` -- the cartridge save RAM's byte order, written through one
  port and read back through the other, both ways, at both ends of the 64 KiB
  and across the even/odd bank boundary. **PASS**: port A byte `n` is port B
  word `n/2`, bits 7:0 for even `n` and 15:8 for odd `n`, which is what makes
  our `.sav` a MiSTer `.sav`.
- `sim/tb_video.sv` -- `MdVideoCapture` against a synthetic raster shaped like
  `vdp.vhd`'s output port, including the V counter advancing 15 pixels before
  the end of the active area, checked pixel by pixel against the framebuffer
  the framework's address rule would build. **PASS** for H40 (320 x 224 over
  224 rows) and for H32 (256 pixels at columns 32-287 with black borders).
  None of the four test ROMs ever leaves H40, so without this the H32 delay
  line and its border would have shipped untested.

**Whole-system** (`tb_system`: the generated `HandheldMd`, the real
`BurstSdramController` with the cycle-level chip model, and the host protocol
driven exactly as the firmware drives it), Comix Zone (USA):

- The 2 MiB cartridge loads through the file window (`FILE_WRITE_START 0`,
  524,288 host words, `FILE_WRITE_END 0`); the header registers read back
  serial **"MK-1569 "** with the region detected as **USA** and **no quirks**,
  which is Comix Zone's product code and region byte.
- `FILE_WRITE_END 1` with a 64 KiB `.sav` sets status bit 6; `SETUP_COMPLETE`
  and `GET_STATUS` answer as the firmware expects (3 = CoreRun); `CoreRun` and
  `NotifyFocus 1` start the machine.
- **The cartridge path against a real SDRAM is comfortable.** Over the whole
  45-frame run (statistics registers 0x1000-0x1020 read back at exit):
  789,950 store transactions, 693,705 window-cache hits (88 %), 436,076 SDRAM
  reads of which 339,831 were prefetches (78 %), **no SDRAM writes at all**,
  **worst answer 11 clocks** -- exactly the 68000's budget -- and **zero
  answers slower than the budget**. Early on, while the game sits in a tight
  loop, the hit rate is 99.8 % and the worst answer is 8 clocks. 1,431,573
  DTACK wait edges over 2,548,468 bus ends.
- **The `.sav` round trip is byte-perfect.** A 64 KiB file of a pattern chosen
  to make a byte-order mistake obvious is written through the host window
  before `SETUP_COMPLETE`; at exit `FILE_READ_START 1` answers 65,536 and all
  16,384 words read back **identical** to what was loaded. Status 0x667 at
  exit: setup, halted, focus, cartridge present, `.sav` loaded, export region,
  H40 -- and the save-dirty bit correctly **clear**, because Comix Zone never
  touches the save RAM.

## Self-review (2026-09-17, after build 5)

- **Clock domain crossings.** The machine, the glue, the ROM store and the
  SDRAM controller are one synchronous design on `clk_sys`; this port adds no
  crossing of its own. The framework's own crossings are unchanged (the host
  SPI FIFOs, the framebuffer to the display clock, the audio FIFO), and every
  input that reaches the machine from them -- the buttons, the settings
  register, the reset and focus flags -- is registered once more in the glue.
  The SDRAM pin clock is the same PLL's second output; the routed report gives
  clk_sys -> sdram_clk_pin +3.68 / +5.43 ns and back +3.16 / +6.17 ns.
  Inside the machine there is one deliberate half-cycle relationship: the
  68000's phase enables and jt12's `clk_en` are generated on the negative edge
  of MCLK, which is what made jt12's enable the critical path (above).
- **Stall correctness.** There is no clock gating and no stall. `system.sv`
  holds `ROM_REQ != ROM_ACK` until the store answers and only then asserts
  DTACK, so a slow answer costs 68000 wait states and can never return wrong
  data. The store answers and acknowledges on the same clock edge, and both
  sides reset their half of the toggle to 0 (a `ROM_REQ <= 0` was added to
  `system.sv`'s MBUS reset for exactly that), so they cannot disagree after a
  reset -- the failure mode that bit the NGPC port.
- **The SNES lesson (stale bytes under mixed SDRAM traffic) cannot apply
  here**, and not by luck: the arbiter has two initiators, the host's cartridge
  window and the ROM store, and they are never active at the same time. The
  host window only moves data while the core is in setup, which is exactly when
  the machine is held in reset and the store is idle; once the core runs, the
  store is the only SDRAM user in the design. The `.sav` window does not touch
  the SDRAM at all -- it is the save RAM's own block RAM port. The controller
  is `BurstSdramController` at 1x in the system domain with no CDC and no line
  cache, as in the PCE and NGPC ports.
- **Reset.** `reset` (the framework's) resets the glue; `loading` is upstream's
  cartridge-download reset and is held through setup, which also holds the VDP
  (`hard_reset`); `machine_reset` is the framework reset, CoreHalt, the Reset
  action or a region strap change. `loading` drops before `machine_reset` does,
  so FX68K sees `pwrUp` fall before `extReset`, which is the order it wants.
  The focus pause is never asserted while the machine is in reset, because
  `system.sv` clocks its own reset register with a 68000 clock enable and the
  pause withholds those. The memory clear (`RAM_INIT`) is separated from
  `LOADING` so the host's `.sav` window owns the save RAM's B port afterwards,
  and the command stays busy for its 65,536 clocks.
- **DMA.** The VDP's VBUS reads the cartridge through the same MBUS state
  machine and the same handshake as the 68000, so a slow ROM answer slows a DMA
  and cannot corrupt it. Four cache lines rather than one exist because the DMA
  and the instruction stream interleave; with one line they would evict each
  other on every access.
- **Audio mixing.** Everything upstream does is kept: jt12's output scaled by
  22.25/16 to match the PSG, `genesis_fm_lpf`, `jt12_genmix`, and `genesis_lpf`
  with MiSTer's own Audio Filter setting. The glue only re-times: a /8 sample
  enable (6.71 MHz, well above the YM2612's own 53 kHz output rate), a 3-stage
  CIC of 128 to 52,434 Hz, and `AudioRateAdapter` onto the framework's 48 kHz,
  because 53,693,182 is not a multiple of 48,000. Muted without focus.
- **Block RAM.** 82 of 135 tiles (60.7 %), against a by-hand estimate of ~135:
  Vivado packs the small VDP buffers and tables far better than the count
  assumed. LUTs 15,030 (23.7 %), registers 10,346, DSP 24 (jt12's multipliers).
- **Known difference from MiSTer, deliberate:** MiSTer only enables the
  cartridge save RAM when a save file was mounted (`bk_ena`); here any write
  into the 0x200000 window marks the save dirty, so a game with no battery that
  wrote there would leave a 64 KiB `.sav` behind. None of the four test ROMs
  touches it (measured: 0 save-RAM accesses through the boot).

## Packaged

`build/sdcard/cores/minuitfranck.MD`, version 0.0.1+rev2.1, from build 5 at
commit 56087cff (bitstream `GitRev=9d020a821af6`, which is the same RTL plus a
testbench and docs). `md_rev2.bit` sha256
`2f2f4c802a4f939c880a585147d5cb8b478e89e5ab002804f5bdea896b565e3b`;
`UserID=B0100002`; core.json, files.json and settings.json validated as strict
JSON and written without a byte-order mark. `README-rev2.txt` carries the
build facts, the simulation results and the hardware test checklist, which
starts with Comix Zone. Copied to the card on 2026-09-17.

## First hardware attempt (2026-09-17)

The core reached the card and the FPGA, and then the firmware refused to start
it: *"File Save wrong size: Expected 65536 bytes, Actually 0 bytes."* That is a
packaging bug, not a core bug, and it is worth writing down because it is a
trap for any core whose save is optional.

`files.json` asked for a save file of **exactly** 64 KiB. The core, correctly,
reports a save size of zero for a game with no battery (`FileReadStart` returns
`cartLoaded && (savLoaded || saveDirty) ? SaveBytes : 0`), and the firmware's
`persist_files` creates the `.sav` before it asks for the size — so leaving a
game always leaves a file behind, an empty one for Comix Zone. On the next
launch that empty file failed the exact-size test and the load stopped.

`"initialize": true` does not help: it only covers a file that cannot be
opened, and an empty file opens fine. It would also do harm, because a slot
filled by the firmware reports 64 KiB at `FileWriteEnd`, which sets `savLoaded`
and makes every game leave a real save file.

The fix is `"max_size": "0x10000"` and no `initialize` (commit c1720b64). The
core clears its own save RAM when the cartridge arrives, so an empty or short
file needs nothing from the firmware.

## In progress

- A longer core simulation (300 frames, Start pressed at frame 170) is past
  the SEGA logo and running towards the title screen and gameplay; frames are
  dumped every 20 from frame 100 into `build/md/sim-frames`.

## Next

1. **Hardware.** Nothing in this port has run on a Game Bub. The first things
   to watch are the ones the simulation cannot answer: sound (the FM chain is
   wired and the chips are initialized, but no music has played in simulation
   yet), the feel of the cartridge path under a real SDRAM (registers
   0x1018 maximum store latency and 0x101C slow answers are there to read
   back), and whether the 4:3 default looks right on the panel.
2. The `.sav` path on a real battery game (Sonic 3 or Phantasy Star IV); the
   format and the window are both verified in simulation, but no game has
   written it.
3. Save states: not built, and `docs/md-savestates-assessment.md` says why.

## Screen Filter (r2.6)

The framework's LCD screen filter register 0xF100101C (Off / LCD Grid /
Scanlines, plus 3 = Smooth, from the NES port); the MD menu offers Off and
Smooth only (the grid and scanlines need a whole-number scale of 2 or more,
and the MD is at 1x there). Smooth is sharp bilinear in 4:3 (427 x 320), Fit
(457 x 320) and Stretch (480 x 320): every MD pixel stays crisp and only the
one screen pixel on each pixel boundary blends the two neighbors (weights in
eighths), so the uneven 1/2-pixel widths of nearest-neighbor disappear. It
works on the 320 x 224 framebuffer, the same in every VDP mode (H32 centered
with black borders, whose edges blend with black like any other pixel; V30
keeps the middle 224 lines), so no mode changes what it does. 1x and HDMI are
unchanged. See `HandheldSmoothScaler` in
`fpga/src/main/scala/platform/handheld/`.

## Root cause of the black screen (2026-09-17, late)

The core was fine; the build was not. `system.sv` (Verilog) instantiates the
Xilinx `dpram` wrapper (VHDL, `rtl/xilinx/bram.vhd`) and leaves `enable_a`,
`cs_a`, `enable_b` and `cs_b` unconnected, relying on their VHDL defaults of
`'1'`. Xsim applies those defaults. Vivado synthesis does not, across a
Verilog-to-VHDL boundary: the inputs tie low, `q_a <= (others => '1')`, and
the memory behind it is dead logic. The synthesis checkpoint's block RAM
inventory had no `ram68k`, no `vram_*`, no `sram` and no `ramZ80` at all --
only the VDP's internal `DualPortRAM`s, which hardwire `cs => '1'`.

That explains every hardware observation in one stroke:

- ROM reads work (the store is Chisel, not a dpram), so the 68000 boots,
  clears RAM, and calls `JSR $1708` at 0x314 -- which writes the VDP
  registers (reg 12 = 0x81, the H40 we read back) and copies a table into a
  RAM that keeps nothing.
- That routine's `RTS` is the first return-address pop after reset: it pops
  `0xFFFFFFFF`, jumps to the odd address `0xFFFFFF`, and the address error
  lands in the ROM's `BRA *` stub at 0x202. Identical counters on every power
  cycle, because nothing about it is marginal.
- The ROM checksum (0x32E-0x350) comes *after* that call, so it was never
  reached -- not skipped. An earlier reading here blamed open-bus reads of
  `$A10008` for skipping it; the ROM says otherwise, and the 49,461
  prefetches match the RAM-clear loop on the cold-boot path, so the I/O
  registers read zero as they should.
- The Z80 RAM was gone too, so the sound driver the 68000 copies to $A00000
  vanished and the Z80 ran `RST 38h` from ones: no audio. The VRAM was gone:
  nothing to draw.
- The simulation could not reproduce it, because xsim honours the defaults.

The clue was `WARNING: [Synth 8-7023] instance 'ram68k_u' of module 'dpram'
has 13 connections declared, but only 7 given`, in every build log since the
first. The PC Engine and SNES ports use the same wrapper from VHDL and were
never affected. Fix: drive the enables explicitly on all eight instances,
and `.NMI_n(1'b1)` on the T80s Z80 for the same reason.

**Verified on hardware, 2026-09-17 22:50.** Build abd0beae: timing met (WNS
+0.723 ns), block RAM 132 of 135 tiles (the memories are back: 82 before). The
synthesis checkpoint now lists `ram68k_q` (32 nets, was 0) and 141 block RAM
primitives (was 86). Rocket Knight Adventures boots on the first try and
**sound plays** -- the FM and PSG chain, which no simulation had ever taken as
far as a note. The tester's picture and gameplay notes go in the package
README's test log.

One follow-up came out of the same session: upstream's `PAUSE_EN` leaves the
VDP running, so the framework's screenshot could never read a still frame
(`row read 53AE, pixel read 0000`). The capture outputs now hold while paused
(commit after abd0beae).

**Watch item.** Vivado warns `Synth 8-6090 variable 'cycle_cnt' is written by
both blocking and non-blocking assignments, entire logic could be removed`
(`system.sv`, the MBUS state machine). Upstream is the same and Quartus takes
it; here it only gates the Z80's reads of the 68000 bus through the $8000 bank
window, which sample-streaming sound drivers use. If speech or drum samples
come out wrong, look there first. The same warning on `jdo` in `gen_io.sv` has
not shown any symptom: the pad reads correctly.

Tooling that found it, all on the firmware side and reusable: the console
commands `press` (drive the menus from the PC), `verify` (read the loaded
cartridge back out of the core's SDRAM) and `screenshot`; core registers
0x1024-0x1038 and the 20-entry bus-address history at 0x1040 read out through
hidden `visible_if` rows in `settings.json`, which the firmware logs.

## Save states (r2.10 to r2.19)

keFEAR89's `Genesis_MiSTer_Savestates` R58 engine merged in (design section
12; the merge is listed in `fpga/verilog/md/README.md`; the simulation study
is `build/STUDY-md-savestates-kefear89-2026-09-27.md`). r2.10 carries the
machinery and no menu entry (the fork rewrites 1,187 lines of `system.sv` and
632 of `vdp.vhd`, so its test is that nothing changed); r2.11 is the same
bitstream with the Save State, Load State and State Slot entries.

Build (2026-09-27 07:19, `md` @ dfcbb95a + the side-port fix): timing met,
WNS +0.402 ns, WHS +0.023 ns; 39,972 LUTs (63.05 %, from 27 %: 13,187 as
memory, the fork's 64 KiB VRAM shadow and its two small shadows as LUT RAM),
15,020 registers, block RAM 133.5 of 135 tiles unchanged, 32 DSPs; 12
minutes. Unit test `MdSaveStateSpec` 2/2. Before the build, the elaboration
caught a combinational loop in the glue (a `PipelineMemoryArbiter` on the
side of the `PipelineMemoryLowPriorityMux`); the scanner and the engine's
channel take the side port by turns instead.

Simulation of the fork's code on the core-only bench, before the merge
(`build/mdss-sim-2026-09-27`, Comix Zone): a save captured the machine, stored
the 141,312-byte state, verified it and resumed the game; a load verified the
stored data and then failed to freeze the running game for the import (error
5, capture error 2). xsim starts some VDP and I/O registers as unknown where
the FPGA starts them at 0.

Hardware (2026-09-27, Comix Zone, over the console):

- r2.10 (08:32): the regression test passed; a moment more at game start (the
  1 MiB States file).
- r2.11 (09:25): Save 1.5 s and 8 s after a Reset passed; Save 66 s into the
  intro failed after 1,277 ms (error 5); Load at 40 s the same; after a
  failure every request failed at once (29 ms) until Settings > Reset.
- r2.12 (09:58, diagnostics registers 0x0020-0x002C): the failing save had 0
  clocks of the safe point in 1.25 s; the passing one (2 s after Reset) had
  360,993 clocks of its 68000/VDP half (0.96 %).
- r2.13 (10:12): the stale-fail race and the size word zeroed before a
  capture, both fixed (design findings B and C).
- r2.14 (10:31, a selectable-condition counter): in the intro, per second,
  VBlank 14.5 %, VBlank + 68000 quiet 14.49 %, VBlank + renderer idle 13.3 %,
  VBlank + VDP memory idle 0.000 % (finding A; see D for the likely cause).
- r2.15 (11:33, `md` @ 52b607ea, WNS +0.456): the capture point outside the
  blank after 78 ms. Title screen: save 185 ms, one load failed after 1,276 ms
  (the game went on, the next requests worked), then 185 / 159 / 211 ms.
  Attract-mode gameplay: save 185 ms, load 185 ms, the picture back exactly.
  Saves 3/3, loads 4/5. Exit Core wrote `Comix Zone (USA).ss`, 262,144 bytes.
- r2.16 (14:02, `md` @ 32caaa89, WNS +0.379): the engine's periodic slot probe
  off (`PROBE = 0`); register 0x0024 held at the clock the 68000 handler gives
  up. 0 slow ROM answers over 57 s of play (the probe had made about 32 a
  second); save 185 ms, load 211 ms by hotkey. During a load's slot read
  (about 2 ms, the game running) a few hundred ROM answers are a few clocks
  late (max 22).
- r2.17 (17:47, `md` @ 37af8582, WNS +0.206), withdrawn the same evening: the
  machine paused during a load's first slot pass. Comix Zone stage 1: saves
  with the game running 0 of 3; paused by Start, a save passed (182 ms) and
  the first load failed at the hold, after which the picture was solid gray
  and every attempt failed. r2.16 re-tested in the same scene: the same
  failures, and after them the game had restarted from the SEGA logo (after
  three failures, then after a single failed save); loads from the intro
  passed (183, 417 ms). The scene, not the pause, was the cause (finding D);
  r2.17 stays out. Both aftermaths (the gray picture, the restart) come from
  the release after a failed hold and are not understood.
- r2.18 (19:20, WNS +0.045, LUTs 63.2 %, BRAM 133.5 / 135), diagnostics only:
  register 0x0030 shows the VDP's nine memory-idle terms (1 = busy), 0x0034
  holds them as 0x0024 does. The bench can preload a States file
  (`STATES=<.ss>` for run_system.sh, `+slot<n>`) and prints ss_dbg / ss_dbg2
  every frame of a request. Read during a failing save in the paused stage-1
  scene: `DT_VRAM_SEL` the only busy term, every sample.
- r2.19 (20:38, WNS +0.127, LUTs 63.1 %, BRAM 133.5 / 135), one change in
  vdp.vhd: the `SS_MEM_IDLE` term for the VRAM data transfer is `DT_VRAM_SEL =
  vram_ack` (an access in flight) instead of `DT_VRAM_SEL = '0'` (the parity
  of the accesses so far); bit 4 of 0x0030 reports the same. On the card
  20:45. Comix Zone stage 1: paused, three saves 183 ms each; running, three
  saves and a load 183 ms each; the load from the intro 209 ms (989 ms on
  r2.18); the diagnostics all idle throughout.

Open, in this order: (1) the release after a failed hold restarted the game
on r2.16 and r2.18 (the handler's RESET_HOLD / RESET_BOOT, the orchestrator's
abort); rare since r2.19. (2) Re-measure the VBlank + VDP memory idle count
with r2.19 (mask 0x0011 in 0x002C): the 0.000 % of r2.14 was most likely the
parity. (3) The late ROM answers during a load's first pass stay (r2.17's
attempt to remove them is above). The one timed-out load of r2.15 was not seen
again.
