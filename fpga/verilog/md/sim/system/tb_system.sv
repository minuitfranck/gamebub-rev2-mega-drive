// Game Bub Mega Drive port: xsim system testbench for HandheldMd (the Chisel
// glue as generated, the vendored machine, the real BurstSdramController on the
// system clock with the cycle-level SDRAM chip model sdram_model.sv, and the
// clock primitive stand-ins of sim_primitives.v).
//
// It drives the host side the way the firmware does (the file transfers into
// the memory windows in files.json order, the settings register, the framework
// commands), runs the game, captures the video the way HandheldTop's
// framebuffer writer does, and at the end reads the `.sav` back as the
// firmware saves it. This is where MdRomStore meets a real SDRAM: the store's
// statistics registers (0x1000-0x1020) say how well the window cache and the
// prefetch did, and how close the answers came to the 68000's budget.
//
// Files in the working directory (make_hex.py): cart_words.hex.
// Plusargs (no '=': xsim.bat splits arguments at '='):
//   +rom_bytes<n>           cartridge file size (cart.args)
//   +frames<n>              frames to run after CoreRun (default 10)
//   +dump_from<n> +dump_every<n>   write sysframe_NNNN.hex (RGB565, 320 x 224)
//   +press_start<frame> +press_a<frame> +press_b<frame>  hold for 20 frames
//   +config<hex>            register 0x0010 (default 0)
//   +sav1                   load a 64 KiB `.sav` of a known pattern (file id 1)
//   +savdump1               read the `.sav` back after the run into sav_out.hex
//   +ss1                    a States file (id 2) as the firmware sets one up when none is on the card
//   +ss_save_at<frame>      Save State (register 0x14 = 0x11, slot from 0x18) with the focus off, as the menu does
//   +ss_load_at<frame>      Load State (0x12) the same way; at the end the States file is read back
//                           and compare it with what was loaded
//   +focus_off_at<frame> +focus_off_len<frames>  NotifyFocus 0 for a while
//   +reset_at<frame>        the Reset action (register 0x0000 bit 0)
`timescale 1ps/1ps

module tb_system;
  reg clk_sys = 1'b0;
  reg locked = 1'b0;
  reg reset = 1'b1;
  always #9312 clk_sys = ~clk_sys;

  reg         host_enable = 1'b0, host_write = 1'b0, cmd_request = 1'b0;
  reg  [31:0] host_address = 32'd0, host_data = 32'd0;
  wire        host_done, cmd_busy, cmd_done, cmd_error;
  wire [31:0] host_read_data;
  // a b x y up down left right l r start select
  reg  [11:0] buttons = 12'd0;

  wire  [4:0] video_r, video_b;
  wire  [5:0] video_g;
  wire        video_de, video_vblank, video_hblank;
  wire [15:0] audio_left, audio_right;

  wire        sdram_cke, sdram_cs, sdram_ras, sdram_cas, sdram_we, sdram_dir;
  wire  [1:0] sdram_dqm, sdram_bank;
  wire [12:0] sdram_address;
  wire [15:0] sdram_to_chip, sdram_from_chip;

  HandheldMd dut (
    .clock(clk_sys), .reset(reset), .io_clocks_clockIn50M(1'b0),
    .io_clocks_clockOutSystem(), .io_clocks_clockOutDisplay(), .io_clocks_clockOutSpi(), .io_clocks_locked(),
    .io_video_data_r(video_r), .io_video_data_g(video_g), .io_video_data_b(video_b),
    .io_video_dataEnable(video_de), .io_video_vblank(video_vblank), .io_video_hblank(video_hblank),
    .io_audio_left(audio_left), .io_audio_right(audio_right),
    .io_host_mem_enable(host_enable), .io_host_mem_write(host_write), .io_host_mem_done(host_done),
    .io_host_mem_address(host_address), .io_host_mem_dataRead(host_read_data), .io_host_mem_dataWrite(host_data),
    .io_host_commandHost_request(cmd_request), .io_host_commandHost_busy(cmd_busy),
    .io_host_commandHost_done(cmd_done), .io_host_commandHost_error(cmd_error),
    .io_input_buttons_a(buttons[0]), .io_input_buttons_b(buttons[1]), .io_input_buttons_x(buttons[2]),
    .io_input_buttons_y(buttons[3]), .io_input_buttons_up(buttons[4]), .io_input_buttons_down(buttons[5]),
    .io_input_buttons_left(buttons[6]), .io_input_buttons_right(buttons[7]), .io_input_buttons_l(buttons[8]),
    .io_input_buttons_r(buttons[9]), .io_input_buttons_start(buttons[10]), .io_input_buttons_select(buttons[11]),
    .io_sdram_clock(), .io_sdram_cke(sdram_cke), .io_sdram_cs(sdram_cs), .io_sdram_ras(sdram_ras),
    .io_sdram_cas(sdram_cas), .io_sdram_we(sdram_we), .io_sdram_dqm(sdram_dqm), .io_sdram_bank(sdram_bank),
    .io_sdram_address(sdram_address), .io_sdram_dataIn(sdram_from_chip), .io_sdram_dataOut(sdram_to_chip),
    .io_sdram_dataDir(sdram_dir)
  );

  sdram_model chip (
    .clk(clk_sys), .cke(sdram_cke), .cs(sdram_cs), .ras(sdram_ras), .cas(sdram_cas), .we(sdram_we),
    .dqm(sdram_dqm), .bank(sdram_bank), .address(sdram_address), .data_from_controller(sdram_to_chip),
    .data_dir(sdram_dir), .data_to_controller(sdram_from_chip)
  );

  task automatic tick();
    @(posedge clk_sys);
    #1000;
  endtask

  task automatic host_access(input [31:0] address, input write, input [31:0] data, output [31:0] result);
    integer n;
    host_enable = 1'b1; host_write = write; host_address = address; host_data = data;
    n = 0;
    forever begin
      tick();
      n = n + 1;
      if (host_done) break;
      if (n > 200000) begin $display("HOST TIMEOUT at 0x%08x", address); $finish; end
    end
    result = host_read_data;
    tick();
    host_enable = 1'b0;
  endtask

  task automatic wr(input [31:0] address, input [31:0] data);
    reg [31:0] unused;
    host_access(address, 1'b1, data, unused);
  endtask

  task automatic rd(input [31:0] address, output [31:0] data);
    host_access(address, 1'b0, 32'd0, data);
  endtask

  task automatic command(input [15:0] cmd, input [31:0] arg1, input [31:0] arg2, output [31:0] result, output error);
    integer n;
    wr(32'hF0000000, cmd); wr(32'hF0000004, arg1); wr(32'hF0000008, arg2); wr(32'hF000000C, 32'd0);
    cmd_request = 1'b1;
    n = 0;
    forever begin
      tick();
      n = n + 1;
      if (cmd_done || cmd_error) break;
      if (n > 5000000) begin $display("COMMAND TIMEOUT %04x", cmd); $finish; end
    end
    error = cmd_error;
    cmd_request = 1'b0;
    tick(); tick();
    rd(32'hF0000000, result);
  endtask

  // --------------------------------------------------- 68000 wait states
  // The 68000 samples DTACK at enPhi2. Counted the same way as in tb_core, so
  // the two runs can be compared: this one has the real store and SDRAM.
  integer wait_edges = 0, bus_cycles = 0;
  always @(posedge clk_sys) begin
    if (dut.core.system.M68K_CLKENn && !dut.core.system.M68K_AS_N && dut.core.system.M68K_MBUS_DTACK_N)
      wait_edges = wait_edges + 1;
    if (dut.core.system.M68K_CLKENn && !dut.core.system.M68K_AS_N && !dut.core.system.M68K_MBUS_DTACK_N)
      bus_cycles = bus_cycles + 1;
  end

  // ------------------------------- framebuffer writer (HandheldTop's rule)
  localparam WIDTH = 320, HEIGHT = 224;
  reg [15:0] fb [0:WIDTH*HEIGHT-1];
  integer fb_x = 0, fb_y = 0, frame = 0, pixels = 0, rows = 0;
  integer frames_to_run, press_start, press_a, press_b, dump_from, dump_every, fd, x, y;
  integer focus_off_at, focus_off_len, reset_at;
  reg last_hblank = 1'b1, last_vblank = 1'b1;
  reg [8*64-1:0] name;
  reg running = 1'b0;
  reg [31:0] checksum;

  always @(posedge clk_sys) begin
    last_hblank <= video_hblank;
    last_vblank <= video_vblank;
    if (video_de && fb_y < HEIGHT && fb_x < WIDTH) begin
      fb[fb_y * WIDTH + fb_x] <= {video_r, video_g, video_b};
      pixels = pixels + 1;
    end
    if (video_vblank) begin
      if (fb_y != 0) rows = fb_y;
      fb_x = 0; fb_y = 0;
    end else if (video_hblank) begin
      if (!last_hblank) begin fb_x = 0; fb_y = fb_y + 1; end
    end else if (video_de) begin
      fb_x = fb_x + 1;
    end

    if (video_vblank && !last_vblank && running) begin
      checksum = 0;
      for (y = 0; y < WIDTH*HEIGHT; y = y + 1) checksum = (checksum * 31) ^ fb[y];
      if (dump_every > 0 && frame >= dump_from && ((frame - dump_from) % dump_every) == 0) begin
        $sformat(name, "sysframe_%04d.hex", frame);
        fd = $fopen(name, "w");
        for (y = 0; y < HEIGHT; y = y + 1) begin
          for (x = 0; x < WIDTH; x = x + 1) $fwrite(fd, "%04x ", fb[y * WIDTH + x]);
          $fwrite(fd, "\n");
        end
        $fclose(fd);
      end
      $display("frame %0d at %0t ps: %0d px rows %0d sum %08x | store txn %0d hit %0d rd %0d pf %0d maxlat %0d slow %0d | waits %0d",
        frame, $time, pixels, rows, checksum,
        dut.statTransactions, dut.statHits, dut.statSdramReads, dut.statPrefetches,
        dut.statMaxLatency, dut.statSlowAnswers, wait_edges);
      pixels = 0;
      frame = frame + 1;
      buttons[10] <= (press_start != 0 && frame >= press_start && frame < press_start + 20);
      buttons[0]  <= (press_a != 0 && frame >= press_a && frame < press_a + 20);
      buttons[1]  <= (press_b != 0 && frame >= press_b && frame < press_b + 20);
    end
  end

  integer i, j, rom_bytes, savload, savdump, mismatches;
  integer ssmode, ss_save_at, ss_load_at;
  integer ss_preload, ss_preload_words, ss_slot;
  reg [31:0] states_words [0:262143];
  reg [31:0] cart_words [0:2621439];
  reg [31:0] sav_in [0:16383];
  reg [31:0] result, status, config_value;
  reg error;

  // A `.sav` pattern that makes a byte-order mistake obvious: word n is
  // {n+3, n+2, n+1, n} as bytes, i.e. save byte k = k & 0xFF mixed with its
  // index, so every 32-bit word differs from its neighbours.
  function automatic [31:0] sav_pattern(input integer n);
    sav_pattern = {8'(4*n + 3), 8'(4*n + 2), 8'(4*n + 1), 8'(4*n)} ^ {8'hA5, 8'h5A, 8'hC3, 8'h3C};
  endfunction

  initial begin
    if (!$value$plusargs("rom_bytes%d", rom_bytes)) begin $display("need +rom_bytes"); $finish; end
    if (!$value$plusargs("frames%d", frames_to_run)) frames_to_run = 10;
    if (!$value$plusargs("press_start%d", press_start)) press_start = 0;
    if (!$value$plusargs("press_a%d", press_a)) press_a = 0;
    if (!$value$plusargs("press_b%d", press_b)) press_b = 0;
    if (!$value$plusargs("dump_from%d", dump_from)) dump_from = 0;
    if (!$value$plusargs("dump_every%d", dump_every)) dump_every = 0;
    if (!$value$plusargs("config%h", config_value)) config_value = 32'h0;
    if (!$value$plusargs("sav%d", savload)) savload = 0;
    if (!$value$plusargs("savdump%d", savdump)) savdump = 0;
    if (!$value$plusargs("focus_off_at%d", focus_off_at)) focus_off_at = 0;
    if (!$value$plusargs("focus_off_len%d", focus_off_len)) focus_off_len = 3;
    if (!$value$plusargs("reset_at%d", reset_at)) reset_at = 0;
    if (!$value$plusargs("ss%d", ssmode)) ssmode = 0;
    if (!$value$plusargs("ss_save_at%d", ss_save_at)) ss_save_at = 0;
    if (!$value$plusargs("ss_load_at%d", ss_load_at)) ss_load_at = 0;
    if (!$value$plusargs("preload%d", ss_preload)) ss_preload = 0;
    if (!$value$plusargs("pwords%d", ss_preload_words)) ss_preload_words = 0;
    if (!$value$plusargs("slot%d", ss_slot)) ss_slot = 0;
    $readmemh("cart_words.hex", cart_words);
    for (i = 0; i < WIDTH*HEIGHT; i = i + 1) fb[i] = 16'h0000;

    repeat (20) tick();
    locked = 1'b1;
    reset = 1'b0;
    repeat (20) tick();

    // files.json order: Cartridge (0), Save (1).
    command(16'h0300, 32'd0, 32'd0, result, error);
    $display("FILE_WRITE_START 0 at %0t ps (the memory clear runs here)", $time);
    for (i = 0; i < (rom_bytes + 3) / 4; i = i + 1) wr(32'h30000000 + i * 4, cart_words[i]);
    command(16'h0301, 32'd0, rom_bytes, result, error);
    $display("cartridge loaded at %0t ps (error %0d)", $time, error);
    rd(32'h00000004, result); $display("serial low  0x%08x", result);
    rd(32'h00000008, result); $display("serial high 0x%08x", result);
    rd(32'h0000001C, result); $display("quirks / region 0x%08x (bits 9:7 = E,U,J; 6:0 = schan,fmbusy,fifo,noram,eeprom,sram00,sram)", result);

    if (savload != 0) begin
      command(16'h0300, 32'd1, 32'd0, result, error);
      for (i = 0; i < 16384; i = i + 1) begin
        sav_in[i] = sav_pattern(i);
        wr(32'h40000000 + i * 4, sav_in[i]);
      end
      command(16'h0301, 32'd1, 32'h10000, result, error);
      rd(32'h00000100, status);
      $display(".sav loaded at %0t ps: status 0x%08x (bit 6 loaded)", $time, status);
    end

    if (ssmode != 0 && ss_preload != 0) begin
      // A States file with content (STATES=<.ss file> for run_system.sh, host words like the
      // cartridge): a load can then put the machine into a saved scene, e.g. a stage where a
      // save fails on the handheld, in a few frames instead of hours of play.
      $readmemh("states_words.hex", states_words);
      command(16'h0300, 32'd2, 32'd0, result, error);
      for (i = 0; i < ss_preload_words; i = i + 1) wr(32'h50000000 + i * 4, states_words[i]);
      command(16'h0301, 32'd2, ss_preload_words * 4, result, error);
      rd(32'h00000100, status);
      $display("States file preloaded (%0d bytes) at %0t ps: status 0x%08x (14:11 slots valid)", ss_preload_words * 4, $time, status);
    end else if (ssmode != 0) begin
      // No States file on the card: the firmware fills the 1 MiB area with 0xFF (here the first
      // 4 KiB of each slot, everything the engine and the scanner look at before a save) and
      // reports a size of 0, so every slot counts as empty.
      command(16'h0300, 32'd2, 32'd0, result, error);
      for (i = 0; i < 4; i = i + 1)
        for (j = 0; j < 1024; j = j + 1) wr(32'h50000000 + i * 32'h40000 + j * 4, 32'hFFFFFFFF);
      command(16'h0301, 32'd2, 32'd0, result, error);
      rd(32'h00000100, status);
      $display("States file (none) set up at %0t ps: status 0x%08x (6 states available, 14:11 slots valid)", $time, status);
    end

    wr(32'h00000010, config_value);
    command(16'h0102, 32'd0, 32'd0, result, error);
    $display("SETUP_COMPLETE: error %0d", error);
    if (error) $finish;
    for (i = 0; i < 100; i = i + 1) begin
      command(16'h0000, 32'd0, 32'd0, result, error);
      if (result == 3) break;
    end
    $display("GET_STATUS: %0d", result);
    command(16'h0100, 32'd0, 32'd0, result, error);
    command(16'h0200, 32'd1, 32'd0, result, error);
    running = 1'b1;
    $display("running at %0t ps", $time);

    if (focus_off_at != 0) begin
      wait (frame == focus_off_at);
      command(16'h0200, 32'd0, 32'd0, result, error);
      $display("focus off at frame %0d, %0t ps", frame, $time);
      repeat (focus_off_len * 896040) tick();
      command(16'h0200, 32'd1, 32'd0, result, error);
      $display("focus on at frame %0d, %0t ps", frame, $time);
    end

    if (reset_at != 0) begin
      wait (frame == reset_at);
      wr(32'h00000000, 32'd1);
      $display("Reset action at frame %0d, %0t ps", frame, $time);
      wait (frame == reset_at + 3);
      rd(32'h00000100, status);
      $display("3 frames after the reset: status 0x%08x, store transactions %0d", status, dut.statTransactions);
    end

    // The two state commands in frame order: a load before a save puts the machine into a saved
    // scene first (with +preload1), which is how a scene the handheld fails in is reached.
    if (ss_load_at != 0 && (ss_save_at == 0 || ss_load_at < ss_save_at)) begin
      wait (frame == ss_load_at);
      ss_command(32'h12, "LOAD");
      if (ss_save_at != 0) begin
        wait (frame == ss_save_at);
        ss_command(32'h11, "SAVE");
      end
    end else begin
      if (ss_save_at != 0) begin
        wait (frame == ss_save_at);
        ss_command(32'h11, "SAVE");
      end
      if (ss_load_at != 0) begin
        wait (frame == ss_load_at);
        ss_command(32'h12, "LOAD");
      end
    end

    wait (frame >= frames_to_run);
    // Exit Core as the firmware does it: halt, then save the non-read-only files.
    command(16'h0101, 32'd0, 32'd0, result, error);
    rd(32'h00000100, status); $display("status 0x%08x", status);
    for (i = 0; i < 9; i = i + 1) begin
      rd(32'h00001000 + i * 4, result);
      $display("stat 0x%04x = %0d", 16'h1000 + i * 4, result);
    end
    $display("68000 DTACK wait edges %0d of %0d bus ends", wait_edges, bus_cycles);
    command(16'h0302, 32'd1, 32'd0, result, error);
    $display("FILE_READ_START 1 -> %0d", result);
    if (savdump != 0 && result != 0) begin
      fd = $fopen("sav_out.hex", "w");
      mismatches = 0;
      for (i = 0; i < (result + 3) / 4; i = i + 1) begin
        rd(32'h40000000 + i * 4, status);
        $fwrite(fd, "%08x\n", status);
        if (savload != 0 && status !== sav_in[i]) begin
          mismatches = mismatches + 1;
          if (mismatches <= 5) $display("  .sav word %0d: read %08x, wrote %08x", i, status, sav_in[i]);
        end
      end
      $fclose(fd);
      $display("sav_out.hex written (%0d words), %0d words differ from what was loaded",
        (result + 3) / 4, mismatches);
    end
    command(16'h0303, 32'd1, 32'd0, result, error);
    if (ssmode != 0) begin
      command(16'h0302, 32'd2, 32'd0, result, error);
      $display("FILE_READ_START 2 -> %0d bytes (0x40000 = one slot used)", result);
      for (i = 0; i < 6; i = i + 1) begin
        rd(32'h50000000 + i * 4, status);
        $display("  slot 1 word %0d: %08x%s", i, status,
          i == 1 ? " (0x8A08 = the engine's body words)" : i == 3 ? " (0x52353853 = its magic)" : i == 4 ? " (0x22800 = the payload bytes)" : "");
      end
      command(16'h0303, 32'd2, 32'd0, result, error);
    end
    $display("done");
    $finish;
  end

  // Save State / Load State as the menu does it: the focus is off (the menu is open), the
  // action writes 0x14, and the firmware polls 0x100 until the busy bits (7, 9, 10) clear.
  // Stall watchdog (r2.17 sim): a machine that stops making frames (400 ms of simulated time
  // without one) is reported with the pause, the engine's busy and its diagnostics word, then the
  // run ends: a frozen machine would otherwise run to the host timeouts in silence. 400 ms, not
  // 100: the glue keeps status bit 7 (busy) up for 100 ms after the engine goes quiet, and with
  // the focus off (ss_command) the machine is paused, by design, until the poll sees it clear.
  reg in_ss_command = 0;
  time wd_last_frame_time;
  initial wd_last_frame_time = 0;
  always @(frame) wd_last_frame_time = $time;
  initial begin : stall_watchdog
    reg [31:0] wd_st;
    forever begin
      repeat (2000) tick();
      if (running && frame > 2 && ($time - wd_last_frame_time) > 64'd400_000_000_000) begin
        rd(32'h00000100, wd_st);
        $display("STALL: no frame since %0t (now %0t): status 0x%08x pause %b ss_busy %b ss_dbg 0x%08x ss_dbg2 0x%08x machine_reset %b loading %b in_ss_command %b",
          wd_last_frame_time, $time, wd_st, dut.core.pause, dut.core.ss_busy, dut.core.ss_dbg, dut.core.ss_dbg2, dut.core.machine_reset, dut.core.loading, in_ss_command);
        $finish;
      end
    end
  end

  task automatic ss_command(input [31:0] value, input string what);
    integer n, f0;
    reg [31:0] st;
    f0 = frame;
    in_ss_command = 1;
    command(16'h0200, 32'd0, 32'd0, result, error);
    wr(32'h00000018, ss_slot);
    wr(32'h00000014, value);
    rd(32'h00000100, st);
    $display("SS %s issued at frame %0d, %0t ps: status 0x%08x", what, frame, $time, st);
    n = 0;
    forever begin
      repeat (1000) tick();
      rd(32'h00000100, st);
      n = n + 1;
      if (n % 1000 == 0) $display("SS %s waiting at frame %0d: status 0x%08x ss_dbg 0x%08x ss_dbg2 0x%08x", what, frame, st, dut.core.ss_dbg, dut.core.ss_dbg2);
      if ((st & 32'h680) == 0 && n > 2) break;
      if (n > 20000) begin $display("SS %s: TIMEOUT waiting for the engine, status 0x%08x", what, st); break; end
    end
    $display("SS %s finished at frame %0d (%0d frames), %0t ps: status 0x%08x: done %0d failed %0d slots valid %b engine error %0d capture error %0d",
      what, frame, frame - f0, $time, st, st[8], st[15], st[14:11], st[31:24], dut.core.ss_capture_error);
    command(16'h0200, 32'd1, 32'd0, result, error);
    $display("SS %s: focus back on at frame %0d, %0t ps: status 0x%08x", what, frame, $time, st);
    in_ss_command = 0;
  endtask
endmodule
