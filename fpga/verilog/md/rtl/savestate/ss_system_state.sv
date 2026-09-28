// v1.5: one immutable 252-bit diagnostic image; no RAM inference needed.
// No live-state mutation occurs here. Owners load saved_state on restore_apply.
module ss_system_state (
    input wire clk, reset, begin_capture, capture_safe, restore_req,
    input wire [251:0] live_state,
    input wire slot_we,
    input wire [4:0] slot_addr,
    input wire [7:0] slot_din,
    output reg [251:0] saved_state,
    output wire restore_apply,
    output reg pass, fail,
    input wire [5:0] read_addr,
    output reg [7:0] read_data
);
reg pending, valid, check_pending;
wire [255:0] image_bytes = {4'b0, saved_state};
wire [4:0] byte_index = read_addr[4:0] - 5'd8;
assign restore_apply = restore_req && valid && !reset;
always @(posedge clk) begin
    if (reset) begin
        pending <= 0;
        valid <= 0;
        check_pending <= 0;
        pass <= 0;
        fail <= 0;
        saved_state <= 0;
    end else if (begin_capture) begin
        pending <= 1;
        valid <= 0;
        check_pending <= 0;
        pass <= 0;
        fail <= 0;
    end else begin
        if (pending && capture_safe) begin
            saved_state <= live_state;
            pending <= 0;
            valid <= 1;
        end
        if (slot_we) begin
            if (slot_addr == 31) saved_state[251:248] <= slot_din[3:0];
            else saved_state[{slot_addr,3'b000} +: 8] <= slot_din;
            valid <= 1;
        end
        if (restore_req) begin
            check_pending <= valid;
            pass <= 0;
            fail <= !valid;
        end else if (check_pending) begin
            // Observe the owners' NBA loads before their next normal update.
            check_pending <= 0;
            pass <= (live_state == saved_state);
            fail <= (live_state != saved_state);
        end
    end
end
// Synchronous read, matching SS_MEM_ADDR's existing one-clock tag pipeline.
// 30340 version; 30341 flags; 30342 size; 30348..30367 little-endian payload.
always @(posedge clk) begin
    case (read_addr)
        6'h00: read_data <= 8'h15;
        6'h01: read_data <= {3'b0, check_pending, pending, valid, fail, pass};
        6'h02: read_data <= 8'd32;
        default: begin
            if (read_addr >= 6'h08 && read_addr <= 6'h27)
                read_data <= image_bytes[{byte_index, 3'b000} +: 8];
            else read_data <= 0;
        end
    endcase
end
endmodule
