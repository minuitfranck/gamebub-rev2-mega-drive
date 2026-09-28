// Behavioral stand-ins for the Xilinx clocking primitives HandheldNgpc
// instantiates, for the xsim system testbench only (tb_system.sv). Every
// clock the glue uses is the testbench's system clock: the machine, the glue
// and the SDRAM controller share it on the board too (1x), and the SDRAM chip
// model acts on its falling edge in place of the phase-shifted pin clock.
`timescale 1ps/1ps

module BUFG (input I, output O);
  assign O = I;
endmodule

module MMCME2_BASE #(
  parameter real CLKFBOUT_MULT_F = 1.0, parameter real CLKIN1_PERIOD = 20.0,
  parameter real CLKOUT0_DIVIDE_F = 1.0, parameter real CLKOUT0_DUTY_CYCLE = 0.5, parameter real CLKOUT0_PHASE = 0.0,
  parameter integer CLKOUT1_DIVIDE = 1, parameter real CLKOUT1_DUTY_CYCLE = 0.5, parameter real CLKOUT1_PHASE = 0.0,
  parameter integer DIVCLK_DIVIDE = 1
) (
  input CLKIN1, input CLKFBIN, input RST, input PWRDWN,
  output CLKOUT0, output CLKOUT0B, output CLKOUT1, output CLKOUT1B, output CLKOUT2, output CLKOUT2B,
  output CLKOUT3, output CLKOUT3B, output CLKOUT4, output CLKOUT5, output CLKOUT6,
  output CLKFBOUT, output CLKFBOUTB, output LOCKED
);
  assign CLKOUT0 = tb_system.clk_sys;
  assign CLKOUT1 = 1'b0;
  assign {CLKOUT0B, CLKOUT1B, CLKOUT2, CLKOUT2B, CLKOUT3, CLKOUT3B, CLKOUT4, CLKOUT5, CLKOUT6, CLKFBOUT, CLKFBOUTB} = 11'd0;
  assign LOCKED = tb_system.locked;
endmodule

module PLLE2_BASE #(
  parameter integer CLKFBOUT_MULT = 1, parameter real CLKIN1_PERIOD = 10.0,
  parameter integer CLKOUT0_DIVIDE = 1, parameter real CLKOUT0_DUTY_CYCLE = 0.5, parameter real CLKOUT0_PHASE = 0.0,
  parameter integer CLKOUT1_DIVIDE = 1, parameter real CLKOUT1_DUTY_CYCLE = 0.5, parameter real CLKOUT1_PHASE = 0.0,
  parameter integer CLKOUT2_DIVIDE = 1, parameter real CLKOUT2_DUTY_CYCLE = 0.5, parameter real CLKOUT2_PHASE = 0.0,
  parameter integer DIVCLK_DIVIDE = 1
) (
  input CLKIN1, input CLKFBIN, input RST, input PWRDWN,
  output CLKOUT0, output CLKOUT1, output CLKOUT2, output CLKOUT3, output CLKOUT4, output CLKOUT5,
  output CLKFBOUT, output LOCKED
);
  assign CLKOUT0 = tb_system.clk_sys;
  assign CLKOUT1 = tb_system.clk_sys;
  assign {CLKOUT2, CLKOUT3, CLKOUT4, CLKOUT5, CLKFBOUT} = 5'd0;
  assign LOCKED = tb_system.locked;
endmodule
