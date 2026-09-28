########################################
# SDRAM interface timing (Mega Drive / Genesis core)
########################################
# Derived from core_pce.xdc. This core's system clock is the Mega Drive's
# master clock, 53.693175 MHz (18.624 ns), PLL output 0 = md_gamebub_core
# clk_sys = BurstSdramController clock, so the SDRAM runs at 1x
# (docs/md-port-design.md sections 1 and 4: no PipelineMemoryBurstCdc, the
# arbiter connects straight to the controller). The chip's clock pin carries
# PLL output 1: the same clock delayed by 11.93 ns
# (`HandheldMd.SdramClockPhaseNs`, 230.625 degrees). The controller launches
# commands, address and write data from plain flops on the rising edge of
# output 0 and captures read data on its FALLING edge (`readCaptureFalling`),
# in a register placed in the IOB below so the pin path does not move with the
# placement.
#
# Why 11.93 ns and not the PCE's 14: the period here is 4.7 ns shorter, and at
# 14 ns the output hold check (period - phase - chip hold) would be down to
# 3.6 ns. Against a PC133-class chip (input setup 2.0, input hold 1.0,
# clock-to-data 6.0, data hold 2.5 ns) 11.93 ns gives:
#   output setup   11.93 - 2.0                      =  9.9 ns
#   output hold    18.62 - 11.93 - 1.0              =  5.7 ns
#   input setup    27.94 - (11.93 + 6.0)            = 10.0 ns
#   input hold     (11.93 + 18.62 + 2.5) - 27.94    =  5.1 ns
# Check the sdram_clk_pin rows of the inter-clock table in the timing summary
# after every build.
#
# Naming this file relies on (as core_pce.xdc did): the glue's PLL wrapper val
# is `pll` and the wrapper's inner PLLE2_BASE instance is `pll` (path
# handheld_top/core/pll/pll), and the controller val is `sdram` with its
# capture register `dataIn`.
create_generated_clock -name sdram_clk_pin -source [get_pins handheld_top/core/pll/pll/CLKOUT1] -divide_by 1 [get_ports sdram_clk]
set sdram_outputs [get_ports {sdram_a[*] sdram_bs[*] sdram_dq[*] sdram_cke[*] sdram_cs_n[*] sdram_cas_n sdram_ras_n sdram_we_n sdram_ldqm sdram_udqm}]
set_output_delay -clock sdram_clk_pin -max  2.0 $sdram_outputs
set_output_delay -clock sdram_clk_pin -min -1.0 $sdram_outputs
set_input_delay  -clock sdram_clk_pin -max  6.0 [get_ports {sdram_dq[*]}]
set_input_delay  -clock sdram_clk_pin -min  2.5 [get_ports {sdram_dq[*]}]
# The falling-edge capture register in the IOB: a fixed pad-to-flop path.
set_property IOB TRUE [get_cells -hier -filter {NAME =~ *sdram/dataIn_reg*}]

########################################
# FX68K multicycle paths
########################################
# Upstream's own, from rtl/FX68K/fx68k.sdc (vendored beside the source),
# translated from Quartus's `-start -setup 2` / `-start -hold 1` pair to
# Vivado's canonical `2 -setup` / `1 -hold`: the setup check moves out by one
# period and the hold check stays where it was.
#
# Each is argued from the RTL and every one is conservative by a large factor.
# The 68000 runs on MCLK/7 (`M68K_CLKENp` / `M68K_CLKENn` in system.sv), so
# `enT1`..`enT4` are at least seven clocks apart; all four families run from a
# register that changes only on a phase enable into a register that commits
# only on one, so the real requirement is seven periods and upstream asks for
# two.
#
#  - `Ir` -> `microAddr`, `nanoAddr`: the instruction register is loaded at
#    `enT1` and the micro/nano addresses are registered from `nma` / `orgAddr`
#    on a phase enable; the microToNanoAddr translation between them is the
#    long cone.
#  - `nanoLatch` -> `alu/pswCcr`: the nano latch is loaded from the nano ROM on
#    a phase enable and the condition-code register commits at `enT3`/`enT4`.
#  - `alu/oper` -> `alu/pswCcr`: the ALU operation select is registered from
#    `aluOp` on a phase enable and feeds the same commit.
#
# Whether they are *needed* was measured rather than assumed. Build 1 ran with
# no exception at all (an `if` in an XDC file is silently rejected --
# Designutils 20-1307 -- so they were never applied) and closed at WNS +0.320
# overall; build 3, with the file cleaned up but still without them, gave the
# machine clock only +0.555 ns, while build 2 with them gave +2.473 ns. The
# critical path in every case is in jt12, not FX68K, so the difference is the
# router's effort budget rather than these paths themselves -- but four times
# the margin on a correct, upstream-argued constraint is worth having.
#
# Nothing else in the design is relaxed. Upstream's fifth exception
# (`sdram|dout*` -> `system|data*`) does not carry over: our ROM data comes
# from MdRomStore's own registers through the REQ/ACK handshake, not from a raw
# SDRAM output. Note that an XDC file is restricted Tcl -- `if` and `puts` are
# not among the commands it accepts -- so the collections are used directly and
# an empty one would fail silently; the FX68K cell counts at the time of
# writing are Ir 16, microAddr 8, nanoAddr 9, nanoLatch 66, oper 5, pswCcr 5.
set fx68k_ir       [get_cells -hier -filter {NAME =~ */M68K/Ir_reg[*]}]
set fx68k_uaddr    [get_cells -hier -filter {NAME =~ */M68K/microAddr_reg[*]}]
set fx68k_naddr    [get_cells -hier -filter {NAME =~ */M68K/nanoAddr_reg[*]}]
set fx68k_nanolat  [get_cells -hier -filter {NAME =~ */M68K/nanoLatch_reg[*]}]
set fx68k_oper     [get_cells -hier -filter {NAME =~ */M68K/excUnit/alu/oper_reg[*]}]
set fx68k_ccr      [get_cells -hier -filter {NAME =~ */M68K/excUnit/alu/pswCcr_reg[*]}]

set_multicycle_path 2 -setup -from $fx68k_ir -to $fx68k_uaddr
set_multicycle_path 1 -hold  -from $fx68k_ir -to $fx68k_uaddr
set_multicycle_path 2 -setup -from $fx68k_ir -to $fx68k_naddr
set_multicycle_path 1 -hold  -from $fx68k_ir -to $fx68k_naddr
set_multicycle_path 2 -setup -from $fx68k_nanolat -to $fx68k_ccr
set_multicycle_path 1 -hold  -from $fx68k_nanolat -to $fx68k_ccr
set_multicycle_path 2 -setup -from $fx68k_oper -to $fx68k_ccr
set_multicycle_path 1 -hold  -from $fx68k_oper -to $fx68k_ccr
