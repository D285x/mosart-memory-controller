//============================================================================
// Module      : seg7_driver
// Description : Time-multiplexed driver for the 4-digit common-anode display
//               of the EDGE Artix-7 board (digit enables active high, segment
//               lines active low, DP is bit 7 of seg).
//   Character codes : 0 to 9 = digits, 4'hA = blank, 4'hB = dash
//   c0 is the leftmost digit (DISP1), c3 the rightmost (DISP4).
//   dp[i] lights the decimal point of digit i.
//   SCAN_BITS sets the per-digit dwell time: 2**SCAN_BITS clock cycles
//   (16 gives about 1.3 ms per digit at 50 MHz, a 190 Hz frame rate).
//============================================================================
module seg7_driver #(
    parameter SCAN_BITS = 16
)(
    input  wire       clk,
    input  wire [3:0] c0, c1, c2, c3,
    input  wire [3:0] dp,
    output reg  [3:0] digit,
    output reg  [7:0] seg
);
    reg [SCAN_BITS+1:0] scan = 0;
    always @(posedge clk) scan <= scan + 1'b1;
    wire [1:0] sel = scan[SCAN_BITS+1:SCAN_BITS];

    reg [3:0] code;
    reg       dpb;
    always @(*) begin
        case (sel)
            2'd0: begin code = c0; dpb = dp[0]; end
            2'd1: begin code = c1; dpb = dp[1]; end
            2'd2: begin code = c2; dpb = dp[2]; end
            default: begin code = c3; dpb = dp[3]; end
        endcase
    end

    reg [6:0] pat;                       // {g,f,e,d,c,b,a}, 1 = lit
    always @(*) begin
        case (code)
            4'd0: pat = 7'h3F;  4'd1: pat = 7'h06;  4'd2: pat = 7'h5B;
            4'd3: pat = 7'h4F;  4'd4: pat = 7'h66;  4'd5: pat = 7'h6D;
            4'd6: pat = 7'h7D;  4'd7: pat = 7'h07;  4'd8: pat = 7'h7F;
            4'd9: pat = 7'h6F;  4'hB: pat = 7'h40;
            default: pat = 7'h00;
        endcase
    end

    always @(posedge clk) begin
        digit <= 4'b0001 << sel;
        seg   <= {~dpb, ~pat};
    end
endmodule
