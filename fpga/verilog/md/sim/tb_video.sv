// Game Bub Mega Drive port: MdVideoCapture against a synthetic VDP raster.
//
// None of the four test ROMs ever leaves H40, so the H32 path -- 256 active
// pixels centred in the 320-wide framebuffer with black borders, fed from a
// 32-slot delay of the VDP's colour -- would otherwise go untested. This bench
// drives the capture with a raster shaped exactly like `vdp.vhd`'s output port
// (a one-clock `ce` at the pixel rate, `hbl` low over H_DISP_WIDTH pixels,
// `vbl` low over V_DISP_HEIGHT lines, and the V counter advancing 15 pixels
// before the end of the active line, which is where the real VDP does it), and
// checks the framebuffer the framework's own address rule would build.
//
// Each pixel's colour encodes its column, so a shift of even one pixel shows.
//
// Run: xvlog -sv <elab>/MdVideoCapture.sv sim/tb_video.sv ; xelab tb_video
`timescale 1ps/1ps

module tb_video;
  reg clk = 1'b0;
  always #9312 clk = ~clk;
  reg reset = 1'b1;

  reg        ce = 1'b0;
  reg  [3:0] r = 4'd0, g = 4'd0, b = 4'd0;
  reg        hbl = 1'b1, vbl = 1'b1;
  reg  [1:0] resolution = 2'b01;

  wire       de, hblank, vblank, frame_pulse;
  wire [7:0] out_r, out_g, out_b;

  MdVideoCapture dut (
    .clock(clk), .reset(reset),
    .io_ce(ce), .io_r(r), .io_g(g), .io_b(b), .io_hbl(hbl), .io_vbl(vbl),
    .io_resolution(resolution),
    .io_dataEnable(de), .io_hblank(hblank), .io_vblank(vblank),
    .io_outR(out_r), .io_outG(out_g), .io_outB(out_b), .io_frame(frame_pulse)
  );

  // The framework's framebuffer address rule (HandheldTop).
  localparam WIDTH = 320, HEIGHT = 224;
  reg [23:0] fb [0:WIDTH*HEIGHT-1];
  integer fb_x = 0, fb_y = 0, pixels = 0, frames = 0, rows = 0;
  reg last_hblank = 1'b1, last_vblank = 1'b1;
  always @(posedge clk) begin
    last_hblank <= hblank;
    last_vblank <= vblank;
    if (de && fb_y < HEIGHT && fb_x < WIDTH) begin
      fb[fb_y * WIDTH + fb_x] <= {out_r, out_g, out_b};
      pixels = pixels + 1;
    end
    if (vblank) begin
      if (fb_y != 0) rows = fb_y;
      fb_x = 0; fb_y = 0;
    end else if (hblank) begin
      if (!last_hblank) begin fb_x = 0; fb_y = fb_y + 1; end
    end else if (de) begin
      fb_x = fb_x + 1;
    end
    if (vblank && !last_vblank) frames = frames + 1;
  end

  // ---------------------------------------------------- the raster driver
  // vdp.vhd, BORDER_EN low: hbl is low over H_DISP_WIDTH pixels of a line that
  // is H_TOTAL slots long, vbl is low over V_DISP_HEIGHT lines, and the V
  // counter advances at H_INT_POS -- 15 pixels before the end of the active
  // area -- so vbl changes in the middle of a line, not at its edge.
  task automatic pixel(input [3:0] value);
    ce = 1'b1; r = value; g = value; b = value;
    @(posedge clk); #100;
    ce = 1'b0;
    repeat (7) begin @(posedge clk); #100; end
  endtask

  integer active, total, line, i;
  task automatic run_frame(input integer height, input integer first_line);
    // `first_line` is the raster line the frame starts on; lines before
    // V_DISP_HEIGHT are active. The line on which vbl falls and the line on
    // which it rises both do it 15 pixels before the end of the active area.
    // Start one line early: vbl falls in the middle of the line before the
    // first active one, and rises in the middle of the last active one.
    for (line = first_line - 1; line < first_line + height + 1; line = line + 1) begin
      hbl = 1'b0;
      for (i = 0; i < active; i = i + 1) begin
        // The V counter advances 15 pixels before the end of the active area.
        if (i == active - 15) begin
          if (line == first_line - 1) vbl = 1'b0;
          if (line == first_line + height - 1) vbl = 1'b1;
        end
        pixel(i[3:0] ^ 4'(line));
      end
      hbl = 1'b1;
      for (i = 0; i < total - active; i = i + 1) pixel(4'd0);
    end
  endtask

  // The colour curve the capture applies (Genesis.sv's color_lut).
  function automatic [7:0] lut(input [3:0] v);
    case (v)
      0: lut = 8'd0;   1: lut = 8'd27;  2: lut = 8'd49;  3: lut = 8'd71;
      4: lut = 8'd87;  5: lut = 8'd103; 6: lut = 8'd119; 7: lut = 8'd130;
      8: lut = 8'd146; 9: lut = 8'd157; 10: lut = 8'd174; 11: lut = 8'd190;
      12: lut = 8'd206; 13: lut = 8'd228; 14: lut = 8'd255; default: lut = 8'd255;
    endcase
  endfunction

  integer errors = 0, x, y, border, checked;
  reg [7:0] want;

  task automatic check_frame(input integer width, input integer line0, input string what);
    border = (WIDTH - width) / 2;
    checked = 0;
    for (y = 0; y < HEIGHT; y = y + 1) begin
      for (x = 0; x < WIDTH; x = x + 1) begin
        if (x < border || x >= border + width) want = 8'd0;
        else want = lut((x - border) ^ (line0 + y));
        if (fb[y * WIDTH + x][7:0] !== want) begin
          errors = errors + 1;
          if (errors <= 8)
            $display("FAIL %s: (%0d,%0d) = %02x, expected %02x", what, x, y,
              fb[y * WIDTH + x][7:0], want);
        end
        checked = checked + 1;
      end
    end
    $display("%s: %0d pixels checked, %0d rows, %0d pixels written, %0d frames",
      what, checked, rows, pixels, frames);
  endtask

  initial begin
    for (i = 0; i < WIDTH*HEIGHT; i = i + 1) fb[i] = 24'hFFFFFF;
    repeat (4) @(posedge clk);
    #100 reset = 1'b0;

    // ---- H40: 320 active of a 420-slot line, 224 lines.
    resolution = 2'b01; active = 320; total = 420;
    run_frame(HEIGHT, 1);            // settle the capture's frame framing
    pixels = 0;
    run_frame(HEIGHT, 1);
    check_frame(320, 1, "H40 320x224");

    // ---- H32: 256 active of a 342-slot line. The picture must land at
    //      columns 32..287 with black either side.
    for (i = 0; i < WIDTH*HEIGHT; i = i + 1) fb[i] = 24'hFFFFFF;
    resolution = 2'b00; active = 256; total = 342;
    run_frame(HEIGHT, 1);
    pixels = 0;
    run_frame(HEIGHT, 1);
    check_frame(256, 1, "H32 256x224 centred");

    if (errors == 0) $display("tb_video: PASS");
    else $display("tb_video: %0d FAILURES", errors);
    $finish;
  end
endmodule
