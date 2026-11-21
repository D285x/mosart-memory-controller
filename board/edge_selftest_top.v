//============================================================================
// Module      : edge_selftest_top
// Project     : MOSART Project 8 - Programmable Memory Controller
// Author      : Shaun Praneeth Raj (24EG104B27)
// Target      : EDGE Artix-7 board (xc7a35tftg256-1), 50 MHz clock
// Description : Board wrapper for emulation. A built-in sequencer drives the
//               unmodified mem_ctrl_top through a hardware self-test and
//               reports the verdict on four outputs.
//
//   Test sequence (starts automatically after reset)
//     1. program WAIT register (MODE=0 : 0 wait states, MODE=1 : 3)
//     2. write all 16 words with a distinct pattern, check no error
//     3. read all 16 words back and compare
//     4. LIMIT=8, read address 9  -> expect error and STATUS.RANGE set
//     5. clear status, LIMIT=16
//     6. WP=1, write address 0    -> expect error and STATUS.WPV set
//     7. clear status, WP=0, read address 0 -> must still hold the old value
//
//   SERIAL_OUT[0] PASS (LED D3) steady on : all checks passed
//   SERIAL_OUT[1] FAIL      steady on : at least one check failed (sticky)
//   SERIAL_OUT[2] DONE      steady on : sequence finished
//   SERIAL_OUT[3] HEARTBEAT ~1 Hz blink : clock is running
//
//   RST polarity is set by RST_ACTIVE_LOW (default 0 = active high).
//   MODE and RST are sampled through two-flop synchronisers.
//============================================================================
module edge_selftest_top #(
    parameter CLK_HZ        = 50_000_000,
    parameter RST_ACTIVE_LOW = 0
)(
    input  wire       CLK,
    input  wire       RST,
    input  wire       MODE,
    output wire [3:0] SERIAL_OUT
);
    // ---------------- input synchronisers ----------------
    reg [1:0] rst_sync  = 2'b11;
    reg [1:0] mode_sync = 2'b00;
    wire      rst_raw   = RST_ACTIVE_LOW ? ~RST : RST;
    always @(posedge CLK) begin
        rst_sync  <= {rst_sync[0], rst_raw};
        mode_sync <= {mode_sync[0], MODE};
    end
    wire reset  = rst_sync[1];
    wire mode_s = mode_sync[1];

    // ---------------- device under test ----------------
    reg        rd_en = 0, wr_en = 0, cfg_we = 0;
    reg  [3:0] address = 0;
    reg  [7:0] write_data = 0;
    reg  [1:0] cfg_addr = 0;
    reg  [7:0] cfg_wdata = 0;
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

    // ---------------- sequencer ----------------
    function [7:0] pat(input [3:0] i);
        pat = {i, ~i} ^ 8'h5A;
    endfunction

    localparam [4:0]
        ST_INIT    = 0,  ST_GAP     = 1,  ST_CFG     = 2,
        ST_WR_ISS  = 3,  ST_WR_WT   = 4,  ST_RD_ISS  = 5,  ST_RD_WT  = 6,
        ST_LIM_SET = 7,  ST_BAD_ISS = 8,  ST_BAD_WT  = 9,  ST_BAD_CHK = 10,
        ST_LIM_RST = 11, ST_WP_SET  = 12, ST_WPW_ISS = 13, ST_WPW_WT = 14,
        ST_WPW_CHK = 15, ST_WP_RST  = 16, ST_CHK0_ISS = 17, ST_CHK0_WT = 18,
        ST_FIN     = 19;

    reg [4:0] state = ST_INIT, nxt = ST_INIT;
    reg [3:0] idx = 0, gap = 0;
    reg       fail = 0, done = 0;

    task goto(input [4:0] s);
        begin nxt <= s; gap <= 4'd3; state <= ST_GAP; end
    endtask

    always @(posedge CLK) begin
        if (reset) begin
            state <= ST_INIT; nxt <= ST_INIT; idx <= 0; gap <= 0;
            fail <= 0; done <= 0;
            rd_en <= 0; wr_en <= 0; cfg_we <= 0;
            address <= 0; write_data <= 0; cfg_addr <= 0; cfg_wdata <= 0;
        end else begin
            rd_en <= 0; wr_en <= 0; cfg_we <= 0;   // one-cycle pulses
            case (state)
                ST_INIT: begin nxt <= ST_CFG; gap <= 4'd15; state <= ST_GAP; end
                ST_GAP : if (gap == 0) state <= nxt; else gap <= gap - 1'b1;

                ST_CFG: begin
                    cfg_we <= 1; cfg_addr <= 2'd1;
                    cfg_wdata <= mode_s ? 8'd3 : 8'd0;
                    idx <= 0; goto(ST_WR_ISS);
                end

                ST_WR_ISS: begin
                    wr_en <= 1; address <= idx; write_data <= pat(idx);
                    state <= ST_WR_WT;
                end
                ST_WR_WT: if (ready) begin
                    if (error) fail <= 1;
                    if (idx == 4'd15) begin idx <= 0; state <= ST_RD_ISS; end
                    else begin idx <= idx + 1'b1; state <= ST_WR_ISS; end
                end

                ST_RD_ISS: begin
                    rd_en <= 1; address <= idx; state <= ST_RD_WT;
                end
                ST_RD_WT: if (ready) begin
                    if (error || read_data !== pat(idx)) fail <= 1;
                    if (idx == 4'd15) begin idx <= 0; state <= ST_LIM_SET; end
                    else begin idx <= idx + 1'b1; state <= ST_RD_ISS; end
                end

                // ---- range error ----
                ST_LIM_SET: begin
                    cfg_we <= 1; cfg_addr <= 2'd2; cfg_wdata <= 8'd8;
                    goto(ST_BAD_ISS);
                end
                ST_BAD_ISS: begin
                    rd_en <= 1; address <= 4'd9; state <= ST_BAD_WT;
                end
                ST_BAD_WT: if (ready) begin
                    if (!error) fail <= 1;
                    cfg_addr <= 2'd3;              // select STATUS for read-back
                    goto(ST_BAD_CHK);
                end
                ST_BAD_CHK: begin
                    if (!cfg_rdata[1]) fail <= 1;  // RANGE
                    cfg_we <= 1; cfg_addr <= 2'd3; cfg_wdata <= 8'h0F;  // W1C
                    goto(ST_LIM_RST);
                end
                ST_LIM_RST: begin
                    cfg_we <= 1; cfg_addr <= 2'd2; cfg_wdata <= 8'd16;
                    goto(ST_WP_SET);
                end

                // ---- write-protect violation ----
                ST_WP_SET: begin
                    cfg_we <= 1; cfg_addr <= 2'd0; cfg_wdata <= 8'b0000_0011;
                    goto(ST_WPW_ISS);
                end
                ST_WPW_ISS: begin
                    wr_en <= 1; address <= 4'd0; write_data <= 8'hFF;
                    state <= ST_WPW_WT;
                end
                ST_WPW_WT: if (ready) begin
                    if (!error) fail <= 1;
                    cfg_addr <= 2'd3;
                    goto(ST_WPW_CHK);
                end
                ST_WPW_CHK: begin
                    if (!cfg_rdata[2]) fail <= 1;  // WPV
                    cfg_we <= 1; cfg_addr <= 2'd3; cfg_wdata <= 8'h0F;
                    goto(ST_WP_RST);
                end
                ST_WP_RST: begin
                    cfg_we <= 1; cfg_addr <= 2'd0; cfg_wdata <= 8'b0000_0001;
                    goto(ST_CHK0_ISS);
                end

                // ---- rejected write must not have changed the memory ----
                ST_CHK0_ISS: begin
                    rd_en <= 1; address <= 4'd0; state <= ST_CHK0_WT;
                end
                ST_CHK0_WT: if (ready) begin
                    if (error || read_data !== pat(4'd0)) fail <= 1;
                    state <= ST_FIN;
                end

                ST_FIN: done <= 1;
                default: state <= ST_INIT;
            endcase
        end
    end

    // ---------------- heartbeat and outputs ----------------
    reg [31:0] hb_cnt = 0;
    reg        hb = 0;
    always @(posedge CLK) begin
        if (hb_cnt == CLK_HZ/2 - 1) begin hb_cnt <= 0; hb <= ~hb; end
        else hb_cnt <= hb_cnt + 1'b1;
    end

    assign SERIAL_OUT = {hb, done, fail, done & ~fail};
endmodule
