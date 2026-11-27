// Port-level miter for sfifo: original and mutant side by side from reset (BW 2, LGFLEN 2).
// Every output must match every cycle after reset.
module miter_top(input wire clk);
    (* anyseq *) wire rst, wr, rd; (* anyseq *) wire [1:0] d;
    wire [1:0] go, mo; wire gf, ge, mf, me; wire [2:0] gl, ml;
    orig_sfifo #(.BW(2),.LGFLEN(2),.OPT_ASYNC_READ(1'b0)) g(.i_clk(clk),.i_reset(rst),.i_wr(wr),.i_data(d),.o_full(gf),.o_fill(gl),.i_rd(rd),.o_data(go),.o_empty(ge));
    mut_sfifo  #(.BW(2),.LGFLEN(2),.OPT_ASYNC_READ(1'b0)) m(.i_clk(clk),.i_reset(rst),.i_wr(wr),.i_data(d),.o_full(mf),.o_fill(ml),.i_rd(rd),.o_data(mo),.o_empty(me));
    reg pv = 0; always @(posedge clk) pv <= 1;
    always @(*) if (!pv) assume(rst);
    always @(posedge clk) if (pv && !rst) begin
        assert(gf == mf && ge == me && gl == ml);
        assert(go == mo);
    end
endmodule
