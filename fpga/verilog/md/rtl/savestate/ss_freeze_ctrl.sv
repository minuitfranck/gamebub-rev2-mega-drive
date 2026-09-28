// Genesis_MiSTer save-state work - v0.1
// Minimal safe-freeze handshake.
// This DOES NOT serialize or restore state yet.

module ss_freeze_ctrl
(
    input  wire clk,
    input  wire reset,
    input  wire req,
    input  wire safe_point,
    output reg  hold,
    output wire ack
);

assign ack = hold;

always @(posedge clk) begin
    if (reset) begin
        hold <= 1'b0;
    end
    else begin
        if (!req) begin
            hold <= 1'b0;
        end
        else if (!hold && safe_point) begin
            hold <= 1'b1;
        end
    end
end

endmodule
