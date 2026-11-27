//============================================================================
// Module      : edge_latency_top
// Project     : Programmable Memory Controller (MOSART Project 8)
// Target      : EDGE Artix-7 board (xc7a35tftg256-1), 50 MHz clock
// Description : Hardware measurement of the access latency and throughput of
//               the unmodified mem_ctrl_top. A sweep engine programs each wait
//               state setting N = 0 to 7 in turn and, with a cycle counter,
//               measures
//                 L_w : cycles from a single write request to ready
//                 L_r : cycles from a single read request to ready
//                 T   : cycles taken by 16 back-to-back reads
//               and checks every result against the design equations
//                 L = 2 + N,   T = 16 * (3 + N)
//               and every read value against the data written.
//
//   Controls
//     pb[4] (centre button)  restart the measurement
//     sw[2:0]                wait-state setting N to display
//     sw[4:3]                quantity: 0 = L_r, 1 = L_w, 2 = T, 3 = T / 16
//   Display (4-digit, left to right): N, then the value in decimal.
//     One clock cycle is 20 ns, so a latency of L cycles is 20 * L ns.
//   LEDs
//     led[0] PASS  all measurements match the equations and all data correct
//     led[1] FAIL  any mismatch (sticky)
//     led[2] DONE  sweep finished
//     led[3] heartbeat, about 1 Hz
//     led[5:4] sw[4:3], led[6] = 0, led[7] = 0
//     led[15:8] displayed value in binary
//============================================================================
module edge_latency_top #(
    parameter CLK_HZ    = 50_000_000,
    parameter SCAN_BITS = 16
)(
    input  wire        CLK,
    input  wire [15:0] sw,
    input  wire [4:0]  pb,
    output wire [15:0] led,
    output wire [3:0]  digit,
    output wire [7:0]  Seven_Seg
);
    // ---------------- input synchronisers ----------------
    reg [1:0] rst_sync = 2'b11;
    reg [4:0] sw_s0 = 0, sw_s1 = 0;
    always @(posedge CLK) begin
        rst_sync <= {rst_sync[0], pb[4]};
        sw_s0    <= sw[4:0];
        sw_s1    <= sw_s0;
    end
    wire       reset = rst_sync[1];
    wire [2:0] sel_n = sw_s1[2:0];
    wire [1:0] sel_q = sw_s1[4:3];

    // ---------------- device under test ----------------
    wire       rd_en, wr_en, cfg_we;
    wire [3:0] address = 4'd0;
    wire [7:0] write_data = 8'hA5;
    wire [1:0] cfg_addr = 2'd1;
    reg  [2:0] n = 3'd0;
    wire [7:0] cfg_wdata = {5'b0, n};
    wire [7:0] read_data, cfg_rdata;
    wire       ready, busy, error;

    mem_ctrl_top #(.DATA_W(8), .ADDR_W(4)) u_dut (
        .clk(CLK), .reset(reset),
        .read_enable(rd_en), .write_enable(wr_en),
        .address(address), .write_data(write_data), .read_data(read_data),
        .ready(ready), .busy(busy), .error(error),
        .cfg_we(cfg_we), .cfg_addr(cfg_addr),
        .cfg_wdata(cfg_wdata), .cfg_rdata(cfg_rdata)
    );

    // ---------------- measurement engine ----------------
    localparam [3:0]
        S_INIT = 0, S_GAP = 1, S_CFG = 2, S_REQW = 3, S_WAITW = 4,
        S_REQR = 5, S_WAITR = 6, S_TP = 7, S_NEXT = 8, S_DONE = 9;

    reg [3:0] state = S_INIT, nxt = S_INIT;
    reg [3:0] gap = 0;
    reg [7:0] cnt = 0, tcnt = 0;
    reg [4:0] issued = 0, ndone = 0;
    reg       bad = 0, done = 0;

    reg [7:0] lat_w [0:7];
    reg [7:0] lat_r [0:7];
    reg [7:0] tp    [0:7];

    // requests are presented in the cycle in which the controller is idle, so
    // a request is accepted in the very cycle it is made
    assign wr_en  = (state == S_REQW) && !busy;
    assign rd_en  = ((state == S_REQR) && !busy) ||
                    ((state == S_TP) && !busy && (issued < 5'd16));
    assign cfg_we = (state == S_CFG);

    wire [7:0] exp_lat = {5'b0, n} + 8'd2;
    wire [7:0] exp_tp  = ({5'b0, n} + 8'd3) << 4;

    always @(posedge CLK) begin
        if (reset) begin
            state <= S_INIT; nxt <= S_INIT; gap <= 0; n <= 0;
            cnt <= 0; tcnt <= 0; issued <= 0; ndone <= 0;
            bad <= 0; done <= 0;
        end else begin
            case (state)
                S_INIT: begin nxt <= S_CFG; gap <= 4'd15; state <= S_GAP; end
                S_GAP : if (gap == 0) state <= nxt; else gap <= gap - 1'b1;

                S_CFG : begin nxt <= S_REQW; gap <= 4'd3; state <= S_GAP; end

                S_REQW: if (!busy) begin state <= S_WAITW; cnt <= 8'd1; end
                S_WAITW: begin
                    cnt <= cnt + 1'b1;
                    if (ready) begin
                        lat_w[n] <= cnt;
                        if (cnt != exp_lat || error) bad <= 1'b1;
                        nxt <= S_REQR; gap <= 4'd3; state <= S_GAP;
                    end
                end

                S_REQR: if (!busy) begin state <= S_WAITR; cnt <= 8'd1; end
                S_WAITR: begin
                    cnt <= cnt + 1'b1;
                    if (ready) begin
                        lat_r[n] <= cnt;
                        if (cnt != exp_lat || error || read_data != 8'hA5) bad <= 1'b1;
                        tcnt <= 0; issued <= 0; ndone <= 0;
                        nxt <= S_TP; gap <= 4'd3; state <= S_GAP;
                    end
                end

                S_TP: begin
                    tcnt <= tcnt + 1'b1;
                    if (rd_en) issued <= issued + 1'b1;
                    if (ready) begin
                        ndone <= ndone + 1'b1;
                        if (error || read_data != 8'hA5) bad <= 1'b1;
                        if (ndone == 5'd15) begin
                            tp[n] <= tcnt + 1'b1;
                            if ((tcnt + 1'b1) != exp_tp) bad <= 1'b1;
                            nxt <= S_NEXT; gap <= 4'd3; state <= S_GAP;
                        end
                    end
                end

                S_NEXT: begin
                    if (n == 3'd7) begin done <= 1'b1; state <= S_DONE; end
                    else begin n <= n + 1'b1; state <= S_CFG; end
                end

                default: state <= S_DONE;
            endcase
        end
    end

    // ---------------- selected value and display ----------------
    reg [7:0] value;
    always @(*) begin
        case (sel_q)
            2'd0: value = lat_r[sel_n];
            2'd1: value = lat_w[sel_n];
            2'd2: value = tp[sel_n];
            default: value = {4'b0, tp[sel_n][7:4]};
        endcase
    end

    wire [3:0] hund = value / 100;
    wire [3:0] tens = (value / 10) % 10;
    wire [3:0] ones = value % 10;

    wire [3:0] c0 = done ? {1'b0, sel_n} : 4'hB;
    wire [3:0] c1 = !done ? 4'hB : (hund == 0) ? 4'hA : hund;
    wire [3:0] c2 = !done ? 4'hB : (hund == 0 && tens == 0) ? 4'hA : tens;
    wire [3:0] c3 = !done ? 4'hB : ones;

    seg7_driver #(.SCAN_BITS(SCAN_BITS)) u_seg (
        .clk(CLK), .c0(c0), .c1(c1), .c2(c2), .c3(c3),
        .dp(4'b0001), .digit(digit), .seg(Seven_Seg)
    );

    // ---------------- LEDs ----------------
    reg [31:0] hb_cnt = 0;
    reg        hb = 0;
    always @(posedge CLK) begin
        if (hb_cnt == CLK_HZ/2 - 1) begin hb_cnt <= 0; hb <= ~hb; end
        else hb_cnt <= hb_cnt + 1'b1;
    end

    assign led = {done ? value : 8'h00, 2'b00, sel_q, hb, done, bad, done & ~bad};
endmodule
