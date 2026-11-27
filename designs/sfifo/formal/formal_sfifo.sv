// Formal properties for sfifo (OPT_ASYNC_READ = 0, OPT_WRITE_ON_FULL = 0, OPT_READ_ON_EMPTY = 0).
// Written in terms of the ports only, against a shadow model of the specification:
//   * a write is accepted when the FIFO is not full, a read when it is not empty;
//   * o_fill is the number of stored entries, o_full = (o_fill == FLEN), o_empty = (o_fill == 0);
//   * entries leave in the order they entered, and o_data shows the oldest entry while not empty.
// Ordering is checked by tracking one entry: the solver picks a write number f_n (anyconst);
// the data of that write is recorded, and when that entry is the oldest one o_data must equal it.
`default_nettype none
module formal_sfifo #(
    parameter BW     = 2,
    parameter LGFLEN = 2
)(
    input wire clk
);
    localparam FLEN = (1 << LGFLEN);
    localparam CW = 6;                       // write/read sequence counters, wider than the bmc depth needs

    (* anyseq *)   wire          reset;
    (* anyseq *)   wire          i_wr;
    (* anyseq *)   wire          i_rd;
    (* anyseq *)   wire [BW-1:0] i_data;
    (* anyconst *) wire [CW-1:0] f_n;

    wire [BW-1:0]   o_data;
    wire            o_full, o_empty;
    wire [LGFLEN:0] o_fill;

    sfifo #(.BW(BW), .LGFLEN(LGFLEN), .OPT_ASYNC_READ(1'b0),
            .OPT_WRITE_ON_FULL(1'b0), .OPT_READ_ON_EMPTY(1'b0)) dut (
        .i_clk(clk), .i_reset(reset),
        .i_wr(i_wr), .i_data(i_data), .o_full(o_full), .o_fill(o_fill),
        .i_rd(i_rd), .o_data(o_data), .o_empty(o_empty));

    reg f_past_valid = 1'b0;
    always @(posedge clk) f_past_valid <= 1'b1;
    always @(*) if (!f_past_valid) assume (reset);

    // shadow model
    reg [LGFLEN:0] c  = 0;                   // number of entries
    reg [CW-1:0]   wn = 0, rn = 0;           // accepted writes and reads since reset
    reg [BW-1:0]   f_data = 0;
    reg            f_seen = 1'b0;            // tracked write has happened
    wire wacc = i_wr && (c < FLEN);
    wire racc = i_rd && (c != 0);

    always @(posedge clk) begin
        if (reset) begin
            c <= 0; wn <= 0; rn <= 0; f_seen <= 1'b0;
        end else begin
            c  <= c + wacc - racc;
            wn <= wn + wacc;
            rn <= rn + racc;
            if (wacc && wn == f_n) begin f_data <= i_data; f_seen <= 1'b1; end
        end
    end

    // the tracked entry is stored and is the oldest one
    wire f_head = f_seen && (rn == f_n);

    always @(posedge clk) if (f_past_valid && !reset) begin
        // S1 to S3: occupancy and flags
        assert (o_fill  == c);
        assert (o_full  == (c == FLEN));
        assert (o_empty == (c == 0));
        // S4: order and data: the oldest entry is presented on o_data
        if (f_head && !o_empty) assert (o_data == f_data);
    end

    // the interesting behaviours are reachable
    always @(posedge clk) if (f_past_valid && !reset) begin
        cover (o_full);
        cover (f_head && i_rd && !o_empty);
        cover (f_head && c == FLEN);
        cover (i_wr && i_rd && c == FLEN);
        cover (wn == FLEN + 2);              // write pointer wrapped
    end
endmodule
