// Game Bub Mega Drive port: the cartridge save RAM's byte order.
//
// `system.sv` instantiates the save RAM as `dpram_dif #(16,8,15,16)`: port A is
// the 68000's byte-wide view (one byte per `MBUS_A[16:1]`) and port B is the
// 16-bit host view that the `.sav` file is streamed through. The whole `.sav`
// format rests on one property:
//
//     port A byte n  <->  port B word n/2, bits 7:0 for even n, 15:8 for odd n
//
// which is `altsyncram`'s mixed-width convention and is what makes our file
// byte-for-byte a MiSTer `.sav`. `rtl/xilinx/bram.vhd` reimplements that shape
// from an even-byte and an odd-byte bank, so it is worth proving rather than
// asserting. This bench writes through one port and reads through the other,
// both ways.
//
// Run: xvhdl rtl/xilinx/bram.vhd ; xvlog -sv sim/tb_bsram.sv ; xelab tb_bsram
`timescale 1ps/1ps

module tb_bsram;
  reg clk = 1'b0;
  always #9312 clk = ~clk;

  reg  [15:0] addr_a = 16'd0;
  reg   [7:0] data_a = 8'd0;
  reg         wren_a = 1'b0;
  wire  [7:0] q_a;
  reg  [14:0] addr_b = 15'd0;
  reg  [15:0] data_b = 16'd0;
  reg         wren_b = 1'b0;
  wire [15:0] q_b;

  dpram_dif #(16, 8, 15, 16) sram (
    .clock(clk),
    .address_a(addr_a), .data_a(data_a), .enable_a(1'b1), .wren_a(wren_a), .q_a(q_a), .cs_a(1'b1),
    .address_b(addr_b), .data_b(data_b), .enable_b(1'b1), .wren_b(wren_b), .q_b(q_b), .cs_b(1'b1)
  );

  task automatic tick(); @(posedge clk); #1000; endtask

  task automatic write_a(input [15:0] a, input [7:0] d);
    addr_a = a; data_a = d; wren_a = 1'b1;
    tick();
    wren_a = 1'b0;
  endtask

  task automatic read_a(input [15:0] a, output [7:0] d);
    addr_a = a;
    tick();
    tick();
    d = q_a;
  endtask

  task automatic write_b(input [14:0] a, input [15:0] d);
    addr_b = a; data_b = d; wren_b = 1'b1;
    tick();
    wren_b = 1'b0;
  endtask

  task automatic read_b(input [14:0] a, output [15:0] d);
    addr_b = a;
    tick();
    tick();
    d = q_b;
  endtask

  integer errors = 0, i;
  reg  [7:0] got8;
  reg [15:0] got16;

  task automatic check8(input [15:0] a, input [7:0] want, input string what);
    reg [7:0] got;
    read_a(a, got);
    if (got !== want) begin
      errors = errors + 1;
      $display("FAIL %s: port A byte %0d = %02x, expected %02x", what, a, got, want);
    end
  endtask

  task automatic check16(input [14:0] a, input [15:0] want, input string what);
    reg [15:0] got;
    read_b(a, got);
    if (got !== want) begin
      errors = errors + 1;
      $display("FAIL %s: port B word %0d = %04x, expected %04x", what, a, got, want);
    end
  endtask

  initial begin
    tick();

    // 1. Written as bytes, read as words. Byte 2n must be the LOW half.
    for (i = 0; i < 8; i = i + 1) write_a(i[15:0], 8'hA0 + i[7:0]);
    for (i = 0; i < 4; i = i + 1)
      check16(i[14:0], {8'hA0 + 8'(2*i + 1), 8'hA0 + 8'(2*i)}, "bytes then words");

    // 2. Written as words, read as bytes.
    for (i = 0; i < 4; i = i + 1) write_b(15'(100 + i), {8'(8'h50 + 2*i + 1), 8'(8'h50 + 2*i)});
    for (i = 0; i < 8; i = i + 1)
      check8(16'(200 + i), 8'(8'h50 + i), "words then bytes");

    // 3. The top of the 64 KiB, where a wrong address width would show.
    write_a(16'hFFFE, 8'h12);
    write_a(16'hFFFF, 8'h34);
    check16(15'h7FFF, 16'h3412, "top word");
    write_b(15'h7FFE, 16'hBEEF);
    check8(16'hFFFC, 8'hEF, "top-1 even byte");
    check8(16'hFFFD, 8'hBE, "top-1 odd byte");

    // 4. The two banks are independent: an even write must not disturb its odd
    //    neighbour, which is the mistake an even/odd split invites.
    write_a(16'd40, 8'h11);
    write_a(16'd41, 8'h22);
    write_a(16'd40, 8'h99);
    check8(16'd41, 8'h22, "odd byte survives an even write");
    check16(15'd20, 16'h2299, "pair after the rewrite");

    if (errors == 0) $display("tb_bsram: PASS, the save RAM byte order is the MiSTer .sav order");
    else $display("tb_bsram: %0d FAILURES", errors);
    $finish;
  end
endmodule
