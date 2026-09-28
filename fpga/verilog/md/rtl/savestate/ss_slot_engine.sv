// R58. Four MiSTer file-backed DDR slots. Capture/import remain R57 fix8.
// DDR ping retains its R56 pattern, address and non-freezing operation.
// Game Bub: PROBE = 0 turns the periodic header probe off (the slot_valid output is then
// meaningless; the glue has its own slot scanner). The probe read the slot's header twice
// every 2^20 clocks through the DDR channel, which made a few ROM fetches a second late.
module ss_slot_engine #(parameter PROBE = 1) (
    input wire clk, reset,
    input wire save_cmd, load_cmd, ping_cmd, blocked, supported,
    input wire [1:0] selected_slot,
    input wire [63:0] rom_identity, config_identity,
    output reg orch_start,
    output wire persistent_enable,
    input wire persistent_ready, persistent_bad,
    output reg persistent_done, persistent_failed,
    input wire orch_busy, orch_pass, orch_fail, sys_fail,
    output wire load_mode, save_return,
    output wire mem_active,
    output wire [17:0] mem_addr,
    output wire [7:0] mem_din,
    output wire mem_we,
    input wire [7:0] mem_dout,
    output reg ddr_req = 0,
    output reg ddr_rnw = 0,
    output reg [21:0] ddr_addr = 0,
    output reg [63:0] ddr_din = 0,
    output wire [7:0] ddr_be,
    input wire [63:0] ddr_dout,
    input wire ddr_ack,
    output reg busy, pass, fail,
    output wire slot_valid,
    output wire recover_reset,
    output reg [31:0] source_crc, checked_crc,
    output reg [7:0] error_code
);
localparam [31:0] PAYLOAD_BYTES = 32'h00022800;
// Physical base 0x3E100000, stride 0x40000; private DDR port base 0x3E000000.
// +0: MiSTer {body_words, change_counter}; +8: format; +16: CRC/size;
// +24: ROM identity; +32: machine configuration; +40: R57 payload.
localparam [31:0] BODY_WORDS = (PAYLOAD_BYTES + 32'd32) / 4;
localparam [63:0] HEADER = {32'h52353853,16'h0001,16'h0001};
reg [1:0] active_slot = 0;
wire [21:0] control_word = 22'h20000 + {5'd0,active_slot,15'd0};
wire [21:0] header_word = control_word + 22'd1;
wire [21:0] payload_word = control_word + 22'd5;
reg slot_known = 0;
assign slot_valid = slot_known && selected_slot == active_slot;
reg [63:0] active_rom, active_config;
reg [31:0] commit_counter;
reg probing = 0;
reg [19:0] probe_timer = 0;
reg [2:0] deferred = 0;
localparam [4:0] IDLE=0, INVALID_WAIT=1, CAPTURE=2, SAVE_PRIME=3,
    SAVE_BYTE=4, SAVE_SEND=5, SAVE_WAIT=6, READ_SEND=7, READ_WAIT=8,
    READ_BYTE=9, META_WAIT=10, COMMIT_WAIT=11, HEADER_WAIT=12,
    INFO_WAIT=13, RELEASE=14, FINISH=15, DRAIN=16,
    PING_WRITE=17, PING_READ=18, LOAD_CHECK_PRIME=19, LOAD_CHECK_BYTE=20,
    CONTROL_WAIT=21, ROM_WAIT=22, CONFIG_WAIT=23, SAVE_CONTROL_WAIT=24,
    SAVE_ROM_WAIT=25, SAVE_CONFIG_WAIT=26, PUBLISH_WAIT=27;
reg [4:0] state = DRAIN;
reg save_old, load_old, ping_old;
reg do_load, do_ping, apply_load, verify_save;
reg capture_seen;
reg [17:0] offset;
reg [2:0] lane;
reg [2:0] prime;
reg [63:0] transfer;
reg [31:0] crc, expected_crc;
// Game Bub: the request watchdog, 2^27 clocks = 2.5 s; the whole-system bench can shorten it
// to 2^24 (0.31 s, EXTRA_DEFS="-d MD_SIM_SHORT_WATCHDOG") so a failure and its release fit in
// a run of a few dozen frames. The hardware build never defines it.
`ifdef MD_SIM_SHORT_WATCHDOG
localparam WATCHDOG_BITS = 24;
`else
localparam WATCHDOG_BITS = 27;
`endif
reg [WATCHDOG_BITS-1:0] watchdog;
reg [8:0] recovery_count = 0;
reg [7:0] ping_index;
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg ack_meta = 0, ack_sync = 0;
always @(posedge clk) begin
    ack_meta <= ddr_ack;
    ack_sync <= ack_meta;
end
assign ddr_be = 8'hFF;
wire [2:0] command_edge = {ping_cmd && !ping_old, load_cmd && !load_old, save_cmd && !save_old};
wire [2:0] command_req = command_edge | deferred;
assign load_mode = do_load;
assign save_return = busy && !do_ping && !do_load;
assign persistent_enable = busy && !do_ping;
assign mem_active = (state == SAVE_PRIME || state == SAVE_BYTE ||
                     state == LOAD_CHECK_PRIME || state == LOAD_CHECK_BYTE ||
                     (state == READ_BYTE && apply_load));
assign mem_addr = offset < 18'h12000 ? offset : offset + 18'h0E000;
assign mem_din = transfer[{lane,3'b000} +: 8];
assign mem_we = state == READ_BYTE && apply_load && !reset && !recover_reset;
assign recover_reset = recovery_count != 0;
wire last_byte = offset == PAYLOAD_BYTES-1;
wire [7:0] read_byte = transfer[{lane,3'b000} +: 8];
function automatic [31:0] crc_byte(input [31:0] c_in, input [7:0] b);
    reg [31:0] c;
    integer i;
    begin
        c=c_in ^ {24'd0,b};
        for(i=0;i<8;i=i+1) c=c[0] ? (c>>1)^32'hEDB88320 : c>>1;
        crc_byte=c;
    end
endfunction
wire [31:0] read_crc_next = crc_byte(crc,read_byte);
function automatic [63:0] ping_pattern(input [7:0] n);
    ping_pattern={48'h535344445235,n,~n};
endfunction

always @(posedge clk) begin
    save_old <= save_cmd;
    load_old <= load_cmd;
    ping_old <= ping_cmd;
    // Only metadata probes may defer commands. Busy capture/restore never queues them.
    if (probing) deferred <= deferred | command_edge;
    persistent_done <= 0;
    persistent_failed <= 0;
    if (recovery_count != 0) recovery_count <= recovery_count - 1'b1;
    if (reset) begin
        state <= DRAIN;
        // Never cancel/rebase an outstanding DDR toggle or its payload.
        busy <= 0; pass <= 0; fail <= 0; slot_known <= 0;
        orch_start <= 0;
        probing <= 0; deferred <= 0; probe_timer <= 0;
        active_slot <= selected_slot; active_rom <= 0; active_config <= 0;
        commit_counter <= 0;
        do_load <= 0; do_ping <= 0; apply_load <= 0; verify_save <= 0;
        capture_seen <= 0;
        offset <= 0; lane <= 0; prime <= 0; transfer <= 0;
        crc <= 32'hFFFFFFFF; expected_crc <= 0;
        watchdog <= 0; source_crc <= 0; checked_crc <= 0;
        error_code <= 0; ping_index <= 0;
    end else begin
        if (state != IDLE && state != DRAIN) watchdog <= watchdog + 1'b1;
        case (state)
            IDLE: begin
                busy <= 0; orch_start <= 0; watchdog <= 0;
                if (command_req != 0) begin
                    deferred <= 0; probing <= 0;
                    pass <= 0; fail <= 0; error_code <= 0;
                    if (blocked || recover_reset || ack_sync != ddr_req ||
                        (command_req != 3'b001 && command_req != 3'b010 && command_req != 3'b100)) begin
                        fail <= 1; error_code <= 8'h01;
                    end else if (command_req[2]) begin
                        busy <= 1; do_ping <= 1; do_load <= 0; ping_index <= 0;
                        ddr_rnw <= 0; ddr_addr <= 0; ddr_din <= ping_pattern(0);
                        ddr_req <= ~ddr_req; state <= PING_WRITE;
                    end else if (!supported) begin
                        fail <= 1; error_code <= 8'h02;
                    end else begin
                        busy <= 1; do_ping <= 0; apply_load <= 0; verify_save <= 0;
                        capture_seen <= 0; do_load <= command_req[1];
                        active_slot <= selected_slot;
                        active_rom <= rom_identity; active_config <= config_identity;
                        slot_known <= 0;
                        offset <= 0; lane <= 0; crc <= 32'hFFFFFFFF;
                        ddr_addr <= 22'h20000 + {5'd0,selected_slot,15'd0};
                        ddr_req <= ~ddr_req; ddr_rnw <= 1;
                        state <= command_req[1] ? CONTROL_WAIT : SAVE_CONTROL_WAIT;
                    end
                end else if (PROBE && !blocked && supported && (probe_timer == 0 || selected_slot != active_slot)) begin
                    // Read metadata after reset/slot selection and periodically. Main
                    // restores files while loading the ROM; never erase those on reset.
                    probing <= 1; do_ping <= 0; do_load <= 0;
                    if (selected_slot != active_slot) slot_known <= 0;
                    active_slot <= selected_slot;
                    active_rom <= rom_identity; active_config <= config_identity;
                    ddr_addr <= 22'h20000 + {5'd0,selected_slot,15'd0};
                    ddr_req <= ~ddr_req; ddr_rnw <= 1; state <= CONTROL_WAIT;
                end else probe_timer <= probe_timer + 1'b1;
            end
            SAVE_CONTROL_WAIT: if (ack_sync == ddr_req) begin
                // Read the host's current counter (FFFFFFFF after ROM reload).
                commit_counter <= ddr_dout[31:0] >= 32'hFFFFFFFE ? 32'd0 : ddr_dout[31:0]+32'd1;
                // Game Bub: the slot's size word stays as it is until the new state is complete
                // and verified (PUBLISH_WAIT), so a save that fails in the capture keeps the state
                // that was in the slot. The fork zeroed it here so that MiSTer's Main would not
                // poll a half-written slot; the firmware here reads the slots at Exit Core only.
                orch_start <= 1; state <= CAPTURE;
            end
            CONTROL_WAIT: if (ack_sync == ddr_req) begin
                if (ddr_dout[63:32] != BODY_WORDS) begin
                    slot_known <= 0;
                    if (!probing) begin
                        fail <= 1; error_code <= ddr_dout[63:32] == 0 ? 8'h03 : 8'h04;
                    end
                    state <= DRAIN;
                end else begin
                    ddr_addr <= header_word; ddr_req <= ~ddr_req; state <= HEADER_WAIT;
                end
            end
            INVALID_WAIT: if (ack_sync == ddr_req) begin
                orch_start <= 1; state <= CAPTURE;
            end
            HEADER_WAIT: if (ack_sync == ddr_req) begin
                if (ddr_dout != HEADER) begin
                    slot_known <= 0; state <= DRAIN;
                    if (!probing) begin fail <= 1; error_code <= 8'h04; end
                end else begin
                    ddr_addr <= header_word+1'b1; ddr_req <= ~ddr_req; state <= INFO_WAIT;
                end
            end
            INFO_WAIT: if (ack_sync == ddr_req) begin
                if (ddr_dout[31:0] != PAYLOAD_BYTES) begin
                    slot_known <= 0; state <= DRAIN;
                    if (!probing) begin fail <= 1; error_code <= 8'h04; end
                end else begin
                    expected_crc <= ddr_dout[63:32];
                    ddr_addr <= control_word+22'd3; ddr_req <= ~ddr_req; state <= ROM_WAIT;
                end
            end
            ROM_WAIT: if (ack_sync == ddr_req) begin
                if (ddr_dout != active_rom) begin
                    slot_known <= 0; state <= DRAIN;
                    if (!probing) begin fail <= 1; error_code <= 8'h1A; end
                end else begin
                    ddr_addr <= control_word+22'd4; ddr_req <= ~ddr_req; state <= CONFIG_WAIT;
                end
            end
            CONFIG_WAIT: if (ack_sync == ddr_req) begin
                if (ddr_dout != active_config) begin
                    slot_known <= 0; state <= DRAIN;
                    if (!probing) begin fail <= 1; error_code <= 8'h1B; end
                end else begin
                    slot_known <= 1;
                    state <= probing ? DRAIN : READ_SEND;
                end
            end
            CAPTURE: begin
                if (orch_busy) capture_seen <= 1;
                if (persistent_ready) begin
                    if (persistent_bad) begin
                        // Captured B is intact; use CPU-only return on capture failure.
                        do_load <= 0;
                        fail <= 1; error_code <= 8'h05;
                        persistent_done <= 1; persistent_failed <= 1; state <= FINISH;
                    end else begin
                        offset <= 0; lane <= 0; prime <= 0; crc <= 32'hFFFFFFFF;
                        apply_load <= do_load;
                        state <= do_load ? READ_SEND : SAVE_PRIME;
                    end
                end else if (capture_seen && !orch_busy && orch_fail) begin
                    fail <= 1; error_code <= 8'h05; state <= DRAIN;
                end
            end
            SAVE_PRIME: begin
                // Covers CPU RAM tag + system registered slot read (2 clocks).
                if (prime == 3) begin prime <= 0; state <= SAVE_BYTE; end
                else prime <= prime + 1'b1;
            end
            SAVE_BYTE: begin
                transfer[{lane,3'b000} +: 8] <= mem_dout;
                crc <= crc_byte(crc,mem_dout);
                if (lane == 7) state <= SAVE_SEND;
                else begin offset <= offset+1'b1; lane <= lane+1'b1; state <= SAVE_PRIME; end
            end
            SAVE_SEND: begin
                ddr_rnw <= 0; ddr_addr <= payload_word + {7'd0,offset[17:3]};
                ddr_din <= transfer; ddr_req <= ~ddr_req; state <= SAVE_WAIT;
            end
            SAVE_WAIT: if (ack_sync == ddr_req) begin
                if (last_byte) begin
                    expected_crc <= ~crc; source_crc <= ~crc;
                    verify_save <= 1; crc <= 32'hFFFFFFFF; offset <= 0; lane <= 0;
                    state <= READ_SEND;
                end else begin
                    offset <= offset+1'b1; lane <= 0; state <= SAVE_PRIME;
                end
            end
            READ_SEND: begin
                ddr_rnw <= 1; ddr_addr <= payload_word + {7'd0,offset[17:3]};
                ddr_req <= ~ddr_req; state <= READ_WAIT;
            end
            READ_WAIT: if (ack_sync == ddr_req) begin
                transfer <= ddr_dout; lane <= 0; state <= READ_BYTE;
            end
            READ_BYTE: begin
                // Write strobe applies this byte on this edge only in import pass.
                crc <= read_crc_next;
                if (last_byte) begin
                    checked_crc <= ~read_crc_next;
                    if (~read_crc_next != expected_crc) begin
                        fail <= 1; slot_known <= 0; error_code <= 8'h06;
                        if (apply_load) recovery_count <= 9'd511;
                        else if (verify_save) begin
                            persistent_done <= 1; persistent_failed <= 1;
                        end
                        state <= verify_save ? FINISH : DRAIN;
                    end else if (verify_save) begin
                        ddr_rnw <= 0; ddr_addr <= header_word+1'b1;
                        ddr_din <= {expected_crc,PAYLOAD_BYTES};
                        ddr_req <= ~ddr_req; state <= META_WAIT;
                    end else if (!apply_load) begin
                        orch_start <= 1; state <= CAPTURE;
                    end else begin
                        // DDR CRC alone does not prove the destination accepted
                        // the writes. Keep CPUs held while reading back the image.
                        offset <= 0; lane <= 0; prime <= 0;
                        crc <= 32'hFFFFFFFF; state <= LOAD_CHECK_PRIME;
                    end
                end else begin
                    offset <= offset+1'b1;
                    if (lane == 7) begin lane <= 0; state <= READ_SEND; end
                    else lane <= lane+1'b1;
                end
            end
            LOAD_CHECK_PRIME: begin
                // Same read latency as SAVE, including the registered RAM mux.
                if (prime == 3) begin prime <= 0; state <= LOAD_CHECK_BYTE; end
                else prime <= prime + 1'b1;
            end
            LOAD_CHECK_BYTE: begin
                crc <= crc_byte(crc,mem_dout);
                if (last_byte) begin
                    checked_crc <= ~crc_byte(crc,mem_dout);
                    if (~crc_byte(crc,mem_dout) != expected_crc) begin
                        // The live RAM was already overwritten: recovery reset
                        // is necessary, but retain a distinct diagnostic reason.
                        fail <= 1; pass <= 0; slot_known <= 0;
                        error_code <= 8'h0B; recovery_count <= 9'd511;
                        orch_start <= 0; state <= DRAIN;
                    end else state <= RELEASE;
                end else begin
                    offset <= offset+1'b1; state <= LOAD_CHECK_PRIME;
                end
            end
            META_WAIT: if (ack_sync == ddr_req) begin
                ddr_addr <= control_word+22'd3; ddr_din <= active_rom;
                ddr_req <= ~ddr_req; state <= SAVE_ROM_WAIT;
            end
            SAVE_ROM_WAIT: if (ack_sync == ddr_req) begin
                ddr_addr <= control_word+22'd4; ddr_din <= active_config;
                ddr_req <= ~ddr_req; state <= SAVE_CONFIG_WAIT;
            end
            SAVE_CONFIG_WAIT: if (ack_sync == ddr_req) begin
                ddr_addr <= header_word; ddr_din <= HEADER;
                ddr_req <= ~ddr_req; state <= COMMIT_WAIT;
            end
            COMMIT_WAIT: if (ack_sync == ddr_req) state <= RELEASE;
            RELEASE: begin persistent_done <= 1; state <= FINISH; end
            FINISH: if (!orch_busy) begin
                orch_start <= 0;
                if (orch_fail || !orch_pass || (do_load && sys_fail)) begin
                    fail <= 1; pass <= 0; error_code <= 8'h07; slot_known <= 0;
                    state <= DRAIN;
                end else if (!fail && !do_load) begin
                    // Last write only: Main now has a complete, verified image.
                    // Never publish failed captures or a failed CPU return.
                    ddr_addr <= control_word; ddr_din <= {BODY_WORDS,commit_counter};
                    ddr_rnw <= 0; ddr_req <= ~ddr_req; state <= PUBLISH_WAIT;
                end else begin pass <= !fail; state <= DRAIN; end
            end
            PUBLISH_WAIT: if (ack_sync == ddr_req) begin
                slot_known <= 1; pass <= 1; state <= DRAIN;
            end
            PING_WRITE: if (ack_sync == ddr_req) begin
                ddr_rnw <= 1; ddr_req <= ~ddr_req; state <= PING_READ;
            end
            PING_READ: if (ack_sync == ddr_req) begin
                source_crc <= {16'h5235,ping_index,~ping_index};
                checked_crc <= ddr_dout[31:0];
                if (ddr_dout != ping_pattern(ping_index)) begin
                    fail <= 1; error_code <= 8'h08; state <= DRAIN;
                end else if (ping_index == 255) begin pass <= 1; state <= DRAIN; end
                else begin
                    ping_index <= ping_index+1'b1;
                    ddr_din <= ping_pattern(ping_index+8'd1);
                    ddr_rnw <= 0; ddr_req <= ~ddr_req; state <= PING_WRITE;
                end
            end
            DRAIN: begin
                busy <= 0; orch_start <= 0; probing <= 0; probe_timer <= 1;
                if (ddr_req == ack_sync && !recover_reset) state <= IDLE;
            end
            default: begin
                fail <= 1; error_code <= 8'h09; slot_known <= 0;
                recovery_count <= 9'd511; orch_start <= 0; state <= DRAIN;
            end
        endcase
        // End-to-end bound includes capture, all DDR waits, VBlank and replay.
        // ~2.5 s at MCLK. Never strand FX68K reset or audio/Z80 paused.
        if (&watchdog && state != IDLE && state != DRAIN) begin
            fail <= 1; pass <= 0; error_code <= 8'h0A; slot_known <= 0;
            if (orch_start) recovery_count <= 9'd511;
            orch_start <= 0; state <= DRAIN;
        end
    end
end
endmodule
