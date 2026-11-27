// Formal properties for the uart top level (uart_tx + uart_rx), DATA_WIDTH = 2, prescale = 1
// (bit period 8 clock cycles). Written against the ports and a shadow model of the
// specification: 8N1-style framing (start bit 0, DATA_WIDTH data bits LSB first, stop bit 1),
// each bit lasting 8 * prescale cycles.
//   Transmit: after a handshake on s_axis, txd shows the frame of that byte with exact bit
//   timing; s_axis_tready stays low and tx_busy high for the whole frame; txd idles at 1;
//   the transmitter is ready again shortly after the stop bit.
//   Receive: rxd is driven by a shadow transmitter that sends well-formed frames with free data,
//   a free stop-bit value and free idle gaps. A good frame must be delivered on m_axis with its
//   data (or flagged as an overrun if the previous byte was not taken); a frame whose stop bit is
//   low must raise frame_error and deliver nothing; no event may occur outside a frame.
`default_nettype none
module formal_uart #(
    parameter W = 2
)(
    input wire clk
);
    localparam P  = 1;                        // prescale
    localparam BP = 8 * P;                    // bit period in cycles
    localparam FL = (W + 2) * BP;             // frame length in cycles

    (* anyseq *) wire         rst;
    (* anyseq *) wire [W-1:0] s_tdata;
    (* anyseq *) wire         s_tvalid;
    (* anyseq *) wire         m_tready;
    (* anyseq *) wire         go;             // shadow transmitter starts a frame when idle
    (* anyseq *) wire [W-1:0] go_data;
    (* anyseq *) wire         go_stop;

    wire         s_tready, m_tvalid, txd, tx_busy, rx_busy, ovr, ferr;
    wire [W-1:0] m_tdata;
    reg          rxd = 1'b1;

    uart #(.DATA_WIDTH(W)) dut (
        .clk(clk), .rst(rst),
        .s_axis_tdata(s_tdata), .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready),
        .m_axis_tdata(m_tdata), .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready),
        .rxd(rxd), .txd(txd),
        .tx_busy(tx_busy), .rx_busy(rx_busy), .rx_overrun_error(ovr), .rx_frame_error(ferr),
        .prescale(16'd1));

    reg f_past_valid = 1'b0;
    always @(posedge clk) f_past_valid <= 1'b1;
    always @(*) if (!f_past_valid) assume (rst);
    // reset only while both sides are idle on the line (reset in mid-frame is not specified)
    always @(*) if (f_past_valid && (t_on || r_on)) assume (!rst);
    // AXI-Stream master: once offered, a byte stays offered and stable until the handshake
    always @(posedge clk) if (f_past_valid && !$past(rst) && !rst && $past(s_tvalid && !s_tready)) begin
        assume (s_tvalid);
        assume (s_tdata == $past(s_tdata));
    end

    // ---------------- transmit shadow ----------------
    wire         hs = !rst && s_tvalid && s_tready;
    reg          t_on = 1'b0;                 // a frame is in progress
    reg  [7:0]   t_k = 0;                     // cycles since the handshake
    reg  [3:0]   t_ph = 0;                    // cycle within the current bit, 0 .. BP-1
    reg  [3:0]   t_bit = 0;                   // 0 start, 1..W data, W+1 stop
    reg  [W+1:0] t_sh = 0;                    // remaining frame bits, LSB is the current bit
    always @(posedge clk) begin
        if (rst) begin
            t_on <= 1'b0; t_k <= 0;
        end else if (hs) begin
            // the design may start the frame one cycle before it raises s_axis_tready
            // (first byte after reset and back-to-back bytes); the frame is then aligned
            // to its start bit
            t_on <= 1'b1; t_bit <= 0; t_sh <= {1'b1, s_tdata, 1'b0};
            if (!txd) begin t_k <= 2; t_ph <= 1; end
            else      begin t_k <= 1; t_ph <= 0; end
        end else if (t_on) begin
            t_k <= t_k + 1;
            if (t_ph == BP - 1) begin t_ph <= 0; t_bit <= t_bit + 1; t_sh <= {1'b1, t_sh[W+1:1]}; end
            else t_ph <= t_ph + 1;
            if (t_k == FL + 3) t_on <= 1'b0;
        end
    end
    wire t_exp = t_sh[0];

    always @(posedge clk) if (f_past_valid && !$past(rst) && !rst) begin
        // T1: frame waveform with exact bit timing
        if (t_on && t_k <= FL) assert (txd == t_exp);
        // T2: idle line (except in the cycle of a handshake for a frame already started)
        if (!t_on && !hs) assert (txd == 1'b1);
        // T3: no new byte accepted and busy shown during the frame
        if (t_on && t_k <= FL) begin
            assert (!s_tready);
            assert (tx_busy);
        end
        // T4: ready again soon after the stop bit
        if (t_on && t_k == FL + 3) assert (s_tready);
    end
    always @(posedge clk) if (f_past_valid && $past(rst) && !rst) assert (txd == 1'b1);

    // ---------------- receive shadow (drives rxd) ----------------
    reg          r_on = 1'b0;
    reg  [7:0]   r_k = 0;                     // cycles since the start of the frame
    reg  [W-1:0] r_d = 0;
    reg          r_stop = 1'b1;
    reg  [3:0]   r_ph = 0;
    reg  [W+1:0] r_sh = 0;                    // frame bits still to send after the current one
    reg  [W-1:0] last_good = 0;
    reg          have_good = 1'b0;
    reg          got_valid = 1'b0, got_ovr = 1'b0, got_ferr = 1'b0;
    // a low stop bit is held just past its centre, then the line returns to idle
    wire [7:0]   r_end = r_stop ? FL : (W + 1) * BP + 5 * P;
    wire         r_win = r_on && r_k >= (W + 1) * BP;          // stop bit: events are due here

    always @(posedge clk) begin
        if (rst) begin
            r_on <= 1'b0; rxd <= 1'b1; have_good <= 1'b0;
        end else if (!r_on) begin
            rxd <= 1'b1;
            if (go) begin
                r_on <= 1'b1; r_k <= 0; r_ph <= 0; r_d <= go_data; r_stop <= go_stop;
                r_sh <= {1'b1, go_stop, go_data}; rxd <= 1'b0;
                got_valid <= 1'b0; got_ovr <= 1'b0; got_ferr <= 1'b0;
            end
        end else begin
            r_k <= r_k + 1;
            if (r_ph == BP - 1) begin
                r_ph <= 0; rxd <= r_sh[0]; r_sh <= {1'b1, r_sh[W+1:1]};
            end else r_ph <= r_ph + 1;
            if (r_k + 1 >= r_end) rxd <= 1'b1;
            if (r_k + 1 == r_end + 2) begin
                r_on <= 1'b0;
                if (r_stop) begin last_good <= r_d; have_good <= 1'b1; end
            end
            if (m_tvalid && !$past(m_tvalid)) got_valid <= 1'b1;
            if (ovr)  got_ovr  <= 1'b1;
            if (ferr) got_ferr <= 1'b1;
        end
    end

    always @(posedge clk) if (f_past_valid && !$past(rst) && !rst) begin
        // R1: delivered data is the data of the most recent good frame
        if (m_tvalid && m_tready && !(r_win && r_stop)) assert (have_good && m_tdata == last_good);
        // R2: events only during the stop bit of a frame of the right kind
        if (ferr) assert (r_win && !r_stop);
        if (ovr)  assert (r_win && r_stop);
        if (m_tvalid && !$past(m_tvalid)) assert (r_win && r_stop);
        // R3: at the end of a frame the right event has happened
        if (r_on && r_k == r_end + 1) begin
            if (r_stop) assert (got_valid || got_ovr);
            else        assert (got_ferr && !got_valid && !got_ovr);
        end
        // R4: data is held until taken
        if ($past(m_tvalid && !m_tready) && !(r_win && r_stop)) assert (m_tvalid && m_tdata == $past(m_tdata));
        // R5: receiver busy from the first data bit to the stop bit
        if (r_on && r_k >= BP && r_k < (W + 1) * BP) assert (rx_busy);
    end

    always @(posedge clk) if (f_past_valid && !rst) begin
        cover (t_on && t_k == FL + 3);
        cover (m_tvalid && m_tready);
        cover (ferr);
        cover (ovr);
    end
endmodule
