// Genesis_MiSTer Save-State project
// v1.4 - v1.3 VDP restore plus canonical YM2612/PSG architectural replay.
// system.sv delays the common restore pulse until VDP memory and audio replay
// are complete; therefore this controller only needs a larger completion timeout.
//
// Two modes are retained:
//   vdp_scan_enable=0 : v0.8 CPU + CPU-RAM snapshot regression cycle.
//   vdp_scan_enable=1 : v0.9 cycle. Before the slow CPU-RAM CRC passes,
//                       claim the existing SS memory ports only while the
//                       Genesis VDP is in VBlank AND all renderer/VRAM32
//                       consumers are protocol-idle.
//
// v1.3 retains the v1.2 dense VDP-memory scan:
//   0x20000-0x2FFFF : 64 KiB VRAM
//   0x30000-0x302FF : 768-byte VDP-local image:
//       CRAM + VSRAM0 + VSRAM1 + 512-byte persistent sprite SAT cache
// The former holes are deliberately occupied by SAT-cache bytes, making the
// complete memory image 66,304 bytes and allowing a one-byte/MCLK stream.
//
// v1.3 retains the v1.0/v1.2 double-read architectural snapshot verification:
//   0x30300-0x3033F : atomically latched VDP registers/control/IRQ/raster state
// The two CRCs must match. The live VDP continues to raster, but the snapshot
// bank was latched on m68k_capture_start and must remain immutable.
//
// After CPU-RAM/Z80 consistency checks, v1.1 waits for a fresh VBlank and
// reuses m68k_restore_req as the common restore pulse. system.sv routes that
// pulse into the VDP safe architectural restore input. The VDP exposes a
// restore-done/verified byte at 0x3033D; v1.1 requires it before PASS.
//
// No VDP clock gating is used. Raster/sync keeps running.
// If VBlank or renderer-idle is lost before the last byte is consumed,
// the VDP scan aborts, PASS is suppressed, and CPU state is restored safely.

module ss_snapshot_orchestrator
(
    input  wire         clk,
    input  wire         reset,
    input  wire         start,
    input  wire         vdp_scan_enable,

    // v1.6A: when asserted with start, stop after capture/verification while
    // FX68K/Z80 are still held. External transport owns SS_MEM until it
    // pulses persistent_done, then the proven v1.5 restore path resumes.
    input  wire         persistent_enable,
    input  wire         persistent_done,
    input  wire         persistent_failed,
    output wire         persistent_ready,
    output wire         persistent_bad,
    output reg [3:0]    capture_error, // first failed capture check, retained until next start
    input wire          persistent_load,
    input wire          slot_z80_we,
    input wire [4:0]    slot_z80_addr,
    input wire [7:0]    slot_z80_din,
    output wire [7:0]   slot_z80_dout,

    output reg          m68k_req,
    output reg          m68k_restore_req,
    input  wire         m68k_capture_start,
    input  wire         m68k_capture_ready,
    input  wire         m68k_mem_safe,
    input  wire         m68k_busy,
    input  wire         m68k_pass,
    input  wire         m68k_fail,

    input  wire         vdp_vbl,
    input  wire         vdp_render_idle,
    input  wire         vdp_scan_idle, // shared-port safety during the read stream

    input  wire [229:0] z80_reg,
    output wire [229:0] z80_dir,
    output wire         z80_set,
    output wire         z80_drive,

    output wire         mem_active,
    output reg  [17:0]  mem_addr,
    input  wire [7:0]   mem_dout,

    output reg          busy,
    output reg          pass,
    output reg          fail,
    output reg  [31:0]  crc_first,
    output reg  [31:0]  crc_second,
    output reg  [31:0]  vdp_crc,
    output reg  [31:0]  vdp_arch_crc,
    // Game Bub: the state machine, for the save-state diagnostics register.
    output wire [5:0]   dbg_state
);

localparam [5:0]
    ST_IDLE            = 6'd0,

    // v0.9 canonical start: ensure we have seen active display, then wait
    // for the NEXT VBlank. This prevents a user request arriving near the
    // end of an already-running VBlank from stealing the renderer ports.
    ST_WAIT_ACTIVE     = 6'd1,
    ST_WAIT_VBL        = 6'd2,

    ST_WAIT_CAPTURE    = 6'd3,
    ST_WAIT_M68K_HOLD  = 6'd4,

    ST_VDP_PRIME       = 6'd5,
    ST_VDP_STREAM      = 6'd6,
    ST_VDP_ABORT       = 6'd7,

    ST_SCAN1_SET       = 6'd8,
    ST_SCAN1_WAIT1     = 6'd9,
    ST_SCAN1_WAIT2     = 6'd10,
    ST_SCAN1_READ      = 6'd11,

    ST_SCAN2_SET       = 6'd12,
    ST_SCAN2_WAIT1     = 6'd13,
    ST_SCAN2_WAIT2     = 6'd14,
    ST_SCAN2_READ      = 6'd15,

    ST_Z80_SET         = 6'd16,
    ST_Z80_WAIT1       = 6'd17,
    ST_Z80_WAIT2       = 6'd18,
    ST_Z80_VERIFY      = 6'd19,

    ST_M68K_RESTORE    = 6'd20,
    ST_WAIT_M68K_DONE  = 6'd21,
    ST_DONE            = 6'd22,

    // v1.0 architectural snapshot readback. Appended so all v0.9 state
    // encodings remain unchanged for easier Quartus regression review.
    ST_VDP_ARCH1_PRIME  = 6'd23,
    ST_VDP_ARCH1_STREAM = 6'd24,
    ST_VDP_ARCH2_PRIME   = 6'd25,
    ST_VDP_ARCH2_STREAM  = 6'd26,

    // v1.1 restore phase. Keep all v1.0 encodings stable.
    ST_RESTORE_WAIT_ACTIVE = 6'd27,
    ST_RESTORE_WAIT_VBL    = 6'd28,
    ST_VDP_RESTORE_PRIME   = 6'd29,
    ST_VDP_RESTORE_CHECK   = 6'd30,

    // v1.6A external-DDR export barrier. Existing state encodings stay fixed.
    ST_PERSIST_WAIT        = 6'd31,
    ST_CAPTURE_WAIT_ACTIVE = 6'd32,
    ST_CAPTURE_WAIT_VBL    = 6'd33;

reg [5:0] state;
reg       armed;
reg       failed;
reg       do_vdp_scan;
reg       do_persistent;
reg [229:0] z80_snap;
reg [31:0] crc_work;
reg [31:0] vdp_arch_crc_first;
reg [21:0] restore_wait;
reg        restore_m68k_seen_done;
reg        restore_m68k_pass_latched;
reg        restore_m68k_fail_latched;

// Address whose data is present on mem_dout during the current VDP-stream edge.
reg [17:0] vdp_consume_addr;

wire [255:0] z80_image = {26'd0,z80_snap};
assign slot_z80_dout = z80_image[{slot_z80_addr,3'b000} +: 8];
assign persistent_bad = failed;
assign z80_dir   = z80_snap;
assign persistent_ready = (state == ST_PERSIST_WAIT);
assign z80_set   = (state == ST_Z80_SET);
assign z80_drive = (state == ST_Z80_SET)   ||
                   (state == ST_Z80_WAIT1) ||
                   (state == ST_Z80_WAIT2) ||
                   (state == ST_Z80_VERIFY);

wire vdp_mem_active =
    (state == ST_VDP_PRIME)        ||
    (state == ST_VDP_STREAM)       ||
    (state == ST_VDP_ARCH1_PRIME)  ||
    (state == ST_VDP_ARCH1_STREAM) ||
    (state == ST_VDP_ARCH2_PRIME)  ||
    (state == ST_VDP_ARCH2_STREAM) ||
    (state == ST_VDP_RESTORE_PRIME) ||
    (state == ST_VDP_RESTORE_CHECK);

wire cpu_mem_active =
    (state == ST_SCAN1_SET)   || (state == ST_SCAN1_WAIT1) ||
    (state == ST_SCAN1_WAIT2) || (state == ST_SCAN1_READ)  ||
    (state == ST_SCAN2_SET)   || (state == ST_SCAN2_WAIT1) ||
    (state == ST_SCAN2_WAIT2) || (state == ST_SCAN2_READ);

assign mem_active = vdp_mem_active | cpu_mem_active;

function automatic [31:0] crc32_byte(
    input [31:0] crc,
    input [7:0]  data
);
    integer i;
    reg [31:0] c;
    reg [7:0] d;
begin
    c = crc;
    d = data;
    for (i = 0; i < 8; i = i + 1) begin
        if (c[0] ^ d[0])
            c = (c >> 1) ^ 32'hEDB88320;
        else
            c = (c >> 1);
        d = d >> 1;
    end
    crc32_byte = c;
end
endfunction

function automatic [17:0] next_ram_addr(input [17:0] a);
begin
    // 00000-0FFFF : 68K RAM
    // 10000-11FFF : Z80 RAM
    if (a == 18'h0FFFF)
        next_ram_addr = 18'h10000;
    else
        next_ram_addr = a + 1'b1;
end
endfunction

function automatic [17:0] next_vdp_addr(input [17:0] a);
begin
    // v1.2 fills the old VDP-local holes with the 512-byte persistent SAT
    // cache, so 0x30000-0x302FF is now a dense serialized memory window.
    if (a == 18'h2FFFF)
        next_vdp_addr = 18'h30000;
    else
        next_vdp_addr = a + 1'b1;
end
endfunction

wire ram_scan_last = (mem_addr == 18'h11FFF);
wire vdp_scan_last  = (vdp_consume_addr == 18'h302FF);
wire vdp_arch_last  = (vdp_consume_addr == 18'h3033F);

// Fixed bytes prove that the atomic-capture pulse happened and that the
// one-clock VDP SS readback pipeline is aligned to the requested address.
wire vdp_arch_marker_bad =
    ((vdp_consume_addr == 18'h30338) && (mem_dout != 8'hA1)) ||
    ((vdp_consume_addr == 18'h30339) && (mem_dout != 8'h56)) ||
    ((vdp_consume_addr == 18'h3033A) && (mem_dout != 8'h44)) ||
    ((vdp_consume_addr == 18'h3033B) && (mem_dout != 8'h50)) ||
    ((vdp_consume_addr == 18'h3033C) && (mem_dout != 8'h13)) ||
    ((vdp_consume_addr == 18'h3033E) && (mem_dout != 8'hFF));

wire [31:0] crc_next = crc32_byte(crc_work, mem_dout);

always @(posedge clk) begin
    if (reset) begin
        state             <= ST_IDLE;
        armed             <= 1'b1;
        failed            <= 1'b0;
        capture_error <= 0;
        do_vdp_scan       <= 1'b0;
        do_persistent     <= 1'b0;
        z80_snap          <= 230'd0;
        crc_work          <= 32'hFFFFFFFF;
        crc_first         <= 32'd0;
        crc_second        <= 32'd0;
        vdp_crc           <= 32'd0;
        vdp_arch_crc      <= 32'd0;
        vdp_arch_crc_first <= 32'd0;
        restore_wait       <= 22'd0;
        restore_m68k_seen_done    <= 1'b0;
        restore_m68k_pass_latched <= 1'b0;
        restore_m68k_fail_latched <= 1'b0;
        mem_addr          <= 18'd0;
        vdp_consume_addr  <= 18'd0;
        m68k_req          <= 1'b0;
        m68k_restore_req  <= 1'b0;
        busy              <= 1'b0;
        pass              <= 1'b0;
        fail              <= 1'b0;
    end
    else begin
        m68k_restore_req <= 1'b0;
        if (slot_z80_we && persistent_ready) begin
            if (slot_z80_addr < 28)
                z80_snap[{slot_z80_addr,3'b000} +: 8] <= slot_z80_din;
            else if (slot_z80_addr == 28) z80_snap[229:224] <= slot_z80_din[5:0];
        end

        if (!start)
            armed <= 1'b1;

        case (state)
            ST_IDLE: begin
                busy     <= 1'b0;
                m68k_req <= 1'b0;

                if (start && armed) begin
                    armed       <= 1'b0;
                    failed        <= 1'b0;
                    capture_error <= 0;
                    do_vdp_scan   <= vdp_scan_enable;
                    do_persistent <= persistent_enable;
                    pass          <= 1'b0;
                    fail        <= 1'b0;
                    crc_first   <= 32'd0;
                    crc_second  <= 32'd0;
                    vdp_crc     <= 32'd0;
                    vdp_arch_crc <= 32'd0;
                    vdp_arch_crc_first <= 32'd0;
                    restore_wait <= 22'd0;
                    busy        <= 1'b1;

                    if (vdp_scan_enable) begin
                        // v0.9 deliberately waits for a fresh VBlank.
                        m68k_req <= 1'b0;
                        state    <= ST_WAIT_ACTIVE;
                    end
                    else begin
                        // Preserve the already hardware-validated v0.8 path.
                        m68k_req <= 1'b1;
                        state    <= ST_WAIT_CAPTURE;
                    end
                end
            end

            ST_WAIT_ACTIVE: begin
                // If the request arrived during VBlank, wait for active video.
                // If it arrived during active video this completes immediately.
                if (!vdp_vbl)
                    state <= ST_WAIT_VBL;
            end

            ST_WAIT_VBL: begin
                if (vdp_vbl) begin
                    m68k_req <= 1'b1;
                    state    <= ST_WAIT_CAPTURE;
                end
            end

            // capture_start is the exact Z80 clean-boundary edge accepted by
            // the M68K save controller. Z80/FM/PSG are paused on this edge.
            ST_WAIT_CAPTURE: begin
                if (m68k_capture_start) begin
                    z80_snap <= z80_reg;
                    state    <= ST_WAIT_M68K_HOLD;
                end
                else if (m68k_fail) begin
                    failed   <= 1'b1;
                    if (!failed) capture_error <= 4'd1;
                    m68k_req <= 1'b0;
                    busy     <= 1'b0;
                    fail     <= 1'b1;
                    state    <= ST_DONE;
                end
            end

            // FX68K has pushed context, captured SSP and is held reset.
            ST_WAIT_M68K_HOLD: begin
                if (m68k_capture_ready && m68k_mem_safe) begin
                    if (do_vdp_scan) begin
                        // IRQ7 entry/context pushes can consume the original
                        // blank. Scan only in a fresh blank AFTER CPU hold.
                        // No SS memory ownership while waiting for that frame.
                        restore_wait <= 22'd0;
                        state <= ST_CAPTURE_WAIT_ACTIVE;
                    end
                    else begin
                        mem_addr <= 18'h00000;
                        crc_work <= 32'hFFFFFFFF;
                        state    <= ST_SCAN1_SET;
                    end
                end
                else if (m68k_fail) begin
                    failed   <= 1'b1;
                    if (!failed) capture_error <= 4'd2;
                    m68k_req <= 1'b0;
                    busy     <= 1'b0;
                    fail     <= 1'b1;
                    state    <= ST_DONE;
                end
            end

            ST_CAPTURE_WAIT_ACTIVE: begin
                if (restore_wait == 22'd3000000) begin
                    failed <= 1'b1;
                    if (!failed) capture_error <= 4'd9;
                    state <= ST_VDP_ABORT;
                end else begin
                    restore_wait <= restore_wait + 1'b1;
                    if (!vdp_vbl) state <= ST_CAPTURE_WAIT_VBL;
                end
            end

            ST_CAPTURE_WAIT_VBL: begin
                if (restore_wait == 22'd3000000) begin
                    failed <= 1'b1;
                    if (!failed) capture_error <= 4'd10;
                    state <= ST_VDP_ABORT;
                end else begin
                    restore_wait <= restore_wait + 1'b1;
                    if (vdp_vbl && vdp_render_idle &&
                        m68k_capture_ready && m68k_mem_safe) begin
                        mem_addr         <= 18'h20000;
                        vdp_consume_addr <= 18'h20000;
                        crc_work         <= 32'hFFFFFFFF;
                        state            <= ST_VDP_PRIME;
                    end
                end
            end

            // mem_addr=0x20000 has been presented for one complete clock.
            // At this edge the VRAM port captures it. The result is consumed
            // on the next edge while the second address is launched.
            ST_VDP_PRIME: begin
                if (!vdp_vbl || !vdp_scan_idle) begin
                    failed <= 1'b1;
                    if (!failed) capture_error <= !vdp_vbl ? 4'd3 : 4'd4;
                    state  <= ST_VDP_ABORT;
                end
                else begin
                    vdp_consume_addr <= mem_addr;
                    mem_addr         <= next_vdp_addr(mem_addr);
                    state            <= ST_VDP_STREAM;
                end
            end

            ST_VDP_STREAM: begin
                // Ownership is legal only for the canonical VBlank window.
                if (!vdp_vbl || !vdp_scan_idle) begin
                    failed <= 1'b1;
                    if (!failed) capture_error <= !vdp_vbl ? 4'd3 : 4'd4;
                    state  <= ST_VDP_ABORT;
                end
                else begin
                    crc_work <= crc_next;

                    if (vdp_scan_last) begin
                        vdp_crc          <= ~crc_next;

                        // v1.1: memory is now captured/verified. Read the
                        // already-latched 64-byte architectural window.
                        mem_addr         <= 18'h30300;
                        vdp_consume_addr <= 18'h30300;
                        crc_work         <= 32'hFFFFFFFF;
                        state            <= ST_VDP_ARCH1_PRIME;
                    end
                    else begin
                        vdp_consume_addr <= mem_addr;
                        mem_addr         <= next_vdp_addr(mem_addr);
                    end
                end
            end

            // v1.1 retains architectural snapshot pass #1. The live state was copied
            // atomically inside vdp.vhd on m68k_capture_start; this readout is
            // therefore expected to stay stable while the raster continues.
            ST_VDP_ARCH1_PRIME: begin
                if (!vdp_vbl || !vdp_scan_idle) begin
                    failed <= 1'b1;
                    if (!failed) capture_error <= !vdp_vbl ? 4'd3 : 4'd4;
                    state  <= ST_VDP_ABORT;
                end
                else begin
                    vdp_consume_addr <= mem_addr;
                    mem_addr         <= mem_addr + 1'b1;
                    state            <= ST_VDP_ARCH1_STREAM;
                end
            end

            ST_VDP_ARCH1_STREAM: begin
                if (!vdp_vbl || !vdp_scan_idle) begin
                    failed <= 1'b1;
                    if (!failed) capture_error <= !vdp_vbl ? 4'd3 : 4'd4;
                    state  <= ST_VDP_ABORT;
                end
                else begin
                    crc_work <= crc_next;

                    if (vdp_arch_marker_bad) begin
                        failed <= 1'b1;
                        if (!failed) capture_error <= 4'd5;
                    end

                    if (vdp_arch_last) begin
                        vdp_arch_crc_first <= ~crc_next;
                        mem_addr            <= 18'h30300;
                        vdp_consume_addr    <= 18'h30300;
                        crc_work            <= 32'hFFFFFFFF;
                        state               <= ST_VDP_ARCH2_PRIME;
                    end
                    else begin
                        vdp_consume_addr <= mem_addr;
                        mem_addr         <= mem_addr + 1'b1;
                    end
                end
            end

            // Pass #2 catches any accidental use of live VDP signals in the
            // serialized window: a changing raster would then perturb the CRC.
            ST_VDP_ARCH2_PRIME: begin
                if (!vdp_vbl || !vdp_scan_idle) begin
                    failed <= 1'b1;
                    if (!failed) capture_error <= !vdp_vbl ? 4'd3 : 4'd4;
                    state  <= ST_VDP_ABORT;
                end
                else begin
                    vdp_consume_addr <= mem_addr;
                    mem_addr         <= mem_addr + 1'b1;
                    state            <= ST_VDP_ARCH2_STREAM;
                end
            end

            ST_VDP_ARCH2_STREAM: begin
                if (!vdp_vbl || !vdp_scan_idle) begin
                    failed <= 1'b1;
                    if (!failed) capture_error <= !vdp_vbl ? 4'd3 : 4'd4;
                    state  <= ST_VDP_ABORT;
                end
                else begin
                    crc_work <= crc_next;

                    if (vdp_arch_marker_bad) begin
                        failed <= 1'b1;
                        if (!failed) capture_error <= 4'd5;
                    end

                    if (vdp_arch_last) begin
                        vdp_arch_crc <= ~crc_next;

                        if ((~crc_next) != vdp_arch_crc_first) begin
                            failed <= 1'b1;
                            if (!failed) capture_error <= 4'd6;
                        end

                        // Release VDP SS ownership and continue the already
                        // hardware-validated v0.8 CPU-RAM consistency passes.
                        mem_addr <= 18'h00000;
                        crc_work <= 32'hFFFFFFFF;
                        state    <= ST_SCAN1_SET;
                    end
                    else begin
                        vdp_consume_addr <= mem_addr;
                        mem_addr         <= mem_addr + 1'b1;
                    end
                end
            end

            // A VDP-window timing failure must never strand FX68K in reset.
            // Drop SS port ownership and proceed directly to CPU restoration.
            ST_VDP_ABORT: begin
                state <= ST_Z80_SET;
            end

            // v0.8 full 72 KiB CPU-RAM scan #1.
            ST_SCAN1_SET:   state <= ST_SCAN1_WAIT1;
            ST_SCAN1_WAIT1: state <= ST_SCAN1_WAIT2;
            ST_SCAN1_WAIT2: state <= ST_SCAN1_READ;

            ST_SCAN1_READ: begin
                crc_work <= crc_next;
                if (ram_scan_last) begin
                    crc_first <= ~crc_next;
                    mem_addr  <= 18'h00000;
                    crc_work  <= 32'hFFFFFFFF;
                    state     <= ST_SCAN2_SET;
                end
                else begin
                    mem_addr <= next_ram_addr(mem_addr);
                    state    <= ST_SCAN1_SET;
                end
            end

            // v0.8 full 72 KiB CPU-RAM scan #2.
            ST_SCAN2_SET:   state <= ST_SCAN2_WAIT1;
            ST_SCAN2_WAIT1: state <= ST_SCAN2_WAIT2;
            ST_SCAN2_WAIT2: state <= ST_SCAN2_READ;

            ST_SCAN2_READ: begin
                crc_work <= crc_next;
                if (ram_scan_last) begin
                    crc_second <= ~crc_next;

                    if ((~crc_next) != crc_first) begin
                        failed <= 1'b1;
                        if (!failed) capture_error <= 4'd7;
                    end

                    state <= ST_Z80_SET;
                end
                else begin
                    mem_addr <= next_ram_addr(mem_addr);
                    state    <= ST_SCAN2_SET;
                end
            end

            ST_Z80_SET:   state <= ST_Z80_WAIT1;
            ST_Z80_WAIT1: state <= ST_Z80_WAIT2;
            ST_Z80_WAIT2: state <= ST_Z80_VERIFY;

            ST_Z80_VERIFY: begin
                if (z80_reg != z80_snap) begin
                    failed <= 1'b1;
                    if (!failed) capture_error <= 4'd8;
                end

                // v1.6A: hold the exact captured machine here. m68k_req is
                // intentionally left asserted; the save handler therefore
                // keeps FX68K reset/frozen and Z80/audio remain quiescent.
                // All orchestrator SS_MEM states are inactive in this barrier,
                // so the external transport may copy CPU RAM without races.
                if (do_persistent)
                    state <= ST_PERSIST_WAIT;
                else if (do_vdp_scan)
                    state <= ST_RESTORE_WAIT_ACTIVE;
                else
                    state <= ST_M68K_RESTORE;
            end

            ST_PERSIST_WAIT: begin
                if (persistent_done) begin
                    if (persistent_failed)
                        failed <= 1'b1;

                    do_persistent <= 1'b0;
                    if (persistent_load && !persistent_failed)
                        state <= ST_Z80_SET; // apply the imported A snapshot
                    else begin
                        // SAVE returns through the M68K handler only.
                        do_vdp_scan <= 1'b0;
                        state <= ST_M68K_RESTORE;
                    end
                end
            end

            // Do not restore VDP state in the middle of active raster. As at
            // capture, require a genuinely fresh VBlank, not the tail of one
            // already in progress.
            ST_RESTORE_WAIT_ACTIVE: begin
                if (!vdp_vbl)
                    state <= ST_RESTORE_WAIT_VBL;
            end

            ST_RESTORE_WAIT_VBL: begin
                if (vdp_vbl && vdp_render_idle && m68k_mem_safe) begin
                    mem_addr    <= 18'h3033D;
                    restore_wait <= 22'd0;
                    restore_m68k_seen_done    <= 1'b0;
                    restore_m68k_pass_latched <= 1'b0;
                    restore_m68k_fail_latched <= 1'b0;
                    state       <= ST_M68K_RESTORE;
                end
            end

            ST_M68K_RESTORE: begin
                // system.sv fans this one-cycle pulse to both the proven FX68K
                // restore handler and v1.1's VDP safe architectural restore.
                m68k_restore_req <= 1'b1;
                if (do_vdp_scan)
                    state <= ST_VDP_RESTORE_PRIME;
                else
                    state <= ST_WAIT_M68K_DONE;
            end

            // 0x3033D is pipelined inside vdp.vhd. Give the VDP restore edge
            // and its one-cycle internal compare time to settle before check.
            ST_VDP_RESTORE_PRIME: begin
                mem_addr <= 18'h3033D;
                state    <= ST_VDP_RESTORE_CHECK;
            end

            ST_VDP_RESTORE_CHECK: begin
                mem_addr <= 18'h3033D;

                // system.sv withholds the proven FX68K/VDP architectural
                // restore pulse until all 66,304 memory bytes are replayed.
                // Therefore m68k_busy is also our unambiguous completion
                // barrier: while it remains high, mem_dout may be internal
                // replay traffic and must not be interpreted as 0x3033D.
                if (!restore_m68k_seen_done) begin
                    if (!m68k_busy) begin
                        restore_m68k_seen_done    <= 1'b1;
                        restore_m68k_pass_latched <= m68k_pass;
                        restore_m68k_fail_latched <= m68k_fail;
                        restore_wait              <= 22'd0;
                    end
                    else if (restore_wait == 22'd3000000) begin
                        failed <= 1'b1;
                        restore_m68k_seen_done    <= 1'b1;
                        restore_m68k_fail_latched <= 1'b1;
                        restore_wait              <= 22'd0;
                    end
                    else begin
                        restore_wait <= restore_wait + 1'b1;
                    end
                end
                else begin
                    // Allow the external 0x3033D address and VDP one-clock
                    // read pipeline to settle after system.sv releases the
                    // internal replay bus.
                    if (restore_wait >= 22'd3 && mem_dout[7]) begin
                        if (!mem_dout[0])
                            failed <= 1'b1;
                        state <= ST_WAIT_M68K_DONE;
                    end
                    else if (restore_wait == 22'd31) begin
                        failed <= 1'b1;
                        state  <= ST_WAIT_M68K_DONE;
                    end
                    else begin
                        restore_wait <= restore_wait + 1'b1;
                    end
                end
            end

            ST_WAIT_M68K_DONE: begin
                if (!m68k_busy) begin
                    m68k_req <= 1'b0;
                    busy     <= 1'b0;

                    if (failed ||
                        (do_vdp_scan ? (restore_m68k_fail_latched || !restore_m68k_pass_latched)
                                     : (m68k_fail || !m68k_pass))) begin
                        pass <= 1'b0;
                        fail <= 1'b1;
                    end
                    else begin
                        pass <= 1'b1;
                        fail <= 1'b0;
                    end

                    state <= ST_DONE;
                end
            end

            ST_DONE: begin
                m68k_req <= 1'b0;
                busy     <= 1'b0;
                if (!start)
                    state <= ST_IDLE;
            end

            default: state <= ST_IDLE;
        endcase
    end
end

assign dbg_state = state;

endmodule
