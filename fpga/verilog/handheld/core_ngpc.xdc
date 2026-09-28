########################################
# SDRAM interface timing (Neo Geo Pocket Color core)
########################################
# Derived from core_pce.xdc (itself core_snes.xdc at 1x). The NGPC core's
# system clock is 49.152 MHz (20.345 ns), PLL output 0 = ngpc_gamebub_core's
# clk_sys = BurstSdramController clock: the SDRAM runs at 1x, the arbiter
# connects straight to the controller (docs/ngpc-port-design.md sections 2
# and 4). The chip's clock pin carries PLL output 1: the same clock delayed by
# 14 ns (`HandheldNgpc.SdramClockPhaseNs`, 248.4 degrees at this rate),
# forwarded through a BUFG and an OBUF. The controller launches commands,
# address and write data from plain flops on the rising edge of output 0 and
# captures read data on its FALLING edge (`readCaptureFalling`), in a register
# placed in the IOB below.
#
# Against core_pce.xdc (42.955 MHz, 23.28 ns, same 14 ns pin-clock delay):
#   create_generated_clock sdram_clk_pin ... CLKOUT1   kept (same PLL output index)
#   set_output_delay / set_input_delay                 kept (chip budget unchanged)
#   set_property IOB TRUE ... *sdram/dataIn_reg*        kept
# What the shorter period costs, from the PCE's routed report (outputs setup
# +5.7 / hold +7.6 ns, inputs setup +8.1 / hold +5.9 ns): the output setup
# check (launch at 0, pin edge at 14 ns) does not move; output hold loses
# 2.9 ns; the input capture edge (the next falling edge) comes 4.4 ns sooner.
# Every row stays positive by that arithmetic; check the sdram_clk_pin rows of
# the inter-clock table after every build.
# Naming this file relies on: the glue's PLL wrapper val is `pll` with the
# inner PLLE2_BASE instance `pll` (handheld_top/core/pll/pll), and the
# controller val is `sdram` with its capture register `dataIn`.
#
# Chip budget (PC133-class SDR SDRAM): input setup 2.0 ns, input hold 1.0 ns,
# clock-to-data 6.0 ns, data hold 2.5 ns.
create_generated_clock -name sdram_clk_pin -source [get_pins handheld_top/core/pll/pll/CLKOUT1] -divide_by 1 [get_ports sdram_clk]
set sdram_outputs [get_ports {sdram_a[*] sdram_bs[*] sdram_dq[*] sdram_cke[*] sdram_cs_n[*] sdram_cas_n sdram_ras_n sdram_we_n sdram_ldqm sdram_udqm}]
set_output_delay -clock sdram_clk_pin -max  2.0 $sdram_outputs
set_output_delay -clock sdram_clk_pin -min -1.0 $sdram_outputs
set_input_delay  -clock sdram_clk_pin -max  6.0 [get_ports {sdram_dq[*]}]
set_input_delay  -clock sdram_clk_pin -min  2.5 [get_ports {sdram_dq[*]}]
# The falling-edge capture register in the IOB: a fixed pad-to-flop path.
set_property IOB TRUE [get_cells -hier -filter {NAME =~ *sdram/dataIn_reg*}]

########################################
# TLCS-900/H multicycle paths
########################################
# The CPU advances on ce_t900, one clk_sys pulse in 16 at the fastest clock
# gear (never two in a row; the gears and the Game Bub `freeze` only widen the
# spacing). Upstream's NGPC.sdc multicycles the register-file write cone on
# MiSTer (Cyclone V grade 7) and the Analogue Pocket port extends the lists
# (openfpga-NGPC target/pocket/ngpc_pocket_timing.sdc); both keep the rule
# "a source that changes only on a tick, feeding storage that commits only on
# a tick, is a two-cycle path". On Artix-7 -1 that set still left 300 failing
# endpoints (build 3, WNS -1.9 ns after the Pocket set, measured on the routed
# checkpoint), in three more families, each covered below with its argument
# (the RTL is NGPC_MiSTer 238299f, vendored unchanged in rtl/t900):
#
# A. Tick registers -> tick commits, whole modules. t900_seq has exactly one
#    sequential always block: reset / restore_hold / `else if (ce)`, plus the
#    savestate write that is legal only while the core is parked (ce low). The
#    main always block of t900_biu is reset / `else if (ce)` with no other
#    branch. So every register of both changes only on a tick (or with the
#    core parked, when nothing commits), and every register of both plus the
#    register file (written only when rf_wr_en, a ce-qualified enable, or by the
#    parked savestate tap) commits only on a tick. This is upstream's argument
#    applied to all of them instead of the listed ones (the Pocket's list plus
#    op_r, clssz_r, bus_be_r, bus_req_r, bc_state, mstep, ... all failed).
#    t900_cpu's control snapshots (int_*_hold, dma_req_hold, pause_req_hold,
#    halt_release_hold) are sources too: upstream's own exception, they load on
#    ce_d one clk_sys after a tick and freeze until the next.
# B. Tick registers and control snapshots -> the bus output holds
#    (t900_biu g_bus_out_split *_h). The holds reload on every !ce cycle;
#    t900_biu documents that every consumer samples them on a ce edge, and
#    k2_soc_fabric presents a moved bus to the cartridge only after
#    SETTLE_CLKS = 5 clk_sys, "one past the observed maximum" settling of the
#    hold chain, which is decode hold (right from the third cycle after a tick)
#    -> bus hold (fourth). With two cycles here the bus holds are right from the
#    second (tick sources) and third (snapshots) cycle, inside that maximum,
#    and the decode hold -> bus hold paths that set the maximum stay single-cycle.
# C. Decode holds (dec_*_hold, q_byte_hold) -> tick commits. The holds reload on
#    every !ce cycle from cones whose inputs move only on ticks (the queue and
#    its read pointer, the sequencer state), so their value is final from the
#    third cycle after a tick until the next one (upstream's documented
#    invariant; ticks are 16 apart) and the commit at the tick sees a value that
#    has been stable for 13 cycles. The Pocket port left this family out as
#    unmeasured; here it fails by 1.1 ns without it.
# Not relaxed: anything into ra_hold / rb_hold / q_byte_hold / dec_*_hold,
# decode holds -> bus holds, and everything outside the CPU.
# XDC has no loops: the families are filtered cell collections. The names rely
# on the core instance path .../soc/cpu and on t900_cpu's generate labels.
set ngpc_tick_src [get_cells -hier -filter {(IS_SEQUENTIAL && (NAME =~ */soc/cpu/u_seq/* || (NAME =~ */soc/cpu/u_biu/* && NAME !~ */u_biu/g_bus_out_split.*))) || NAME =~ */soc/cpu/g_rf_read_split.int_*_hold_reg* || NAME =~ */soc/cpu/g_rf_read_split.dma_req_hold_reg* || NAME =~ */soc/cpu/g_rf_read_split.pause_req_hold_reg* || NAME =~ */soc/cpu/g_rf_read_split.halt_release_hold_reg*}]
set ngpc_tick_dst [get_cells -hier -filter {(IS_SEQUENTIAL && (NAME =~ */soc/cpu/u_seq/* || (NAME =~ */soc/cpu/u_biu/* && NAME !~ */u_biu/g_bus_out_split.*))) || NAME =~ */soc/cpu/u_regfile/regs_reg*}]
set ngpc_bus_holds [get_cells -hier -filter {NAME =~ */soc/cpu/u_biu/g_bus_out_split.*_h_reg*}]
set ngpc_dec_holds [get_cells -hier -filter {NAME =~ */soc/cpu/g_rf_read_split.dec_*_hold_reg* || NAME =~ */soc/cpu/g_rf_read_split.q_byte_hold_reg*}]
set_multicycle_path 2 -setup -from $ngpc_tick_src -to $ngpc_tick_dst
set_multicycle_path 1 -hold -from $ngpc_tick_src -to $ngpc_tick_dst
set_multicycle_path 2 -setup -from $ngpc_tick_src -to $ngpc_bus_holds
set_multicycle_path 1 -hold -from $ngpc_tick_src -to $ngpc_bus_holds
set_multicycle_path 2 -setup -from $ngpc_dec_holds -to $ngpc_tick_dst
set_multicycle_path 1 -hold -from $ngpc_dec_holds -to $ngpc_tick_dst
