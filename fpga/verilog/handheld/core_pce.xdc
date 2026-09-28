########################################
# SDRAM interface timing (PC Engine core)
########################################
# Derived from core_snes.xdc. The SNES runs its SDRAM controller at 2x its
# 21.477 MHz system clock; the PC Engine core's system clock IS that rate:
# 42.955 MHz (23.28 ns), PLL output 0 = pce_top CLK = BurstSdramController
# clock, so the SDRAM runs at 1x (docs/pce-port-design.md sections 2-3: no
# PipelineMemoryBurstCdc, the arbiter connects straight to the controller).
# The chip's clock pin carries PLL output 1: the same clock delayed by 14 ns
# (`HandheldPce.SdramClockPhaseNs`, 216 degrees), forwarded through a BUFG
# and an OBUF. The controller launches commands, address and write data from
# plain flops on the rising edge of output 0, and captures read data on its
# FALLING edge (`readCaptureFalling` in HandheldPce), in a register placed
# in the IOB below so that the pin path does not move with the placement.
#
# Why the constraints carry over unchanged: the pin interface is the same
# electrical arrangement, at the same frequency and the same 14 ns pin-clock
# phase as the SNES's SDRAM domain; only the PLL output that feeds the pin
# changed index (the SNES's separate 2x output for the controller is gone,
# so the phase-shifted output moved from CLKOUT2 to CLKOUT1). The routed pin
# paths (2-13 ns outputs, 0.5-6 ns inputs, pin clock lagging the flop clock
# by 3-5.5 ns) do not depend on which core drives them, so the SNES's 2x
# analysis is exactly the PCE's 1x analysis. Line by line, against
# core_snes.xdc:
#   create_generated_clock sdram_clk_pin ... CLKOUT2   CHANGED -> CLKOUT1
#   set sdram_outputs [...]                            kept (same pins, same launch flops)
#   set_output_delay -max 2.0 / -min -1.0              kept (chip setup 2.0 / hold 1.0 ns)
#   set_input_delay  -max 6.0 / -min 2.5               kept (chip clock-to-data 6.0 / hold 2.5 ns)
#   set_property IOB TRUE ... *sdram/dataIn_reg*        kept (falling-edge capture register)
#   dropped: nothing. There is no separate system domain any more, so no
#   inter-domain constraint is needed either; the BUFGCE-gated core clock is
#   the same clock to the timer.
# Naming this file relies on (as core_snes.xdc did): the glue's PLL wrapper
# val is `pll` and the wrapper's inner PLLE2_BASE instance is `pll` (path
# handheld_top/core/pll/pll), and the controller val is `sdram` with its
# capture register `dataIn`.
#
# Chip budget (PC133-class SDR SDRAM): input setup 2.0 ns, input hold 1.0 ns,
# clock-to-data 6.0 ns, data hold 2.5 ns. Vivado's default edge relationship
# is the intended one for every path: an output launched on a rising edge is
# sampled at the next pin-clock edge (nominally 14 ns later), and read data
# launched on a pin-clock edge (with CAS latency 2 the chip drives a beat
# from the edge after the READ, to be valid at the second) is captured at
# the next falling flop edge (nominally 20.9 ns later); on the board the
# beats change within the first quarter cycle after the controller's rising
# edge. Check the sdram_clk_pin rows of the inter-clock table in the timing
# summary after every build.
create_generated_clock -name sdram_clk_pin -source [get_pins handheld_top/core/pll/pll/CLKOUT1] -divide_by 1 [get_ports sdram_clk]
set sdram_outputs [get_ports {sdram_a[*] sdram_bs[*] sdram_dq[*] sdram_cke[*] sdram_cs_n[*] sdram_cas_n sdram_ras_n sdram_we_n sdram_ldqm sdram_udqm}]
set_output_delay -clock sdram_clk_pin -max  2.0 $sdram_outputs
set_output_delay -clock sdram_clk_pin -min -1.0 $sdram_outputs
set_input_delay  -clock sdram_clk_pin -max  6.0 [get_ports {sdram_dq[*]}]
set_input_delay  -clock sdram_clk_pin -min  2.5 [get_ports {sdram_dq[*]}]
# The falling-edge capture register in the IOB: a fixed pad-to-flop path.
set_property IOB TRUE [get_cells -hier -filter {NAME =~ *sdram/dataIn_reg*}]
