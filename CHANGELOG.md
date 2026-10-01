# Changelog

Builds of the Mega Drive core for the rev2 Game Bub, newest first. Each build was run on a rev2 handheld before
it was kept. The full working history of the rev2 project, including the tests behind each line here, is in the
project's changelog.

## r2.20 (29 September 2026)
- HDMI pins for the production (rev4.1) Game Bub dock: `rev_2.xdc` moves each TMDS lane to the pair the dock reads
  it from, and the rev2 buffer block matches the dock's polarity. The handheld's own screen does not use these pins;
  HDMI output is untested until a dock is on hand. Nothing else changed.

## r2.19 (27 September 2026)
- Save states work mid-stage. The engine's "VDP memory idle" test compared the VRAM data-transfer request line
  with zero, but that line is a toggle: its level is the parity of the transfers so far. After an odd number of
  transfers the video chip read as busy while idle, and with the 68000 held nothing flipped it back, so the
  capture waited for its watchdog. The term now compares the line with its acknowledge. Comix Zone stage 1:
  three saves paused, three saves and a load running, all in about 0.2 s, where earlier builds passed 1 in 8.

## r2.18 (27 September)
- Diagnostics only: register 0x0030 shows the nine terms of the engine's memory-idle test one by one, 0x0034
  holds them from the end of the last request. This is what found the r2.19 fix.
- The bench can preload a States file, so a load puts the simulated machine into a scene saved on the handheld.

## r2.17 (27 September, withdrawn the same evening)
- Paused the machine during a load's first pass over the slot, to remove a few hundred late cartridge answers.
  No benefit shown; removed.

## r2.16 (27 September)
- The engine's periodic slot-header probe is off (the firmware's own scanner reads the headers): no late
  cartridge answers outside a state operation.
- Register 0x0024 holds the diagnostics word from the clock the capture handler gave up.

## r2.13 to r2.15 (27 September)
- The capture point: the fork captures only with the 68000 and the VDP quiet inside a vertical blank; after 78 ms
  without it the same quiet point outside the blank is accepted (r2.15).
- A request after a failed one no longer fails at once: the orchestrator read the handler's previous failure flag
  one clock before it was cleared (r2.13).
- A failed save no longer wipes the slot: the slot's size word was zeroed before the capture (r2.13).
- Diagnostics registers 0x0020 to 0x002C: the engine's live state, a held copy, and a clock counter over any
  combination of the safe-point terms (r2.12 to r2.14).

## r2.10 and r2.11 (27 September)
- keFEAR89's save-state engine (Genesis_MiSTer_Savestates R58) merged into the port: the slot channel to SDRAM,
  the States file (1 MiB, four slots of 256 KiB, MiSTer's `.ss` format), the slot scanner, and the Save State,
  Load State and State Slot entries in the in-game settings (r2.11).

## r2.9 (26 September)
- Two log counters: screen refreshes repeated and refreshed, for the screen driver's checks.

## r2.8 (26 September)
- The screen driver never cuts a refresh short: PAL games and 50 Hz sources are stable.

## r2.6 and r2.7 (25 September)
- Screen Filter setting: Sharp (the previous look) and Smooth (a bilinear filter for the 320-wide picture on the
  240-line screen).

## r2.5 and earlier (September 2026)
- The port itself: the archived MiSTer Genesis core on the Game Bub's FPGA framework, the cartridge in SDRAM
  through a pipelined store, battery saves, region detection from the header (Region setting: Auto, Japan, USA,
  Europe), the rev2 screen path, audio through the handheld's chain with a DC blocker (r2.5).
