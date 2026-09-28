// Genesis_MiSTer Save-State project
// v0.8 - FX68K architectural save/reset/restore controller.
//
// Manual v0.7 mode:
//   start=1, orchestrated=0 -> save -> reset -> restore -> RTE automatically.
//
// v0.8 orchestrated mode:
//   start=1, orchestrated=1 -> save -> hold FX68K in reset after SSP capture.
//   capture_ready remains high until restore_req is asserted.
//   Then custom reset-vector restore -> RTE -> normal game code.

module ss_m68k_handler_test
(
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire        safe_start,
    input  wire        m68k_ce,

    input  wire        orchestrated,
    input  wire        restore_req,
    input  wire        slot_we,
    input  wire [1:0]  slot_addr,
    input  wire [7:0]  slot_din,
    output wire        capture_start,
    output wire        capture_ready,

    input  wire [23:0] m68k_addr,
    input  wire [15:0] m68k_dout,
    input  wire        m68k_as_n,
    input  wire [1:0]  m68k_ds_n,
    input  wire        m68k_rw,
    input  wire [2:0]  m68k_fc,
    input  wire        m68k_dtack_n,
    input  wire        m68k_intack,

    output reg         irq7,
    output reg         cpu_reset,
    output reg         pause_aux,
    output wire        din_en,
    output reg  [15:0] din_data,

    output reg         busy,
    output reg         pass,
    output reg         fail,
    output reg  [31:0] saved_ssp,
    // Game Bub: the state machine, for the save-state diagnostics register.
    output wire [3:0]  dbg_state
);

localparam [23:0] HANDLER_BASE = 24'hA14000;
localparam [23:0] RESTORE_PC   = 24'hA14008;
localparam [23:0] SCRATCH_BASE = 24'hA14100;

localparam [3:0]
    ST_IDLE          = 4'd0,
    ST_WAIT_SAFE     = 4'd1,
    ST_WAIT_IACK     = 4'd2,
    ST_WAIT_SSP      = 4'd3,
    ST_RESET_HOLD    = 4'd4,
    ST_RESET_BOOT    = 4'd5,
    ST_WAIT_RETURN   = 4'd6,
    ST_DONE          = 4'd7,
    ST_HOLD_SNAPSHOT = 4'd8;

localparam [25:0] TIMEOUT_MAX = 26'h3FFFFFF;

reg [3:0]  state;
reg        armed;
reg [25:0] timeout_cnt;
reg [4:0]  reset_ce_cnt;

reg ssp_hi_seen, ssp_lo_seen;
reg rst_ssp_hi_seen, rst_ssp_lo_seen;
reg rst_pc_hi_seen, rst_pc_lo_seen;
reg restore_handler_seen;

assign capture_start = (state == ST_WAIT_SAFE) && safe_start;
assign capture_ready = (state == ST_HOLD_SNAPSHOT);

wire active = (state != ST_IDLE) && (state != ST_DONE);

wire handler_sel =
    active && !m68k_as_n && m68k_rw &&
    (m68k_addr[23:5] == HANDLER_BASE[23:5]);

wire irq_vector_sel =
    (state == ST_WAIT_IACK || state == ST_WAIT_SSP) &&
    !m68k_as_n && m68k_rw &&
    ((m68k_addr == 24'h00007C) || (m68k_addr == 24'h00007E));

wire reset_vector_sel =
    (state == ST_RESET_HOLD || state == ST_RESET_BOOT ||
     state == ST_HOLD_SNAPSHOT) &&
    !m68k_as_n && m68k_rw &&
    (m68k_addr[23:3] == 21'd0);

assign din_en = handler_sel || irq_vector_sel || reset_vector_sel;

wire scratch_hi_commit =
    (state == ST_WAIT_SSP) &&
    !m68k_as_n && !m68k_rw && !m68k_dtack_n &&
    (m68k_ds_n == 2'b00) &&
    (m68k_addr == SCRATCH_BASE);

wire scratch_lo_commit =
    (state == ST_WAIT_SSP) &&
    !m68k_as_n && !m68k_rw && !m68k_dtack_n &&
    (m68k_ds_n == 2'b00) &&
    (m68k_addr == (SCRATCH_BASE + 24'd2));

wire reset_vector_commit =
    (state == ST_RESET_BOOT) &&
    reset_vector_sel && !m68k_dtack_n;

wire restore_handler_commit =
    (state == ST_RESET_BOOT || state == ST_WAIT_RETURN) &&
    handler_sel && !m68k_dtack_n &&
    (m68k_addr == RESTORE_PC);

wire program_fetch_outside_handler =
    (state == ST_RESET_BOOT || state == ST_WAIT_RETURN) &&
    !m68k_as_n && m68k_rw && !m68k_dtack_n &&
    ((m68k_fc == 3'b010) || (m68k_fc == 3'b110)) &&
    !handler_sel &&
    (m68k_addr[23:3] != 21'd0);

function automatic [15:0] handler_word(input [3:0] idx);
begin
    case (idx)
        4'd0:  handler_word = 16'h48E7; // movem.l d0-d7/a0-a6,-(a7)
        4'd1:  handler_word = 16'hFFFE;
        4'd2:  handler_word = 16'h4E6E; // move.l usp,a6
        4'd3:  handler_word = 16'h2F0E; // move.l a6,-(a7)
        4'd4:  handler_word = 16'h4DF9; // lea $00A14100,a6
        4'd5:  handler_word = 16'h00A1;
        4'd6:  handler_word = 16'h4100;
        4'd7:  handler_word = 16'h2C8F; // move.l a7,(a6)
        4'd8:  handler_word = 16'h2C5F; // move.l (a7)+,a6
        4'd9:  handler_word = 16'h4E66; // move.l a6,usp
        4'd10: handler_word = 16'h4CDF; // movem.l (a7)+,d0-d7/a0-a6
        4'd11: handler_word = 16'h7FFF;
        4'd12: handler_word = 16'h4E73; // rte
        default: handler_word = 16'h4E71;
    endcase
end
endfunction

always @* begin
    if (reset_vector_sel) begin
        case (m68k_addr[2:1])
            2'd0: din_data = saved_ssp[31:16];
            2'd1: din_data = saved_ssp[15:0];
            2'd2: din_data = {8'h00, RESTORE_PC[23:16]};
            default: din_data = RESTORE_PC[15:0];
        endcase
    end
    else if (irq_vector_sel)
        din_data = (m68k_addr[1] == 1'b0) ? 16'h00A1 : 16'h4000;
    else
        din_data = handler_word(m68k_addr[4:1]);
end

always @(posedge clk) begin
    if (reset) begin
        state                <= ST_IDLE;
        armed                <= 1'b1;
        timeout_cnt          <= 26'd0;
        reset_ce_cnt         <= 5'd0;
        irq7                 <= 1'b0;
        cpu_reset            <= 1'b0;
        pause_aux            <= 1'b0;
        busy                 <= 1'b0;
        pass                 <= 1'b0;
        fail                 <= 1'b0;
        saved_ssp            <= 32'd0;
        ssp_hi_seen          <= 1'b0;
        ssp_lo_seen          <= 1'b0;
        rst_ssp_hi_seen      <= 1'b0;
        rst_ssp_lo_seen      <= 1'b0;
        rst_pc_hi_seen       <= 1'b0;
        rst_pc_lo_seen       <= 1'b0;
        restore_handler_seen <= 1'b0;
    end
    else begin
        if (!start)
            armed <= 1'b1;

        case (state)
            ST_IDLE: begin
                irq7        <= 1'b0;
                cpu_reset   <= 1'b0;
                pause_aux   <= 1'b0;
                busy        <= 1'b0;
                timeout_cnt <= 26'd0;
                // Game Bub: a result belongs to the request that produced it. Once the requester
                // has dropped `start`, clear it: the orchestrator looks at `fail` on the clock after
                // it raises `start`, one clock before this machine accepts the request and would
                // clear a stale failure itself, so a failed attempt made every later one fail at once.
                if (!start) begin
                    pass <= 1'b0;
                    fail <= 1'b0;
                end

                if (start && armed) begin
                    armed                <= 1'b0;
                    pass                 <= 1'b0;
                    fail                 <= 1'b0;
                    saved_ssp            <= 32'd0;
                    ssp_hi_seen          <= 1'b0;
                    ssp_lo_seen          <= 1'b0;
                    rst_ssp_hi_seen      <= 1'b0;
                    rst_ssp_lo_seen      <= 1'b0;
                    rst_pc_hi_seen       <= 1'b0;
                    rst_pc_lo_seen       <= 1'b0;
                    restore_handler_seen <= 1'b0;
                    busy                 <= 1'b1;
                    state                <= ST_WAIT_SAFE;
                end
            end

            ST_WAIT_SAFE: begin
                if (safe_start) begin
                    // Z80/FM/PSG stop here. The 68000 stays clocked to enter IRQ7.
                    pause_aux   <= 1'b1;
                    irq7        <= 1'b1;
                    timeout_cnt <= 26'd0;
                    state       <= ST_WAIT_IACK;
                end
                else if (timeout_cnt == TIMEOUT_MAX) begin
                    busy <= 1'b0;
                    fail <= 1'b1;
                    state <= ST_DONE;
                end
                else timeout_cnt <= timeout_cnt + 1'b1;
            end

            ST_WAIT_IACK: begin
                if (m68k_intack && !m68k_as_n) begin
                    irq7        <= 1'b0;
                    timeout_cnt <= 26'd0;
                    state       <= ST_WAIT_SSP;
                end
                else if (timeout_cnt == TIMEOUT_MAX) begin
                    irq7 <= 1'b0;
                    pause_aux <= 1'b0;
                    busy <= 1'b0;
                    fail <= 1'b1;
                    state <= ST_DONE;
                end
                else timeout_cnt <= timeout_cnt + 1'b1;
            end

            ST_WAIT_SSP: begin
                if (scratch_hi_commit) begin
                    saved_ssp[31:16] <= m68k_dout;
                    ssp_hi_seen <= 1'b1;
                end

                if (scratch_lo_commit) begin
                    saved_ssp[15:0] <= m68k_dout;
                    ssp_lo_seen <= 1'b1;
                end

                if ((ssp_hi_seen || scratch_hi_commit) &&
                    (ssp_lo_seen || scratch_lo_commit)) begin
                    cpu_reset    <= 1'b1;
                    timeout_cnt  <= 26'd0;

                    if (orchestrated) begin
                        // The orchestrator will scan state while FX68K remains
                        // reset and Z80/audio remain paused.
                        state <= ST_HOLD_SNAPSHOT;
                    end
                    else begin
                        reset_ce_cnt <= 5'd0;
                        state <= ST_RESET_HOLD;
                    end
                end
                else if (timeout_cnt == TIMEOUT_MAX) begin
                    pause_aux <= 1'b0;
                    busy <= 1'b0;
                    fail <= 1'b1;
                    state <= ST_DONE;
                end
                else timeout_cnt <= timeout_cnt + 1'b1;
            end

            ST_HOLD_SNAPSHOT: begin
                if (slot_we)
                    saved_ssp[{slot_addr,3'b000} +: 8] <= slot_din;
                cpu_reset  <= 1'b1;
                pause_aux  <= 1'b1;
                irq7       <= 1'b0;

                if (restore_req) begin
                    // Reset has already been held for far longer than the
                    // conservative 32 CE events used by manual v0.7.
                    cpu_reset   <= 1'b0;
                    timeout_cnt <= 26'd0;
                    state       <= ST_RESET_BOOT;
                end
            end

            ST_RESET_HOLD: begin
                if (m68k_ce) begin
                    reset_ce_cnt <= reset_ce_cnt + 1'b1;
                    if (&reset_ce_cnt) begin
                        cpu_reset   <= 1'b0;
                        timeout_cnt <= 26'd0;
                        state       <= ST_RESET_BOOT;
                    end
                end
            end

            ST_RESET_BOOT: begin
                if (reset_vector_commit) begin
                    case (m68k_addr[2:1])
                        2'd0: rst_ssp_hi_seen <= 1'b1;
                        2'd1: rst_ssp_lo_seen <= 1'b1;
                        2'd2: rst_pc_hi_seen  <= 1'b1;
                        2'd3: rst_pc_lo_seen  <= 1'b1;
                    endcase
                end

                if (restore_handler_commit)
                    restore_handler_seen <= 1'b1;

                if (restore_handler_seen || restore_handler_commit) begin
                    timeout_cnt <= 26'd0;
                    state <= ST_WAIT_RETURN;
                end
                else if (timeout_cnt == TIMEOUT_MAX) begin
                    pause_aux <= 1'b0;
                    busy <= 1'b0;
                    fail <= 1'b1;
                    state <= ST_DONE;
                end
                else timeout_cnt <= timeout_cnt + 1'b1;
            end

            ST_WAIT_RETURN: begin
                if (program_fetch_outside_handler) begin
                    pause_aux <= 1'b0;
                    busy      <= 1'b0;

                    if (rst_ssp_hi_seen && rst_ssp_lo_seen &&
                        rst_pc_hi_seen && rst_pc_lo_seen &&
                        restore_handler_seen) begin
                        pass <= 1'b1;
                        fail <= 1'b0;
                    end
                    else begin
                        pass <= 1'b0;
                        fail <= 1'b1;
                    end

                    state <= ST_DONE;
                end
                else if (timeout_cnt == TIMEOUT_MAX) begin
                    pause_aux <= 1'b0;
                    busy <= 1'b0;
                    fail <= 1'b1;
                    state <= ST_DONE;
                end
                else timeout_cnt <= timeout_cnt + 1'b1;
            end

            ST_DONE: begin
                irq7       <= 1'b0;
                cpu_reset  <= 1'b0;
                pause_aux  <= 1'b0;

                if (!start) begin
                    pass  <= 1'b0; // Game Bub: see ST_IDLE
                    fail  <= 1'b0;
                    state <= ST_IDLE;
                end
            end

            default: state <= ST_IDLE;
        endcase
    end
end

assign dbg_state = state;

endmodule
