// Port-level miter for mem_ctrl_top (DATA_W 2, ADDR_W 3), used only to cross-check the
// SymbiYosys miter route of flow.py against the yosys sat results of mutate.py.
module miter_top(input wire clk);
    (* anyseq *) wire rst, re, we, cwe; (* anyseq *) wire [2:0] a; (* anyseq *) wire [1:0] wd, ca; (* anyseq *) wire [7:0] cwd;
    wire [1:0] grd, mrd; wire [7:0] gcr, mcr; wire gr, gb, ge, mr, mb, me;
    orig_mem_ctrl_top #(.DATA_W(2), .ADDR_W(3)) g (.clk(clk), .reset(rst), .read_enable(re), .write_enable(we), .address(a),
        .write_data(wd), .read_data(grd), .ready(gr), .busy(gb), .error(ge), .cfg_we(cwe), .cfg_addr(ca), .cfg_wdata(cwd), .cfg_rdata(gcr));
    mut_mem_ctrl_top #(.DATA_W(2), .ADDR_W(3)) m (.clk(clk), .reset(rst), .read_enable(re), .write_enable(we), .address(a),
        .write_data(wd), .read_data(mrd), .ready(mr), .busy(mb), .error(me), .cfg_we(cwe), .cfg_addr(ca), .cfg_wdata(cwd), .cfg_rdata(mcr));
    reg pv = 0; always @(posedge clk) pv <= 1;
    always @(*) if (!pv) assume (rst);
    always @(posedge clk) if (pv && !rst) assert (grd == mrd && gcr == mcr && gr == mr && gb == mb && ge == me);
endmodule
