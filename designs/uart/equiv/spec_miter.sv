// Specification miter for the uart top level: original and mutant side by side from reset, with
// prescale = 1 and DATA_WIDTH = 2, all other inputs free. Every output must match every cycle,
// except m_axis_tdata, which is specified only while m_axis_tvalid is high.
module miter_top(input wire clk);
    (* anyseq *) wire rst, s_tvalid, m_tready, rxd;
    (* anyseq *) wire [1:0] s_tdata;
    wire g_tr, g_tv, g_txd, g_tb, g_rb, g_ov, g_fe, m_tr, m_tv, m_txd, m_tb, m_rb, m_ov, m_fe;
    wire [1:0] g_td, m_td;
    orig_uart #(.DATA_WIDTH(2)) g (.clk(clk), .rst(rst), .s_axis_tdata(s_tdata), .s_axis_tvalid(s_tvalid),
        .s_axis_tready(g_tr), .m_axis_tdata(g_td), .m_axis_tvalid(g_tv), .m_axis_tready(m_tready), .rxd(rxd),
        .txd(g_txd), .tx_busy(g_tb), .rx_busy(g_rb), .rx_overrun_error(g_ov), .rx_frame_error(g_fe), .prescale(16'd1));
    mut_uart #(.DATA_WIDTH(2)) m (.clk(clk), .rst(rst), .s_axis_tdata(s_tdata), .s_axis_tvalid(s_tvalid),
        .s_axis_tready(m_tr), .m_axis_tdata(m_td), .m_axis_tvalid(m_tv), .m_axis_tready(m_tready), .rxd(rxd),
        .txd(m_txd), .tx_busy(m_tb), .rx_busy(m_rb), .rx_overrun_error(m_ov), .rx_frame_error(m_fe), .prescale(16'd1));
    reg pv = 0; always @(posedge clk) pv <= 1;
    always @(*) if (!pv) assume (rst);
    always @(posedge clk) if (pv && !rst) begin
        assert (g_tr == m_tr && g_tv == m_tv && g_txd == m_txd && g_tb == m_tb && g_rb == m_rb && g_ov == m_ov && g_fe == m_fe);
        if (g_tv) assert (g_td == m_td);
    end
endmodule
