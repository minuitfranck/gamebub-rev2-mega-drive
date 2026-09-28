// Game Bub Mega Drive port: core-only xsim testbench for md_gamebub_core.
//
// The machine with a behavioural cartridge ROM store on the upstream toggle
// handshake (a configurable answer latency, so the design's budget of about
// eleven clocks can be exercised -- docs/md-port-design.md section 4), the real
// MdVideoCapture from the Chisel output, the framework's own framebuffer
// address rule, and frame dumps.
//
// Files in the working directory (make_hex.py): cart16.hex.
// Plusargs (no '=', xsim.bat splits at '='):
//   +rom_bytes<n> +rom_words<n>    the cartridge file (cart.args)
//   +frames<n>                     frames to run (default 30)
//   +latency<n>                    store answer delay in clocks (default 8);
//                                  +latency_rnd1 = random 1..latency
//   +dump_from<n> +dump_every<n>   write frame_NNNN.hex (RGB888, 320 x 224)
//   +press_start<frame>            hold Start 20 frames from this frame
//   +press_a<frame> +press_b<frame> +press_c<frame>
//   +maxclk<n>                     stop after n million clocks (default 4000)
//   +pause_at<frame> +pause_len<clocks>
//   +pal1 +export0                 region straps (default NTSC, export)
//   +ahist_from<frame> +ahist_frames<n>  histogram of 68000 bus addresses
`timescale 1ps/1ps

module tb_core;
  // 53.693175 MHz: half period 9312.14 ps. xsim's time unit here is 1 ps, so
  // the period is 18624 ps (53.6941 MHz, 20 ppm fast -- irrelevant).
  reg clk = 1'b0;
  always #9312 clk = ~clk;

  reg        loading = 1'b1;
  reg        machine_reset = 1'b1;
  reg        ram_init = 1'b0;
  reg        pause = 1'b0;
  reg        pal = 1'b0;
  reg        region_export = 1'b1;
  reg        pad_3button = 1'b0;
  reg [11:0] joy = 12'd0;
  reg [23:0] rom_size = 24'd0;

  wire [23:0] rom_addr;
  wire [15:0] rom_wdata;
  wire        rom_we, rom_req;
  wire  [1:0] rom_be;
  reg  [15:0] rom_data = 16'hFFFF;
  reg         rom_ack = 1'b0;

  wire [15:0] bram_do;
  wire        bram_change;
  wire        video_ce, video_hbl, video_vbl;
  wire  [3:0] video_r, video_g, video_b;
  wire  [1:0] video_resolution;
  wire [15:0] audio_l, audio_r;
  wire [23:0] dbg_m68k_a;

  md_gamebub_core dut (
    .clk_sys(clk),
    .loading(loading), .machine_reset(machine_reset), .ram_init(ram_init), .pause(pause),
    .pal(pal), .region_export(region_export), .pad_3button(pad_3button),
    .sram_quirk(1'b0), .sram00_quirk(1'b0), .eeprom_quirk(1'b0), .noram_quirk(1'b0),
    .fifo_quirk(1'b0), .fmbusy_quirk(1'b0), .schan_quirk(1'b0),
    .lpf_mode(2'b00), .enable_fm(1'b1), .enable_psg(1'b1), .en_hifi_pcm(1'b0),
    .ladder(1'b1), .obj_limit_high(1'b0), .border(1'b0), .cram_dots(1'b0),
    .rom_size(rom_size), .rom_addr(rom_addr), .rom_data(rom_data), .rom_wdata(rom_wdata),
    .rom_we(rom_we), .rom_be(rom_be), .rom_req(rom_req), .rom_ack(rom_ack),
    .bram_a(15'd0), .bram_di(16'd0), .bram_do(bram_do), .bram_we(1'b0), .bram_change(bram_change),
    .joy_1(joy),
    .video_ce(video_ce), .video_r(video_r), .video_g(video_g), .video_b(video_b),
    .video_hbl(video_hbl), .video_vbl(video_vbl), .video_resolution(video_resolution),
    .audio_l(audio_l), .audio_r(audio_r),
    .dbg_m68k_a(dbg_m68k_a)
  );

  // ------------------------------------------------ behavioural ROM store
  // Upstream's contract: a transaction is outstanding while rom_req != rom_ack,
  // and the answer and the acknowledge move on the same edge.
  reg [15:0] cart [0:5242879];   // 10 MiB of 16-bit words
  integer latency, latency_rnd, delay = 0;
  integer reads = 0, writes = 0;
  reg busy = 1'b0;

  always @(posedge clk) begin
    if (!busy) begin
      if (!machine_reset && rom_req !== rom_ack) begin
        busy <= 1'b1;
        delay <= latency_rnd ? (($urandom_range(latency - 1, 0)) + 1) : latency;
      end
    end else if (delay > 1) begin
      delay <= delay - 1;
    end else begin
      if (rom_we) begin
        if (rom_be[1]) cart[rom_addr][15:8] <= rom_wdata[15:8];
        if (rom_be[0]) cart[rom_addr][7:0] <= rom_wdata[7:0];
        writes = writes + 1;
        rom_data <= cart[rom_addr];
      end else begin
        reads = reads + 1;
        rom_data <= cart[rom_addr];
      end
      rom_ack <= rom_req;
      busy <= 1'b0;
    end
  end

  // ----------------------------------------------------- 68000 wait states
  // The 68000 samples DTACK at enPhi2 (M68K_CLKENn). Every such edge with the
  // address strobe low and no DTACK yet is a wait state (including the two the
  // bus always needs), so the number is only meaningful compared between runs.
  integer wait_edges = 0, wait_edges_frame = 0, bus_cycles = 0;
  always @(posedge clk) begin
    if (dut.system.M68K_CLKENn && !dut.system.M68K_AS_N && dut.system.M68K_MBUS_DTACK_N) begin
      wait_edges = wait_edges + 1;
      wait_edges_frame = wait_edges_frame + 1;
    end
    if (dut.system.M68K_CLKENn && !dut.system.M68K_AS_N && !dut.system.M68K_MBUS_DTACK_N)
      bus_cycles = bus_cycles + 1;
  end

  // ------------------------------------------------------------- audio
  integer audio_moves = 0, audio_moves_frame = 0;
  integer audio_min = 0, audio_max = 0;
  reg signed [15:0] audio_prev = 16'sd0;
  // The chain's own stages, so a silent DAC can be told apart from a silent
  // YM2612: FM_left is jt12's output, PSG_SND the SN76489's, PRE_LPF_L the mix
  // before genesis_lpf, and audio_l the DAC the glue resamples.
  integer fm_moves = 0, psg_moves = 0, mix_moves = 0;
  integer fm_min = 0, fm_max = 0, psg_min = 0, psg_max = 0;
  reg signed [15:0] fm_prev = 16'sd0, mix_prev = 16'sd0;
  reg signed [10:0] psg_prev = 11'sd0;
  always @(posedge clk) begin
    if (dut.system.FM_left < fm_min) fm_min = dut.system.FM_left;
    if (dut.system.FM_left > fm_max) fm_max = dut.system.FM_left;
    if (dut.system.PSG_SND < psg_min) psg_min = dut.system.PSG_SND;
    if (dut.system.PSG_SND > psg_max) psg_max = dut.system.PSG_SND;
    if (dut.system.FM_left !== fm_prev) begin fm_moves = fm_moves + 1; fm_prev = dut.system.FM_left; end
    if (dut.system.PSG_SND !== psg_prev) begin psg_moves = psg_moves + 1; psg_prev = dut.system.PSG_SND; end
    if (dut.system.PRE_LPF_L !== mix_prev) begin mix_moves = mix_moves + 1; mix_prev = dut.system.PRE_LPF_L; end
    if ($signed(audio_l) < audio_min) audio_min = $signed(audio_l);
    if ($signed(audio_l) > audio_max) audio_max = $signed(audio_l);
    if (audio_l !== audio_prev) begin
      audio_moves = audio_moves + 1;
      audio_moves_frame = audio_moves_frame + 1;
      audio_prev = audio_l;
    end
  end

  // ------------------------------------------ the real video capture module
  wire        cap_de, cap_hblank, cap_vblank, cap_frame;
  wire  [7:0] cap_r, cap_g, cap_b;
  reg         cap_reset = 1'b1;

  MdVideoCapture capture (
    .clock(clk), .reset(cap_reset),
    .io_ce(video_ce), .io_r(video_r), .io_g(video_g), .io_b(video_b),
    .io_hbl(video_hbl), .io_vbl(video_vbl), .io_resolution(video_resolution),
    .io_dataEnable(cap_de), .io_hblank(cap_hblank), .io_vblank(cap_vblank),
    .io_outR(cap_r), .io_outG(cap_g), .io_outB(cap_b), .io_frame(cap_frame)
  );

  // -------------------------- the framework's framebuffer address rule
  // HandheldTop: X advances on dataEnable while neither blank is high, the
  // rising edge of hblank resets X and advances Y, and vblank resets both.
  localparam WIDTH = 320, HEIGHT = 224;
  reg [23:0] fb [0:WIDTH*HEIGHT-1];
  integer fb_x = 0, fb_y = 0, frame = 0, pixels = 0, rows = 0;
  reg last_hblank = 1'b1, last_vblank = 1'b1;
  integer frames_to_run, dump_from, dump_every, fd, x, y;
  integer press_start, press_a, press_b, press_c, maxclk, clocks = 0;
  integer pause_at, pause_len;
  reg [8*64-1:0] name;
  reg [31:0] checksum;

  always @(posedge clk) begin
    clocks = clocks + 1;
    last_hblank <= cap_hblank;
    last_vblank <= cap_vblank;
    if (cap_de && fb_y < HEIGHT && fb_x < WIDTH) begin
      fb[fb_y * WIDTH + fb_x] <= {cap_r, cap_g, cap_b};
      pixels = pixels + 1;
    end
    if (cap_vblank) begin
      if (fb_y != 0) rows = fb_y;
      fb_x = 0; fb_y = 0;
    end else if (cap_hblank) begin
      if (!last_hblank) begin fb_x = 0; fb_y = fb_y + 1; end
    end else if (cap_de) begin
      fb_x = fb_x + 1;
    end

    if (cap_vblank && !last_vblank) begin
      checksum = 0;
      for (y = 0; y < WIDTH*HEIGHT; y = y + 1) checksum = (checksum * 31) ^ fb[y];
      if (dump_every > 0 && frame >= dump_from && ((frame - dump_from) % dump_every) == 0) begin
        $sformat(name, "frame_%04d.hex", frame);
        fd = $fopen(name, "w");
        for (y = 0; y < HEIGHT; y = y + 1) begin
          for (x = 0; x < WIDTH; x = x + 1) $fwrite(fd, "%06x ", fb[y * WIDTH + x]);
          $fwrite(fd, "\n");
        end
        $fclose(fd);
      end
      $display("frame %0d at %0t ps (%0d M clk): %0d px rows %0d sum %08x | res %b a %06x | rom rd %0d | waits %0d | audio %0d | vdp wr %0d (%0d) io %0d zbus %0d fm %0d (%0d) psg %0d sram %0d | z80 rst %b brq %b | fm/psg/mix %0d/%0d/%0d",
        frame, $time, clocks / 1000000, pixels, rows, checksum, video_resolution, dbg_m68k_a,
        reads, wait_edges_frame, audio_moves_frame,
        vdp_wr, vdp_wr_frame, io_acc, zbus_acc, fm_wr, fm_wr_frame, psg_wr, sram_acc,
        dut.system.Z80_RESET_N, dut.system.Z80_BUSRQ_N, fm_moves, psg_moves, mix_moves);
      vdp_wr_frame = 0;
      fm_wr_frame = 0;
      audio_moves_frame = 0;
      wait_edges_frame = 0;
      pixels = 0;
      frame = frame + 1;
      joy[7] <= (press_start != 0 && frame >= press_start && frame < press_start + 20);
      joy[4] <= (press_a != 0 && frame >= press_a && frame < press_a + 20);
      joy[5] <= (press_b != 0 && frame >= press_b && frame < press_b + 20);
      joy[6] <= (press_c != 0 && frame >= press_c && frame < press_c + 20);
    end
  end

  // +pause_at<frame> +pause_len<clocks>: the focus pause (upstream's PAUSE_EN),
  // driven from its own process so it cannot block the frame capture -- the
  // measurement is what the machine does, not what the bench manages to see.
  // The VDP is NOT paused on purpose, so the display keeps refreshing with a
  // frozen picture; what must stop is the 68000, the Z80 and the sound chips.
  integer pause_rom_before = 0, pause_rom_during = 0, pause_vdp_before = 0, pause_vdp_during = 0;
  initial begin
    wait (pause_at != 0);
    wait (frame == pause_at);
    @(posedge clk); #100;
    pause_rom_before = reads;
    pause_vdp_before = vdp_wr;
    pause = 1'b1;
    repeat (pause_len) @(posedge clk);
    #100;
    pause_rom_during = reads - pause_rom_before;
    pause_vdp_during = vdp_wr - pause_vdp_before;
    pause = 1'b0;
    $display("PAUSE: held for %0d clocks from frame %0d; during it the machine did %0d cartridge reads and %0d VDP writes (both must be 0)",
      pause_len, pause_at, pause_rom_during, pause_vdp_during);
  end

  // +ahist_from<frame> +ahist_frames<n>: where the 68000 spends its bus cycles.
  integer ahist_from, ahist_frames, a_count [int unsigned];
  integer a_total = 0;
  reg as_prev = 1'b1;
  always @(posedge clk) begin
    as_prev <= dut.system.M68K_AS_N;
    if (ahist_frames != 0 && frame >= ahist_from && frame < ahist_from + ahist_frames &&
        as_prev && !dut.system.M68K_AS_N) begin
      if (a_count.exists(dbg_m68k_a)) a_count[dbg_m68k_a] = a_count[dbg_m68k_a] + 1;
      else a_count[dbg_m68k_a] = 1;
      a_total = a_total + 1;
    end
  end
  task automatic print_a_histogram();
    int unsigned keys[$];
    int unsigned k;
    integer n, best_i, j;
    foreach (a_count[k]) keys.push_back(k);
    $display("bus address histogram over frames %0d..%0d: %0d cycles, %0d addresses",
      ahist_from, ahist_from + ahist_frames - 1, a_total, keys.size());
    for (n = 0; n < 24 && keys.size() > 0; n = n + 1) begin
      best_i = 0;
      for (j = 1; j < keys.size(); j = j + 1) if (a_count[keys[j]] > a_count[keys[best_i]]) best_i = j;
      $display("  %06x: %0d", keys[best_i], a_count[keys[best_i]]);
      keys.delete(best_i);
    end
  endtask
  always @(posedge clk) begin
    if (ahist_frames != 0 && frame == ahist_from + ahist_frames && a_total != 0) begin
      print_a_histogram();
      a_total = 0;
    end
  end

  // ---------------------------------------------- peripheral activity
  // Where the machine is actually spending its bus cycles, so a game that
  // looks stuck can be told apart from one that is just still booting.
  integer vdp_rd = 0, vdp_wr = 0, io_acc = 0, zbus_acc = 0, fm_wr = 0, psg_wr = 0, sram_acc = 0;
  integer vdp_wr_frame = 0, fm_wr_frame = 0;
  reg vdp_sel_prev = 1'b0, io_sel_prev = 1'b0, zbus_sel_prev = 1'b0, sram_sel_prev = 1'b0;
  always @(posedge clk) begin
    vdp_sel_prev <= dut.system.VDP_SEL;
    io_sel_prev <= dut.system.IO_SEL;
    zbus_sel_prev <= dut.system.ZBUS_SEL;
    sram_sel_prev <= dut.system.SRAM_SEL;
    if (dut.system.VDP_SEL && !vdp_sel_prev) begin
      if (dut.system.MBUS_RNW) vdp_rd = vdp_rd + 1;
      else begin vdp_wr = vdp_wr + 1; vdp_wr_frame = vdp_wr_frame + 1; end
    end
    if (dut.system.IO_SEL && !io_sel_prev) io_acc = io_acc + 1;
    if (dut.system.ZBUS_SEL && !zbus_sel_prev) zbus_acc = zbus_acc + 1;
    if (dut.system.SRAM_SEL && !sram_sel_prev) sram_acc = sram_acc + 1;
    if (dut.system.FM_SEL && dut.system.ZBUS_WE) begin fm_wr = fm_wr + 1; fm_wr_frame = fm_wr_frame + 1; end
    if (dut.system.VDP_SEL && !dut.system.MBUS_RNW && dut.system.MBUS_A[4] && !dut.system.MBUS_A[3]) psg_wr = psg_wr + 1;
  end

  // +trace<n>: the first n ROM transactions and a periodic machine snapshot,
  // for bring-up.
  integer trace_n, traced = 0;
  always @(posedge clk) begin
    if (traced < trace_n && !busy && !machine_reset && rom_req !== rom_ack) begin
      $display("ROM req #%0d at %0t: addr %06x (byte %06x) we %b be %b", traced, $time,
        rom_addr, {rom_addr, 1'b0}, rom_we, rom_be);
      traced = traced + 1;
    end
    if (trace_n != 0 && (clocks % 50000) == 0)
      $display("t=%0t clk=%0d RESET_N=%b LOADING=%b rst=%b hard=%b enp=%b enn=%b | AS=%b dtack=%b mstate=%0d A=%06x | BG=%b BR=%b BGACK=%b vbusBR=%b vbusBGACK=%b z80BR=%b z80BGACK=%b vbusSEL=%b | fc=%b rw=%b",
        $time, clocks, dut.system.RESET_N, dut.system.LOADING, dut.system.reset, dut.system.hard_reset,
        dut.system.M68K_CLKENp, dut.system.M68K_CLKENn,
        dut.system.M68K_AS_N, dut.system.M68K_MBUS_DTACK_N, dut.system.mstate, dbg_m68k_a,
        dut.system.M68K_BG_N, dut.system.M68K_BR_N, dut.system.M68K_BGACK_N,
        dut.system.VBUS_BR_N, dut.system.VBUS_BGACK_N, dut.system.Z80_BR_N, dut.system.Z80_BGACK_N,
        dut.system.VBUS_SEL, dut.system.M68K_FC, dut.system.M68K_RNW);
  end

  always @(posedge clk) begin
    if (clocks >= maxclk * 1000000) begin $display("clock limit reached"); $finish; end
  end

  integer i, rom_bytes, rom_words, pal_arg, export_arg, pad3_arg;
  initial begin
    if (!$value$plusargs("rom_bytes%d", rom_bytes)) begin $display("need +rom_bytes"); $finish; end
    if (!$value$plusargs("rom_words%d", rom_words)) rom_words = rom_bytes / 2;
    if (!$value$plusargs("frames%d", frames_to_run)) frames_to_run = 30;
    if (!$value$plusargs("latency%d", latency)) latency = 8;
    if (!$value$plusargs("latency_rnd%d", latency_rnd)) latency_rnd = 0;
    if (!$value$plusargs("dump_from%d", dump_from)) dump_from = 0;
    if (!$value$plusargs("dump_every%d", dump_every)) dump_every = 0;
    if (!$value$plusargs("press_start%d", press_start)) press_start = 0;
    if (!$value$plusargs("press_a%d", press_a)) press_a = 0;
    if (!$value$plusargs("press_b%d", press_b)) press_b = 0;
    if (!$value$plusargs("press_c%d", press_c)) press_c = 0;
    if (!$value$plusargs("maxclk%d", maxclk)) maxclk = 4000;
    if (!$value$plusargs("trace%d", trace_n)) trace_n = 0;
    if (!$value$plusargs("pause_at%d", pause_at)) pause_at = 0;
    if (!$value$plusargs("pause_len%d", pause_len)) pause_len = 100000;
    if (!$value$plusargs("ahist_from%d", ahist_from)) ahist_from = 0;
    if (!$value$plusargs("ahist_frames%d", ahist_frames)) ahist_frames = 0;
    if (!$value$plusargs("pal%d", pal_arg)) pal_arg = 0;
    if (!$value$plusargs("export%d", export_arg)) export_arg = 1;
    if (!$value$plusargs("pad3%d", pad3_arg)) pad3_arg = 0;
    pal = (pal_arg != 0);
    region_export = (export_arg != 0);
    pad_3button = (pad3_arg != 0);
    rom_size = rom_words[23:0];

    for (i = 0; i < 5242880; i = i + 1) cart[i] = 16'hFFFF;
    $readmemh("cart16.hex", cart);
    for (i = 0; i < WIDTH*HEIGHT; i = i + 1) fb[i] = 24'h000000;
    $display("latency %0d (random %0d), cartridge %0d bytes (%0d words), pal %0d export %0d",
      latency, latency_rnd, rom_bytes, rom_words, pal, region_export);

    repeat (20) @(posedge clk);
    #1000 cap_reset = 1'b0;
    // The memory clear, as the glue runs it: 2^16 clocks with LOADING high.
    ram_init = 1'b1;
    repeat (65536) @(posedge clk);
    #1000 ram_init = 1'b0;
    repeat (20) @(posedge clk);
    #1000 loading = 1'b0;
    repeat (20) @(posedge clk);
    #1000 machine_reset = 1'b0;
    $display("machine reset released at %0t ps; reset vector %04x%04x, entry %04x%04x",
      $time, cart[0], cart[1], cart[2], cart[3]);
    wait (frame >= frames_to_run);
    $display("done: frames %0d, ROM reads %0d writes %0d, DTACK wait edges %0d of %0d bus ends",
      frame, reads, writes, wait_edges, bus_cycles);
    $display("audio: DAC %0d..%0d with %0d changes; FM %0d..%0d (%0d changes), PSG %0d..%0d (%0d), mix %0d changes",
      audio_min, audio_max, audio_moves, fm_min, fm_max, fm_moves, psg_min, psg_max, psg_moves, mix_moves);
    $finish;
  end
endmodule
