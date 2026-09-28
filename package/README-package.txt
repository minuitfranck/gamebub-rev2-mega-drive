Mega Drive / Genesis core (minuitfranck.MD) built for Game Bub rev2 (vertical) - package version 0.0.2+rev2.2 (2026-09-17 23:04)
Source: the archived MiSTer-devel/Genesis_MiSTer @ adc0c42, GPL-3.0. Original Genesis code by Gregory Estrade;
        MiSTer port and maintenance by Sorgelig, with srg320, greyrogue, Kitrinx and dshadoff; YM2612 and PSG by
        Jose Tejada Gomez (jt12 / jt89); 68000 by Jorge Cwik (FX68K); Z80 by Daniel Wallner (T80). Subset vendored
        in gamebub-rev2\core-md\fpga\verilog\md (changes listed in its README.md) + Game Bub glue in
        gamebub-rev2\core-md (branch md @ 44769768, bitstream GitRev 44769768fe5f). Port by minuitfranck with Claude.
        Personal build: do not share the bitstream. Design: core-md\docs\md-port-design.md;
        status: docs\md-port-status.md.
Build:  Vivado 2023.2, xc7a100tcsg324-1, target gamebub_rev2, system clock 53.693 MHz (the Mega Drive's own
        master clock, from the 50 MHz oscillator as 189/176);
        Post Routing Timing Summary | WNS=0.810  | TNS=0.000  | WHS=0.013  | THS=0.000  |
        | Slice LUTs                 | 16104 |     0 |          0 |     63400 | 25.40 |
        | Slice Registers            | 11586 |     0 |          0 |    126800 |  9.14 |
        | Block RAM Tile    |  132 |     0 |          0 |       135 | 97.78 |
        | DSPs           |   24 |     0 |          0 |       240 | 10.00 |
        md_rev2.bit sha256 c9e8c9e37238670bc15d4cc73d3e3ee34c985f3a6df4712054a1e4ce43052110
Firmware: v1.1.0-beta1 local8 or newer (SD-card cores). local10 adds the console commands verify and press
        used while testing; no firmware change is needed to play.

Simulation (xsim, Vivado 2023.2), Comix Zone (USA), 2 MiB:
      Core-only (the machine + a behavioural ROM store at a flat 8 clocks, no cache): the 68000 fetches its
      reset vector, clears the work RAM and is back in code by frame 2; H40 (320 x 224) from the first frame,
      frames exactly 16.688 ms apart (59.92 Hz); the Z80 is out of reset by frame 14 with the VDP, the YM2612
      and the PSG all being written. First picture at frame 38 (0.63 s), and the SEGA logo is fully drawn at
      frame 80 (1.33 s) - 320 wide, correct shapes and shading.
      Whole-system (the real SDRAM controller and a chip model, the host protocol as the firmware drives it):
      the 2 MiB cartridge loads through the file window; the header reads back as "MK-1569 " with the region
      detected as USA and no quirks; SETUP_COMPLETE and CoreRun as the firmware does them. Over 45 frames the
      cartridge path did 789,950 store transactions with 693,705 window-cache hits, 436,076 SDRAM reads (78 %
      of them prefetches) and no SDRAM writes; worst answer 11 clocks against the 68000's ~11-clock budget,
      and ZERO answers slower than that budget. A 64 KiB .sav loaded before the run reads back byte-identical
      at Exit Core, and the cartridge save RAM's byte order - what makes our .sav a MiSTer .sav - is proved
      by its own testbench.

Files in this folder: core.json, files.json, settings.json, md_rev2.bit. No BIOS: a Mega Drive
      has none, the 68000 boots straight out of the cartridge.
Games: .md / .bin / .gen (lower-case extensions; the file browser matches extensions case-sensitively), up to
      10 MiB. Not supported, by design: Virtua Racing (the SVP chip), Pier Solar, Sega CD and 32X, and anything
      that needs a multitap, a mouse or a light gun.
Saves: games with a battery write a 64 KiB <game>.sav next to the ROM on Exit Core. It is the same format as a
      MiSTer .sav. A game without a battery leaves an empty <game>.sav instead, which the core ignores: the
      save file may be any size up to 64 KiB, and the core clears its save RAM itself when the cartridge
      arrives. (None of the four test ROMs has a battery; Sonic the Hedgehog 3 and Phantasy Star IV are the
      usual ones to try.)
Save states: not in this build. See core-md\docs\md-savestates-assessment.md.
Video: 320x224 and 256x224 both work; a 256-wide picture is centered with black borders, so a game that switches
      modes does not jump around. Scaling defaults to 4:3, the shape a Mega Drive was meant to be seen in
      (427x320 of the 480x320 panel); Fit gives square pixels (457x320), Stretch fills the panel, 1x is the
      unscaled 320x224.
Controls: d-pad; Genesis A B C on Y B A and X Y Z on L X R by default. Comix Zone and Rocket Knight both put
      jump on Genesis B and attack on A and C, so out of the box jump is B and attack is A or Y, like a SNES game;
      the setting Buttons: "A B C = B A X" puts jump on A instead. Start = Start, Select = Mode. The 6-button pad is the default; setting Pad = 3 button
      for the few games that misread one.
Settings: Reset, Scaling, Region (Auto / Japan / USA / Europe), Video (From region / 60 Hz / 50 Hz), Pad,
      Buttons, Audio Filter (Model 1 default, as MiSTer), Mono, Sprite Limit, CRAM Dots, HiFi PCM, FM Chip
      (YM2612 / YM3438), Border.

OWNER TEST CHECKLIST (in this order; note what you see for each):
 0. What simulation could NOT check, so listen and look hard here: SOUND. The whole audio chain is wired and
    the YM2612 and the PSG are initialized and answer the CPU in simulation, but no music had started by the
    point the runs reached, so not one note has been through the resampler. If something is wrong with sound
    it will be obvious in the first seconds of any of these games.
 1. Install: copy this folder to the card as cores\minuitfranck.MD (the install script does it). Cores > Mega Drive / Genesis
    must be listed. Put the .md files in roms\MD (or wherever you keep them) and pick one.
 2. **Comix Zone (USA)** - the one that matters. The SEGA screen, then the title, then Start into the game.
    Watch for: a full 320-wide picture with sensible colors, music and sound effects, and the pad doing what it
    should (B attacks, A jumps, Y is the special move). Play a couple of minutes of the first page and watch for
    slowdown, stutter or crackling audio - the cartridge is read from SDRAM and that path is the main risk of
    this port.
 3. Sonic the Hedgehog 2 - scrolling and sprite-heavy; watch for tearing or dropped frames in Emerald Hill.
 4. Streets of Rage 2 - the FM soundtrack is the test here; it should be clean, in tune and not clipping.
 5. Altered Beast - a small 512 KiB ROM and a good test of the speech samples (the PCM channel).
 6. Home menu while playing: the game pauses (sound stops) and resumes where it was.
 7. Settings: Scaling modes (4:3 / Fit / 1x / Stretch), Audio Filter Model 2 and None (audible difference), Pad =
    3 button (Comix Zone should still play), Reset (the game restarts).
 8. A game with a battery, if you have one (Sonic 3, Phantasy Star IV): save in game, Exit Core, check that
    <game>.sav appeared next to the ROM, launch again and load the save.
Useful to report if something is wrong: the core register dump 0x0100 (status: bit 5 cartridge present, 8 PAL,
      9 export, 11:10 VDP resolution), 0x1000-0x1020 (statistics: frames, ROM transactions, cache hits,
      SDRAM reads / writes, prefetches, max store latency, slow answers, run clocks) and 0x1024-0x102C (where
      the 68000 is: its last bus address, and the lowest and highest it reached in the last 64 frames).

TEST LOG (hardware): 2026-09-17 - Rocket Knight Adventures (USA) boots with sound on the first try after the
      RAM-enable fix (abd0beae); earlier builds hit an address error on the first RTS because Vivado had
      optimized every work RAM out of the netlist (see core-md docs\md-port-status.md, "Root cause").

SETTINGS UPDATE 2026-09-18: package 0.0.2+rev2.3 (settings.json only; the bitstream is unchanged, md_rev2.bit sha256 c9e8c9e37238670bc15d4cc73d3e3ee34c985f3a6df4712054a1e4ce43052110).
The Border checkbox is removed: on the fixed 320x224 frame it shifted the picture and cut off its right and bottom edges. The border bit resets to off.


REBUILD 2026-09-18 23:51: package 0.0.2+rev2.4 (was 0.0.2+rev2.3); core-md branch md @ e3be1a13
Build:  Vivado 2023.2, xc7a100tcsg324-1, target gamebub_rev2; timing met, WNS 0.355 ns, WHS 0.015 ns
        Slice LUTs 16097 of 63400 (25.39%), Block RAM Tile 132 of 135 (97.78%), DSPs 24 of 240 (10.00%)
        md_rev2.bit sha256 59b28c6fe170e468de427b2d14086460e4622eca3d638e0e9a2a80389bbd301f
Jeremy's SDRAM precharge fix (f242532462): the burst-ending precharge now closes all banks (matters for ROMs above 8 MiB and firmware transfers that cross banks). Same features as 0.0.2+rev2.3 otherwise.
TEST LOG (hardware): not yet run for this build.
TEST LOG (hardware, 2026-09-19 00:15-00:17, firmware local13): Comix Zone (USA)[Easiest] boots to its title, Start leads (after a black transition) into gameplay in episode 1: FIRST TIME COMIX ZONE RUNS ON THIS CORE. Sound not checked (no one listening).

TEST LOG (hardware, 2026-09-19 15:19-15:20, firmware local14, owner): BATTERY SAVE CONFIRMED ON THE DEVICE. Sonic the
Hedgehog 3 (USA): started a save slot, played, Exit Core wrote Sonic the Hedgehog 3 (USA).sav (65536 B, 80 non-empty
bytes, sensible slot data, not ROM bytes), relaunched and DATA SELECT shows the file at Zone 1. The card was checked
read-only afterwards: chkdsk clean, no cross-links.


REBUILD 2026-09-24 10:50: package r2.5 (was r2.4); core-md branch md @ 5ee68d00
Build:  Vivado 2023.2, xc7a100tcsg324-1, target gamebub_rev2; timing met, WNS 0.407 ns, WHS 0.026 ns
        Slice LUTs 16270 of 63400 (25.66%), Block RAM Tile 132 of 135 (97.78%), DSPs 24 of 240 (10.00%)
        md_rev2.bit sha256 a6a460dc9ab810c4b1ce3f985fffbeb599c3d7081eacc077b22c550d63656078
Sound: MiSTer's DC blocker in the framework (about 15 Hz at 48 kHz): the output is centered on zero (no constant offset, fewer pops where the sound starts or stops). Saves: the framework's SPI receiver fix (a transfer that starts while an earlier one is still queued is no longer misread).
TEST LOG (hardware): not yet run for this build.


REBUILD 2026-09-25 13:24: package r2.6 (was r2.5); core-md branch md @ 9135c267
Build:  Vivado 2023.2, xc7a100tcsg324-1, target gamebub_rev2; timing met, WNS 0.131 ns, WHS 0.019 ns
        Slice LUTs 17134 of 63400 (27.03%), Block RAM Tile 133.5 of 135 (98.89%), DSPs 32 of 240 (13.33%)
        md_rev2.bit sha256 846103c9cf1c01c8a82e640e40fab8fecb0c94c5d8ae56746b0538b26ce45bf6
Screen Filter setting (id 12): Off / Smooth. Smooth = sharp bilinear on the LCD in 4:3, Fit and Stretch (1x and HDMI unchanged); framework register 0xF100101C = 3, from the NES port.
TEST LOG (hardware): not yet run for this build.


REBUILD 2026-09-25 16:21: package r2.7 (was r2.6); core-md branch md @ b17bcd23
Build:  Vivado 2023.2, xc7a100tcsg324-1, target gamebub_rev2; timing met, WNS 0.328 ns, WHS 0.028 ns
        Slice LUTs 17111 of 63400 (26.99%), Block RAM Tile 133.5 of 135 (98.89%), DSPs 32 of 240 (13.33%)
        md_rev2.bit sha256 f3254a1fc9d67b9adc65ac6b3e4706d85f910fd8117eb66f86c8b2258da4de03
Screen Filter: Smooth without latency (fixes the garbage strip on the first 2 rows of every LCD scan line, seen with Off too); HandheldLcdScanSpec checks every displayed pixel.
TEST LOG (hardware): not yet run for this build.


REBUILD 2026-09-26 10:55: package r2.8 (was r2.7); core-md branch md @ da2b80e9
Build:  Vivado 2023.2, xc7a100tcsg324-1, target gamebub_rev2; timing met, WNS 0.348 ns, WHS 0.026 ns
        Slice LUTs 17110 of 63400 (26.99%), Block RAM Tile 133.5 of 135 (98.89%), DSPs 32 of 240 (13.33%)
        md_rev2.bit sha256 c0e7b8ef949531156165c90a5f3ff853683e77974f824d276944bd92be29cfd1
r2.7 + one change: the screen driver never cuts a refresh short (a 50 Hz / PAL game, or pictures faster than the panel, could leave a ghost on the screen). No visible change at the normal rate.
TEST LOG (hardware): not yet run for this build.


REBUILD 2026-09-26 14:30: package r2.9 (was r2.8); core-md branch md @ 76ff40fd
Build:  Vivado 2023.2, xc7a100tcsg324-1, target gamebub_rev2; timing met, WNS 0.600 ns, WHS 0.023 ns
        Slice LUTs 17163 of 63400 (27.07%), Block RAM Tile 133.5 of 135 (98.89%), DSPs 32 of 240 (13.33%)
        md_rev2.bit sha256 3550f64ab6b893bdfda09133bb7bf5b99eef78271448a1f36c5a5fc41d0f409d
r2.8 + one change: counts screen refreshes for the log (repeats 0xF1002008, refreshes 0xF100200C) to check the screen fix. No visible change.
TEST LOG (hardware): not yet run for this build.


REBUILD 2026-09-27 07:19: package r2.10 (was r2.9); core-md branch md @ 50f899d6
Build:  Vivado 2023.2, xc7a100tcsg324-1, target gamebub_rev2; timing met, WNS 0.402 ns, WHS 0.023 ns
        Slice LUTs 39972 of 63400 (63.05%), Block RAM Tile 133.5 of 135 (98.89%), DSPs 32 of 240 (13.33%)
        md_rev2.bit sha256 b961a4e1dee844144c8fc22be2a7274968d5e38f6cc9e94e4b1424652b928626
Save-state machinery: keFEAR89's Genesis_MiSTer_Savestates R58 engine merged in (core-md md @ dfcbb95a + the side-port fix), NO menu entries in this package: a regression test of the merged machine (the fork rewrites much of system.sv and 632 lines of the VDP). The three shadow memories are LUT RAM (block RAM stays 133.5 of 135); LUTs 27% -> 63%. files.json gains the States file (id 2, 1 MiB at 0x50000000). Save State / Load State / State Slot come as r2.11, the same bitstream with three settings.json entries.
TEST LOG (hardware): not yet run for this build.


PACKAGE r2.11 (2026-09-27 09:30): the r2.10 bitstream unchanged (sha256 b961a4e1...), plus three settings.json entries:
      Save State (id 13, Home + R), Load State (id 14, Home + L), State Slot (id 15, 1-4). The engine behind them
      is keFEAR89's Genesis_MiSTer_Savestates R58 (docs/md-port-design.md section 12): a save interrupts the game for
      about 4 frames, a load about 5; the FM and PSG restart their notes after a load; a load that fails resets the
      game. Four slots in <game>.ss (256 KiB each, written on Exit Core; byte for byte a MiSTer .ss). r2.10 passed
      its regression test (Comix Zone, Phantasy Star IV with its battery save) the same morning.


REBUILD 2026-09-27 09:56: package r2.12 (was r2.11); core-md branch md @ 14b73d53
Build:  Vivado 2023.2, xc7a100tcsg324-1, target gamebub_rev2; timing met, WNS 0.314 ns, WHS 0.015 ns
        Slice LUTs 40081 of 63400 (63.22%), Block RAM Tile 133.5 of 135 (98.89%), DSPs 32 of 240 (13.33%)
        md_rev2.bit sha256 c95731054fa05515fd2971f1d69adf58d293cbcd56f6f505e3fa40878516fbd8
Diagnostics for the save-state engine, nothing else: registers 0x0020 (live) / 0x0024 (held at the end of a request) show the orchestrator and 68000 capture handler states and every safe-point term, 0x0028 / 0x002C count the clocks of a request with the safe point (all terms / the 68000-VDP half) true. For the two problems r2.11 showed on the handheld: no capture within 1.25 s in some game phases (save 66 s into Comix Zone's intro, load at 40 s), and every attempt failing at once after a failure until a Reset.
TEST LOG (hardware): not yet run for this build.


REBUILD 2026-09-27 10:15: package r2.13 (was r2.12); core-md branch md @ ff02c45f
Build:  Vivado 2023.2, xc7a100tcsg324-1, target gamebub_rev2; timing met, WNS 0.036 ns, WHS 0.045 ns
        Slice LUTs 40094 of 63400 (63.24%), Block RAM Tile 133.5 of 135 (98.89%), DSPs 32 of 240 (13.33%)
        md_rev2.bit sha256 d805546a7057d9a9537fa288d41998cf2ee916499b54a026ecc66c75e6b96802
Save-state engine, failed attempts, two fixes: (1) the 68000 capture handler clears its pass / fail while the request line is low, so a failed attempt no longer makes every later attempt fail at once (a one-clock race: the orchestrator read the stale fail before the handler cleared it); (2) a save no longer zeroes the slot's size word before its capture, so a failed save keeps the state that was in the slot (the fork zeroed it for MiSTer's Main polling). The r2.12 diagnostics registers stay. The capture itself still needs a quiet moment the game does not give in busy scenes (the diagnostics found the 68000 / VDP terms never true in Comix Zone's intro); that is the next step.
TEST LOG (hardware): not yet run for this build.


REBUILD 2026-09-27 10:29: package r2.14 (was r2.13); core-md branch md @ 70ff5773
Build:  Vivado 2023.2, xc7a100tcsg324-1, target gamebub_rev2; timing met, WNS 0.135 ns, WHS 0.020 ns
        Slice LUTs 40056 of 63400 (63.18%), Block RAM Tile 133.5 of 135 (98.89%), DSPs 32 of 240 (13.33%)
        md_rev2.bit sha256 967efcfb1eac31f50fddd0f116f797719cfd1c1d604e7b34a895533ff2925ff6
Diagnostics only, on r2.13: register 0x002C takes a mask of the safe-point terms and 0x0028 counts, all the time, the clocks in which every masked term is true (a write of the mask restarts it), so any combination can be measured while a game runs. A test settings.json (build/md-r2.14-diag-settings.json, entry 'Diag mask') selects the mask from the menu; not part of the package.
TEST LOG (hardware): not yet run for this build.


REBUILD 2026-09-27 10:59: package r2.15 (was r2.14); core-md branch md @ 52b607ea
Build:  Vivado 2023.2, xc7a100tcsg324-1, target gamebub_rev2; timing met, WNS 0.456 ns, WHS 0.030 ns
        Slice LUTs 40014 of 63400 (63.11%), Block RAM Tile 133.5 of 135 (98.89%), DSPs 32 of 240 (13.33%)
        md_rev2.bit sha256 94e6edc8aae5e255f738b467451bd5b96cae84f2c3dfcd4dba9bc325fe4fc612
The capture's quiet moment, relaxed: the fork's strict point (vertical blank, no DMA, renderer idle) is tried first; after about five frames without it (2^22 clocks, 78 ms) the capture also accepts the relaxed point outside the blank (the 68000 between bus cycles, no DMA in flight, the VDP FIFO empty, the Z80 at an opcode fetch). Measured with r2.14 in Comix Zone's intro: inside the blank the VDP memory was idle 0.000 % of the time (a DMA through every blank), so the strict point never came and every save or load there timed out after 1.25 s. The video-memory snapshot still happens in a following blank (a frozen CPU starts no new DMA); a load puts the VDP back mid-frame, one partial frame of picture. r2.13's two failure fixes and the diagnostics registers stay.
TEST LOG (hardware) 2026-09-27 11:44-12:00, Comix Zone from the paused Home menu: title screen save 185 ms, the first load 45 s later
        timed out (1,276 ms, the 68000 hold; the game went on, no wedge), the retry 185 ms, the same sequence again 159 / 211 ms;
        attract-mode gameplay save 185 ms, load 185 ms, the picture back exactly and the demo playing on. Saves 3/3, loads 4/5.
        Exit Core wrote Comix Zone (USA).ss, 262,144 bytes.


REBUILD 2026-09-27 13:53: package r2.16 (was r2.15); core-md branch md @ 32caaa89
Build:  Vivado 2023.2, xc7a100tcsg324-1, target gamebub_rev2; timing met, WNS 0.379 ns, WHS 0.033 ns
        Slice LUTs 40083 of 63400 (63.22%), Block RAM Tile 133.5 of 135 (98.89%), DSPs 32 of 240 (13.33%)
        md_rev2.bit sha256 0b88d2fcf2c44f2ab5cd542d5dbcd4f41532dffd4ee8ac6a3787e653ba3359db
Two small changes to the save-state engine, nothing for play: (1) the engine no longer probes the slot's header twice every 19.5 ms
        (it did that for MiSTer's menu; here the firmware's own scanner reads the headers), which had made about 32 cartridge reads a
        second a few clocks late; (2) when the 68000 capture handler gives up, the diagnostics register 0x0024 keeps the moment it gave
        up (which wait, which conditions were false) instead of the end of the request, for the rare load timeout seen with r2.15.
TEST LOG (hardware) 2026-09-27 14:12, Comix Zone: no slow cartridge answers over 57 s of play (0x101C = 0, max latency 11 clocks);
        save 185 ms and load 211 ms by hotkey; a few hundred late answers only during the load's own slot read (as before).


REBUILD 2026-09-27 17:54: package r2.17 (was r2.16); core-md branch md @ 37af8582
Build:  Vivado 2023.2, xc7a100tcsg324-1, target gamebub_rev2; timing met, WNS 0.206 ns, WHS 0.022 ns
        Slice LUTs 40065 of 63400 (63.19%), Block RAM Tile 133.5 of 135 (98.89%), DSPs 32 of 240 (13.33%)
        md_rev2.bit sha256 af6957ff5ef287b44e20399e9ab191f3c588721f28785871b91d89f1cea42b3e
r2.16 + one change: the machine stays paused (the focus pause's mechanism) while a Load State's first pass reads the slot to check its CRC (141 KB, about 2 ms), and runs again the moment the capture starts; during that pass a load no longer delays cartridge fetches (r2.16 measured a few hundred late answers there, 0x101C). Saves unchanged. Whole-system sim: rerunning with a stall watchdog (the first run froze after the save, cause open, the save path is r2.16's); my own console test on the handheld comes before any hand-over, r2.16 to fall back to.
TEST LOG (hardware): not yet run for this build.
TEST LOG (hardware) 2026-09-27 18:11-18:19, Comix Zone stage 1 (the owner's game, hands off): saves by hotkey with the game
        running FAILED 3 of 3 with the engine's 2.5 s watchdog (error 0x0A: the 68000 parked at 0xA14102, the VDP memory never
        idle during the hold; the same failure measured in Gunstar Heroes with r2.16, a limit of the engine, not of this build;
        the game went on each time). With the game paused by Start: a save DONE in 182 ms; then the first LOAD FAILED the same
        way, the picture turned solid gray, and every attempt after it (2 loads, 1 save) failed the same way: a load under
        r2.17's pause leaves the VDP's memory busy for good. The late-answer counter did stay at 2 through the loads (the pause
        did what it was meant to), but a load that fails is no improvement.
WITHDRAWN 2026-09-27 18:20: the card goes back to r2.16 (md_rev2.bit sha256 0b88d2fcf2c44f2ab5cd542d5dbcd4f41532dffd4ee8ac6a3787e653ba3359db,
        core.json r2.16). The few hundred late cartridge answers during a load's first pass under r2.16 are harmless and stay.
CORRECTION 2026-09-27 18:36 (r2.16 back on the card, same scene re-tested): r2.16 fails the paused stage-1 scene the same
        way (save, load, load, save: watchdog, the VDP memory never idle during the hold), so the r2.17 pause was not shown
        guilty; it stays withdrawn as unproven. r2.16's aftermath is worse in one way: after a failed hold there the game
        RESTARTS from the SEGA logo (seen after one failed save). Until the engine work: save and load at title screens
        and menus; mid-stage attempts in Comix Zone fail and can restart the game. Loads from the intro pass (183 / 417 ms).


REBUILD 2026-09-27 19:22: package r2.18 (was r2.16); core-md branch md @ 3a669dd3
Build:  Vivado 2023.2, xc7a100tcsg324-1, target gamebub_rev2; timing met, WNS 0.045 ns, WHS 0.023 ns
        Slice LUTs 40085 of 63400 (63.23%), Block RAM Tile 133.5 of 135 (98.89%), DSPs 32 of 240 (13.33%)
        md_rev2.bit sha256 ba0d990dbba45df65042ab8764389dfd15bf4cc5b99ee4910e07cadcf926fe61
r2.16 + diagnostics only, nothing for play: register 0x0030 shows the video chip's nine memory-idle conditions one by one (1 = busy) and 0x0034 keeps them from the end of the last request. Purpose: in busy scenes (Comix Zone stage 1, Gunstar Heroes) a save parks the 68000 and then waits until its watchdog for the video chip's memory to go idle; this register says which condition never comes, the first step of the engine work. Built while the owner was away; to install at a mount, then read with mdreg.py during a failing save.
TEST LOG (hardware): not yet run for this build.


REBUILD 2026-09-27 20:38: package r2.19 (was r2.18); core-md branch md @ acd93f0e
Build:  Vivado 2023.2, xc7a100tcsg324-1, target gamebub_rev2; timing met, WNS 0.127 ns, WHS 0.031 ns
        Slice LUTs 40030 of 63400 (63.14%), Block RAM Tile 133.5 of 135 (98.89%), DSPs 32 of 240 (13.33%)
        md_rev2.bit sha256 167808ad46377358a6a14ed7caf674ec76da371d2fb4244627aa61d953feeb3d
r2.18 + one change: the save-state engine's 'video memory idle' test no longer reads a toggle line's level as busy. That line flips once per VRAM data transfer, so after an odd number of transfers the video chip looked busy while idle, and with the 68000 held nothing flipped it back: the capture waited for its 2.5 s watchdog. This was the mid-stage 'Save failed' / 'Load failed' seen in Gunstar Heroes and Comix Zone (register 0x0030 of r2.18 named the line). Expected: saves and loads in busy scenes pass.
TEST LOG (hardware): not yet run for this build.
