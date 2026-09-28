# Save states for the Mega Drive port: assessment, 2026-09-17

> **Outcome (2026-09-27).** The engine assessed here was merged into the port after all (r2.10) and works on the
> handheld since r2.19. Four changes were needed on top of it: a capture point outside the vertical blank (r2.15),
> the handler's stale `fail` flag cleared (r2.13), the slot's size word written after the data (r2.13), and the VDP
> "memory idle" test compared against the VRAM acknowledge instead of a toggle's level (r2.19). Design note
> section 12 has the details; `build/STUDY-md-savestates-kefear89-2026-09-27.md` has the simulation study. The
> text below is the assessment as written on 2026-09-17, with one correction in section 5: a DMA in flight is not
> lost, because the capture waits for the VDP's `SS_MEM_IDLE`, which includes "no DMA".

What `Genesis_MiSTer_Savestates` @ 3cd5380 ("Savestates R58 (Beta)") does, whether it could drive this port's
0x14 / 0x18 / 0x100 registers and a `.ss` file, how invasive it is, and the recommendation at the time.

Read: `README.md`, `README_R58_EN.md`, `R58_SOURCE_MANIFEST.json`, `R58_changes.diff`, the nine files of
`rtl/savestate/`, and the fork's `rtl/system.sv`, `Genesis.sv`, `rtl/vdp.vhd` and `rtl/T80/T80.vhd` diffed against
the archived core vendored here (`Genesis_MiSTer` @ adc0c42).

**Recommendation at the time: do not adopt.** The fork does not take a snapshot of the machine from outside; it
makes the game take one, by forcing a level-7 interrupt into a handler the core fabricates at an unused I/O
address, and it restores by resetting the 68000 into another fabricated handler that reloads the registers and
`RTE`s. The other three ports here use MiSTer's `savestates.sv`, the opposite approach: every module exports its own
state through a bus, the machine is parked at an instruction boundary, and nothing the game can see changes.

## 1. What the snapshot captures

| Part | How | Captured |
| --- | --- | --- |
| **68000** | `ss_m68k_handler_test.sv`: `irq7` is forced, the core answers the interrupt-acknowledge cycle itself and feeds the CPU a fabricated handler at `0xA14000` that writes D0-D7/A0-A7/SR/PC into a scratch area at `0xA14100`; the SSP is taken from the bus, then the CPU is held in reset. Restore feeds a fabricated reset vector at `0xA14008` that reloads them and `RTE`s. | the architectural registers. The prefetch queue, the current instruction, the bus cycle in flight and the exact cycle position are not saved; the CPU is reset in between. FX68K itself is unmodified (0 changed lines). |
| **Z80** | `ss_z80_state_test.sv` with T80's own `REG` / `DIR` ports, widened by the fork from 212 to 230 bits (adds `Halt_FF`, `Alternate`, `WZ`), restored into a clean opcode-fetch context (`ISet`, `XY_State`, `XY_Ind` forced) | the architectural registers, restored at an instruction boundary. |
| **Work RAM, Z80 RAM** | a byte stream over the existing test ports, read twice and CRC-compared | yes, 64 KiB + 8 KiB. |
| **VDP memory** | `ss_snapshot_orchestrator.sv`, a dense scan of 66,304 bytes: 64 KiB VRAM, then CRAM + VSRAM0 + VSRAM1 + a 512-byte persistent sprite-attribute cache, taken while the raster keeps running, during VBlank with the renderer and the VRAM32 port idle, aborting if that window is lost | yes, with a double-read CRC check. |
| **VDP architectural state** | a 64-byte bank at `0x30300` latched at capture (registers, control port state, IRQ and raster state), also double-read | yes; `vdp.vhd` grew 632 changed lines to expose and restore it. |
| **DMA in flight** | the capture waits for `SS_MEM_IDLE`, which includes "no DMA" (correction of 2026-09-27) | not applicable. |
| **YM2612** | not snapshotted. `system.sv` shadows every register write and, on restore, resets the chip and replays the shadow register by register, with the chip's clock enable running while the CPUs are frozen | the register file, not the state: envelope phase, operator phase accumulators, the LFO, the timers and the PCM channel's position restart. |
| **PSG** | a shadow of tone / volume / noise registers replayed after a reset | the register file, not the phase. |
| **Cartridge mapper** | `BANK_REG[0..7]`, `BANK_ROM`, `BANK_SRAM`, the Z80 bank register `BAR`, `Z80_BUSRQ_N` and `Z80_RESET_N`, in a 252-bit `ss_sys_live` image | yes. |
| **Battery save RAM** | not in the state; MiSTer's own backup-RAM file, as in the base core | out of scope. |
| **SVP, Pier Solar, multitap, mouse, light gun, serial** | listed as unsupported by the fork | not built here. |

Slot payload: 141,312 bytes (`PAYLOAD_BYTES = 0x22800`), in four MiSTer DDR slots at `0x3E100000` with a 256 KiB
stride, each with a header carrying a format word, a CRC, a ROM identity and a machine-configuration identity,
both checked before a load (`ss_rom_identity.sv`, `ss_slot_engine.sv`).

## 2. Could it drive the port's registers and a `.ss` file?

The storage side maps over directly:

- `ss_slot_engine.sv` has the shape wanted: four fixed-size slots, a header with a CRC and a ROM identity, a save
  command, a load command, and busy / pass / fail outputs. Its DDR port (`ddr_req` / `ddr_rnw` / `ddr_addr` /
  `ddr_din` / `ddr_dout` / `ddr_ack`, 64-bit) becomes a `PipelineMemoryInterface` initiator on the SDRAM arbiter, as
  `NgpcSaveStatePort` is, with 141,312 bytes per slot at SDRAM `0x1000000` and a 256 KiB stride: 1 MiB of a 32 MiB
  chip.
- `save_cmd` / `load_cmd` / `selected_slot` map onto register 0x14 bits 0 and 1 and register 0x18 as in the SNES,
  NES and NGPC cores; `busy`, `pass`, `fail` and `slot_valid` onto status bits 6-14 of 0x100; the `settings.json`
  entries are the NGPC's with the addresses unchanged.
- `.ss` is the four slots as they sit in the SDRAM, loaded and read back through a host window, as the NGPC port
  does.

(This is how it was done in r2.10; design note section 12.)

## 3. How invasive it is

Against the archived core vendored here:

| File | Changed lines | Of |
| --- | --- | --- |
| `rtl/system.sv` | 1,187 | 1,465 |
| `Genesis.sv` | 2,740 | 1,192 (rewritten and grown) |
| `rtl/vdp.vhd` | 632 | 3,704 |
| `rtl/T80/T80.vhd` | 60 | 1,175 |
| `rtl/FX68K/*`, `rtl/jt12/*`, `rtl/jt89/*` | 0 | |
| new `rtl/savestate/*.sv` | about 2,300 | |

`system.sv` is the file this port depends on most, and 81 % of its lines change: the port's own changes to it (the
`RAM_INIT` split, the three `ifdef`s, the portability fixes) have to be re-derived on top, and later comparisons
with upstream are against a different base. `Genesis.sv` is not used here. Resources: the four slots are
file-backed; the block RAM cost is the shadows (the YM2612 register file, the PSG registers, the 512-byte sprite
cache, the 252-bit system image) plus the orchestrator's state. The build already had no block RAM to spare (see
`docs/md-port-status.md`); the shadows went into LUT RAM in r2.10.

## 4. State of the fork

- The README's first line: "**Beta release.** ... Save/load may fail in some games or configurations. Do not rely on
  savestates as the only copy of important progress."
- Three of the nine engine files keep a `_test.sv` name (`ss_m68k_handler_test.sv`, `ss_z80_state_test.sv`,
  `ss_ram_test.sv`) and are the shipping engine. Header comments carry a version history (v0.8 to R58).
- The repository was one week old, with no test suite in the tree and no list of verified games.
- The engine double-reads and CRC-checks both the VDP memory and the architectural bank, aborts when the VBlank or
  renderer-idle window is lost, checks the ROM identity and configuration before a load, and states that oscillator
  phase is canonicalized by reset and replay.

## 5. What differs in play

A restored state differs from the saved one in ways a player can hear and occasionally see:

- **Sound restarts rather than resumes.** Both chips are reset and replayed: every FM note's envelope and phase, the
  LFO and the PCM sample position start over.
- **The 68000 loses its pipeline.** Restoring through a reset and an `RTE` is exact at an instruction boundary, and
  the save is taken at a level-7 interrupt boundary, not the boundary the game was at.
- **The interrupt is visible to the game.** The capture pushes a frame on the game's own stack and runs fabricated
  code. A game with a tight stack, a game that uses level 7 itself, or a game inside a critical section can be
  disturbed by the act of saving.

## 6. Recommendation at the time

Do not adopt: a re-derivation of the whole `system.sv` change set onto an 81 %-rewritten file, plus a 632-line VDP
delta, for a feature that is beta upstream and whose restored state is audibly different from the saved one. If
save states were wanted later, write them MiSTer-generic style: park the machine (the 68000 at an instruction
boundary, the Z80 at `M1`, the VDP at a frame boundary with the FIFO empty and no DMA, the ROM store drained),
export the memories through their second ports (about 140 KiB), export the registers of `system.sv` and the VDP,
and add a state export to FX68K and jt12, which is the open problem.

Superseded by the outcome above: the merge went ahead on 2026-09-27 as a two-package plan, and the engine's
limits found on the handheld were fixed in the engine itself.
