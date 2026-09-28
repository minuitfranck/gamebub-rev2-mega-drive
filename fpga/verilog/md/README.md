# Vendored MiSTer Genesis RTL (Mega Drive / Genesis core for Game Bub rev2)

Source: **Genesis_MiSTer @ adc0c42** ("Release 20230224"), the archived MiSTer
Genesis core. **GPL-3.0-only**; see `LICENSE`. The Game Bub port is under the
same license.

Credits, from the upstream headers and README: the original FPGAGen / Genesis
code is Gregory Estrade's (`greg@torlus.com`, 2010-2013); the MiSTer port and
most of its maintenance are **Sorgelig**'s (2017-2023); the VDP, the bus and
the cartridge work carry contributions from **srg320**, **greyrogue**,
**Kitrinx** and **dshadoff**. The YM2612 (`rtl/jt12`) and the SN76489
(`rtl/jt89`) are **Jose Tejada Gomez** (@topapate), GPL-3.0. The 68000
(`rtl/FX68K`) is **Jorge Cwik**'s FX68K. The Z80 (`rtl/T80`) is **Daniel
Wallner**'s T80. MiSTer-devel's current MegaDrive_MiSTer is a different,
gate-accurate rewrite (Nuked-MD); this port is based on the archived core.

**Save states** come from **keFEAR89**'s
[Genesis_MiSTer_Savestates](https://github.com/keFEAR89/Genesis_MiSTer_Savestates)
R58 (@ 3cd5380, 2026-09-11, GPL-3.0-only), a fork of the same archived core:
its `rtl/savestate/` engine and its changes to `system.sv`, `vdp.vhd`, the T80
and `gen_io.sv` are merged in (2026-09-27; `docs/md-port-design.md` section 12
and `build/STUDY-md-savestates-kefear89-2026-09-27.md`).

## What is here

Everything the Mega Drive machine needs and nothing else. Paths mirror the
upstream `rtl/` tree.

| Path | Upstream | Note |
| --- | --- | --- |
| `rtl/system.sv` | `rtl/system.sv` | the machine: clock enables, the MBUS, the ZBUS, the memories |
| `rtl/vdp.vhd`, `rtl/vdp_common.vhd` | same | the VDP |
| `rtl/FX68K/` | same | the 68000 (+ `fx68k.sdc`, `fx68k.txt` for reference) |
| `rtl/T80/` | same | the Z80 (`T80pa.vhd` is not instantiated and is not vendored) |
| `rtl/jt12/` | same | the YM2612, exactly the file set of upstream's `jt12.qip` |
| `rtl/jt89/` | same | the PSG |
| `rtl/gen_io.sv`, `rtl/multitap.sv`, `rtl/fourway.v`, `rtl/teamplayer.sv` | same | the I/O chip and the pad |
| `rtl/audio_iir_filter.v`, `rtl/genesis_lpf.v` | same | the Mega Drive's audio filters |
| `rtl/savestate/` | Genesis_MiSTer_Savestates R58 `rtl/savestate/` | the save-state engine: `ss_slot_engine.sv` (slots, CRCs, the commands), `ss_snapshot_orchestrator.sv` (the capture and restore sequence), `ss_m68k_handler_test.sv` (the 68000 capture through a forced level-7 interrupt; not a test, despite its name), `ss_system_state.sv`, `ss_freeze_ctrl.sv`. Not vendored: the fork's OSD test engines (`ss_ram_test.sv`, `ss_z80_state_test.sv`, `ss_persistent_export.sv`) and `ss_rom_identity.sv` (the Chisel glue supplies the cartridge identity) |
| `rtl/bram.vhd.altera`, `rtl/mlab.vhd.altera` | `rtl/bram.vhd`, `rtl/mlab.vhd` | reference only, not built (they instantiate `altsyncram`) |
| `Genesis.sv.reference`, `Genesis.sdc.reference` | `Genesis.sv`, `Genesis.sdc` | reference only: the MiSTer top level and its constraints |

New files, GPL-3.0-only, written for this port:

| Path | What |
| --- | --- |
| `rtl/xilinx/bram.vhd` | Vivado-inferable `dpram` / `dpram_dif` / `DualPortRAM` / `obj_cache`, replacing `rtl/bram.vhd` |
| `rtl/gamebub/md_gamebub_core.sv` | the Game Bub top level around `system`; bound from Chisel as `MdCore` |
| `rtl/generated/fx68k_microrom.svh`, `fx68k_nanorom.svh` | the FX68K ROM images as assignments (`tools/gen_fx68k_roms.py`) |
| `tools/gen_fx68k_roms.py` | writes those two from the vendored `.mem` files |

Not vendored: the MiSTer framework (`sys/`), `rtl/sdram.sv`, `rtl/ddram.sv`,
`rtl/pll*` (the Game Bub framework's own SDRAM controller and clock tree
replace them), `rtl/SVP/`, `rtl/cheatcodes.sv`, `rtl/EEPROM_STM95.sv`,
`rtl/cofi.sv`, `rtl/lightgun.sv`, `rtl/miracle.sv`, the jt12 ADPCM tree
(YM2610 only) and `rtl/jt12/jt12.vhd` / `rtl/jt89/jt89.vhd` (VHDL component
declarations; we instantiate from SystemVerilog).

## Modifications to the vendored files

Every one is marked `Game Bub:` in place. Commit `01102f46` is the pristine
copy, so `git diff 01102f46 -- fpga/verilog/md` is the full change set.

| File | Change | Why |
| --- | --- | --- |
| `rtl/system.sv` | new input `RAM_INIT`, which replaces `LOADING` as the port-B clear condition of the work RAM, VRAM and cartridge save RAM (and as the `ram_rst_a` counter's enable) | upstream clears those memories for as long as the cartridge is downloading; the Game Bub needs the save RAM's B port free for the host's `.sav` window while the core is still in setup. `LOADING` keeps every other role. |
| `rtl/system.sv` | `` `ifdef MD_NO_CHEATS`` around the `CODES` instance (`genie_data` becomes the bus data, `GG_AVAILABLE` 0) | the cheat engine sits on the 68000 read path and holds block RAM tables; nothing here can deliver a code file |
| `rtl/system.sv` | `` `ifdef MD_NO_SVP`` around the `SVP` instance, with its bus, DRAM and second ROM port tied off | a second DSP with its own memories, for Virtua Racing only |
| `rtl/system.sv` | `` `ifdef MD_NO_PIER`` around `STM95XXX` and the save-RAM address mux it owns | the Pier Solar SPI EEPROM, one homebrew game |
| `rtl/system.sv` | `sram_addr` / `sram_di` / `sram_wren` are `logic`, not `wire` | driven from `always_comb`; Quartus accepts that on a net, Vivado does not |
| `rtl/system.sv` | the cartridge save RAM is `dpram_dif #(16,8,15,16)`, 64 KiB, not `#(17,8,16,16)`, 128 KiB | the upstream shape is sized for the SVP's DRAM on port B; the save RAM itself is 64 KiB (port A addresses a byte with `MBUS_A[16:1]`, port B a 16-bit word with `BRAM_A[14:0]`), so with `MD_NO_SVP` the upper half was 16 unused block RAM tiles |
| `rtl/system.sv` | every `dpram` / `dpram_dif` instance drives `enable_a`, `cs_a`, `enable_b` and `cs_b` explicitly (and `data_b` where port B is the clear); `ramZ80`'s unused port B is tied off | **Vivado does not apply a VHDL port default to an instance made from Verilog** (xsim does). Left unconnected, `cs_a` was tied low, `q_a` became constant ones, and the work RAM, VRAM, save RAM and Z80 RAM were optimized out: the 68000 booted from ROM, programmed the VDP, then took an address error at its first return; no sound, nothing drawn. The PC Engine and SNES ports instantiate the same wrapper from VHDL and never hit this. Found 2026-09-17 in the synthesis checkpoint: no `ram68k`, `vram_*`, `sram` or `ramZ80` block RAM existed. |
| `rtl/system.sv` | `.NMI_n(1'b1)` on the Z80 (`T80s`) | the same rule: the VHDL default `'1'` is not applied from Verilog, and the Mega Drive has no NMI source |
| `rtl/system.sv` | `ss_m68k_safe_start`: the fork's capture point (`ss_m68k_point_strict`: the 68000 and VDP quiet inside a vertical blank, the Z80 at an opcode fetch) first; after 2^22 clocks (78 ms) of a request without it, also the same point outside the blank (`ss_m68k_point_cpu`); `SS_DBG`, a 32-bit diagnostics word (design section 12) | in busy scenes the strict point did not come within 1.25 s (r2.11 timed out where r2.15 saves in 0.2 s); see also finding D below, which explains much of that |
| `rtl/vdp.vhd`, `rtl/system.sv`, `rtl/gamebub/md_gamebub_core.sv` | `SS_MEM_TERMS` / `ss_dbg2` (r2.18): the nine terms of `SS_MEM_IDLE` one by one, 1 = busy (FIFO not empty, `IN_DMA`, `DTC`, `DMAC`, `DT_VRAM_SEL`, `FF_VBUS_SEL`, `CRAM_WE_A`, `VSRAM0_WE_A`, `VSRAM1_WE_A`), register 0x0030 live and 0x0034 held | in busy scenes (Comix Zone stage 1, Gunstar Heroes) the engine parked the 68000 and then waited for `SS_MEM_IDLE` until its watchdog; this names the term |
| `rtl/vdp.vhd` | `SS_MEM_IDLE` (r2.19): the data-transfer term is `DT_VRAM_SEL = vram_ack` (an access in flight) instead of the fork's `DT_VRAM_SEL = '0'`; bit 4 of `SS_MEM_TERMS` the same | `DT_VRAM_SEL` is a toggle request, so its level is the parity of the VRAM data accesses so far: after an odd number the VDP read as busy while idle, and with the 68000 held nothing flipped it back (the "mode 2" failures and the inconsistent results of r2.11 to r2.18; design finding D) |
| `rtl/savestate/ss_m68k_handler_test.sv` | `pass` and `fail` cleared whenever `start` is low (`ST_IDLE`, `ST_DONE`); `dbg_state` output | the orchestrator sampled the previous attempt's `fail` one clock before the handler would have cleared it, so one failure made every later request fail at once |
| `rtl/savestate/ss_slot_engine.sv` | the slot's size word is no longer zeroed before a capture (`SAVE_CONTROL_WAIT`) | a save that failed wiped the state already in the slot |
| `rtl/savestate/ss_slot_engine.sv` | `parameter PROBE` (1 = the fork's behavior); the glue instantiates it with 0 | the periodic header probe (two DDR reads every 2^20 clocks) delayed a few ROM fetches a second; the glue's slot scanner reads the headers instead |
| `rtl/savestate/ss_slot_engine.sv` | `` `ifdef MD_SIM_SHORT_WATCHDOG``: the request watchdog is 2^24 clocks (0.31 s) instead of 2^27 (2.5 s) | simulation only (`EXTRA_DEFS` of the bench), so a failing request and its release fit in a run of a few dozen frames |
| `rtl/savestate/ss_snapshot_orchestrator.sv` | `dbg_state` output | the diagnostics word |
| `rtl/system.sv` | `.VRAM_SPEED(~(FAST_FIFO\|(\|TURBO)))` and `.VSCROLL_BUG(1'b0)` | both VHDL ports are one `std_logic`; the upstream actuals are 2- and 32-bit expressions |
| `rtl/FX68K/fx68k.sv` | the two `$readmemb` calls become `` `include`` of `rtl/generated/fx68k_*rom.svh`` | a bare relative filename resolves differently in Vivado, xsim and Quartus |
| `rtl/T80/T80.vhd`, `rtl/T80/T80s.vhd` | `x : entity work.E` instead of `x : work.E` (4 places) | the short form is a Quartus extension, not VHDL |
| `rtl/T80/T80.vhd` | `ioq and "000000111"` instead of `ioq and x"7"` | `ioq` is 9 bits and a VHDL hex literal is 4 bits per digit; Quartus extends it silently, Vivado refuses (Synth 8-509) |
| `rtl/vdp.vhd` | every `synthesis translate_off` region commented out | debug writers (`vdp.out` is one line per pixel, about 1 MB of text per frame) that dominated the run time of a whole-machine xsim simulation; synthesis never saw them |
| `rtl/jt12/jt12_top.v` | `accum_r[0:6]` / `accum_l[0:6]` instead of `[7]` | the single-value unpacked range is SystemVerilog, and the file is compiled as Verilog |
| `rtl/fourway.v` | the `always` block with a declaration in it is named `ctl` | a declaration in an unnamed block is SystemVerilog |
| `rtl/system.sv`, `rtl/vdp.vhd`, `rtl/T80/T80.vhd`, `rtl/T80/T80s.vhd`, `rtl/gen_io.sv`, `rtl/fourway.v`, `rtl/multitap.sv` | the R58 save-state changes merged in (2026-09-27): a three-way merge of the fork against adc0c42 onto our files. `vdp.vhd`, the T80, `fourway.v` and `multitap.sv` merged without a conflict; `system.sv` had 7 and `T80.vhd` and `gen_io.sv` one each, where our edit and the fork's touch the same lines (the RAM port-B clears, `entity work.`, the `static` declarations), resolved with both. The fork's `jt12` edits (Quartus timing clean-ups) are not taken | save states (docs/md-port-design.md section 12) |
| `rtl/system.sv` | the fork's three shadow memories (`ss_vram_shadow`, 64 KiB; `ss_vdp_local_shadow`, 768 bytes; `ss_fm_shadow`, 512 bytes) carry `(* ram_style = "distributed" *)` instead of the fork's Quartus `ramstyle = "M10K"` | the build has 1.5 of 135 block RAM tiles free and the VRAM shadow alone would need 16; as LUT RAM they cost about a sixth of the chip's LUTs |
| `rtl/system.sv`, `rtl/gen_io.sv`, `rtl/teamplayer.sv` | `static` on the 30 variables declared inside `always` blocks | **xsim gives such a variable automatic lifetime**: with an initializer it is re-initialized on every execution of the block, without one it is X on every execution. Quartus and Vivado synthesis give it static lifetime, so this is a simulation-only fix, but without it nothing runs in xsim: the clock-enable divider stayed at its reset value, `M68K_CLKENp` and `M68K_CLKENn` were both high, FX68K's `BeI` never updated (`wClk` stuck), and the 68000 never fetched. Naming the block is not enough; `static` is what xsim honors. |

Build defines: `MD_NO_CHEATS`, `MD_NO_SVP`, `MD_NO_PIER` (set in
`fpga/scripts/build_core.py` and in the simulation scripts); `MD_SIM_SHORT_WATCHDOG`
for the bench only.

## Regenerating

```
python fpga/verilog/md/tools/gen_fx68k_roms.py
```

Deterministic; the output depends only on the vendored `.mem` files, and
`build_core.py` runs it before every build.
