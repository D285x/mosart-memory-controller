// Self-checking testbench for the uart top level, second version: tb_uart_v1.v plus the checks and
// tests added after analysing the mutants that survived v1 (marked "v2" below):
//   stop bit held for the whole bit period, busy flags during frames and when idle, outputs
//   right after a reset, a streaming AXI-Stream master, resets during transmission, reception and
//   at status events, and a receiver tolerance test at +/- 4 percent bit rate after a false start.
// Bit period = 8 * prescale clock cycles, 8N1 framing, LSB first.
// Transmit side: bytes accepted on the s_axis handshake are queued; a receiver model decodes txd
// (sampling in the middle of each bit) and compares every decoded byte with the queue.
// Receive side: a transmitter model drives rxd; every byte taken on the m_axis handshake is
// compared with the expected byte, and the numbers of frame_error and overrun_error pulses are
// compared with the expected numbers at the end. In loopback mode rxd is driven by txd.
`timescale 1ns/1ps
module tb_uart;
    reg clk = 0, rst = 1;
    reg [7:0] s_tdata = 0;
    reg s_tvalid = 0, m_tready = 1;
    wire s_tready, m_tvalid, txd, tx_busy, rx_busy, ovr, ferr;
    wire [7:0] m_tdata;
    reg [15:0] prescale = 1;
    reg loop = 0, rxd_drv = 1;
    wire rxd = loop ? txd : rxd_drv;

    uart #(.DATA_WIDTH(8)) dut (
        .clk(clk), .rst(rst),
        .s_axis_tdata(s_tdata), .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready),
        .m_axis_tdata(m_tdata), .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready),
        .rxd(rxd), .txd(txd),
        .tx_busy(tx_busy), .rx_busy(rx_busy), .rx_overrun_error(ovr), .rx_frame_error(ferr),
        .prescale(prescale));

    cov_uart cov (.clk(clk), .rst(rst), .s_tdata(s_tdata), .s_tvalid(s_tvalid), .s_tready(s_tready),
        .m_tdata(m_tdata), .m_tvalid(m_tvalid), .m_tready(m_tready), .tx_busy(tx_busy),
        .rx_busy(rx_busy), .ovr(ovr), .ferr(ferr), .prescale(prescale), .loop(loop), .rxd(rxd));

    always #5 clk = ~clk;

    integer checks = 0, errors = 0, i, j, fj;
    task fail(input [8*48-1:0] what);
        begin
            errors = errors + 1;
            if (errors <= 10) $display("ERROR t=%0t %0s", $time, what);
        end
    endtask

    // ---------------- transmit side ----------------
    reg [7:0] txq [0:255];
    integer tx_wr = 0, tx_rd = 0;
    reg tx_chk = 1;
    always @(posedge clk) if (!rst && s_tvalid && s_tready) begin
        txq[tx_wr % 256] = s_tdata; tx_wr = tx_wr + 1;
    end

    // receiver model on txd
    reg [7:0] dec;
    integer b;
    always begin
        @(negedge txd);
        if (tx_chk && !rst) begin
            repeat (4 * prescale) @(posedge clk);
            checks = checks + 2;
            if (txd !== 1'b0) fail("tx start bit");
            if (tx_busy !== 1'b1) fail("tx_busy during frame");                        // v2
            for (b = 0; b < 8; b = b + 1) begin
                repeat (8 * prescale) @(posedge clk);
                dec[b] = txd;
                checks = checks + 1;
                if (tx_busy !== 1'b1) fail("tx_busy during frame");                    // v2
            end
            repeat (8 * prescale) @(posedge clk);
            checks = checks + 2;
            if (txd !== 1'b1) fail("tx stop bit");
            // v2: the stop bit lasts a whole bit period, so txd stays high until its end
            for (b = 0; b < 4 * prescale - 1; b = b + 1) begin
                @(posedge clk);
                checks = checks + 1;
                if (txd !== 1'b1) fail("tx stop bit too short");
            end
            if (tx_rd >= tx_wr) fail("tx byte without handshake");
            else begin
                if (dec !== txq[tx_rd % 256]) fail("tx data");
                tx_rd = tx_rd + 1;
            end
        end
    end

    // offer one byte on s_axis and wait for the handshake
    task send(input [7:0] d);
        begin
            @(negedge clk); s_tdata = d; s_tvalid = 1;
            @(posedge clk); while (!s_tready) @(posedge clk);
            @(negedge clk); s_tvalid = 0;
        end
    endtask

    task wait_tx_done;
        begin
            @(negedge clk);
            while (tx_busy || s_tvalid) @(negedge clk);
            repeat (16 * prescale) @(negedge clk);
            checks = checks + 2;
            if (tx_busy !== 1'b0) fail("tx_busy when idle");                           // v2
            if (s_tready !== 1'b1) fail("tx not ready when idle");                     // v2
        end
    endtask

    // v2: streaming master: s_axis_tvalid stays high and the next byte is presented right after each
    // handshake (allowed by AXI-Stream); every accepted byte must be transmitted
    task stream(input integer n);
        integer k;
        begin
            @(negedge clk); s_tdata = $random; s_tvalid = 1;
            for (k = 0; k < n; k = k + 1) begin
                @(posedge clk); while (!s_tready) @(posedge clk);
                @(negedge clk); s_tdata = $random;
            end
            s_tvalid = 0;
        end
    endtask

    // ---------------- receive side ----------------
    reg [7:0] rxq [0:255];
    integer rx_wr = 0, rx_rd = 0, exp_ferr = 0, exp_ovr = 0, got_ferr = 0, got_ovr = 0;
    reg rx_chk = 1;
    always @(posedge clk) if (!rst && rx_chk) begin
        if (m_tvalid && m_tready) begin
            checks = checks + 1;
            if (rx_rd >= rx_wr) fail("rx byte not sent");
            else begin
                if (m_tdata !== rxq[(rx_wr - 1) % 256]) begin fail("rx data"); $display("  got %h exp %h", m_tdata, rxq[(rx_wr - 1) % 256]); end
                rx_rd = rx_wr;     // the newest byte is the one delivered
            end
        end
    end
    // v2: events are counted also in a cycle where reset is applied (a pulse can coincide with it)
    always @(posedge clk) if (rx_chk) begin
        if (ferr) got_ferr = got_ferr + 1;
        if (ovr)  got_ovr  = got_ovr + 1;
    end

    // transmitter model: one frame on rxd; stop = 0 produces a framing error
    reg busy_chk = 1;      // v2: rx_busy is checked inside frame() unless the frame is aborted
    integer bitp = 0;      // v2: bit period of the transmitter model; 0 means 8 * prescale
    task frame(input [7:0] d, input stop);
        integer bp;
        begin
            bp = (bitp != 0) ? bitp : 8 * prescale;
            @(negedge clk); rxd_drv = 0;
            repeat (bp) @(negedge clk);
            for (fj = 0; fj < 8; fj = fj + 1) begin
                rxd_drv = d[fj];
                repeat (bp / 2) @(negedge clk);
                if (rx_chk && busy_chk && !rst) begin                                  // v2
                    checks = checks + 1;
                    if (rx_busy !== 1'b1) fail("rx_busy during frame");
                end
                repeat (bp - bp / 2) @(negedge clk);
            end
            rxd_drv = stop;
            // a low stop bit is held just past its centre so that the line is idle afterwards
            repeat (stop ? bp : 5 * bp / 8) @(negedge clk);
            rxd_drv = 1;
            repeat (4 * prescale) @(negedge clk);
            if (rx_chk && busy_chk && !rst) begin                                      // v2
                checks = checks + 1;
                if (rx_busy !== 1'b0) fail("rx_busy when idle");
            end
        end
    endtask

    // v2: outputs in the first cycles after a reset: idle line, nothing busy, no data, no events
    // (state left by the reset edge, then one cycle later: transmitter ready, receiver still idle)
    always @(negedge rst) begin
        #1;
        checks = checks + 1;
        if (txd !== 1'b1 || tx_busy !== 1'b0 || rx_busy !== 1'b0 || m_tvalid !== 1'b0 || ovr !== 1'b0 || ferr !== 1'b0)
            begin fail("outputs after reset"); $display("  txd %b tx_busy %b rx_busy %b m_tvalid %b ovr %b ferr %b", txd, tx_busy, rx_busy, m_tvalid, ovr, ferr); end
        @(negedge clk);
        checks = checks + 2;
        if (s_tready !== 1'b1) fail("tx not ready one cycle after reset");
        if (rx_busy !== 1'b0) fail("rx busy one cycle after reset");
    end

    task pulse_reset;
        begin
            @(negedge clk); rst = 1; @(negedge clk); rst = 0;
        end
    endtask

    task rx_good(input [7:0] d);
        begin
            rxq[rx_wr % 256] = d; rx_wr = rx_wr + 1;
            frame(d, 1);
        end
    endtask

    // ---------------- test sequence ----------------
    initial begin
        // D1: reset and idle line
        $display("PHASE D1 t=%0t", $time);
        repeat (3) @(negedge clk);
        rst = 0;
        repeat (4) @(negedge clk);
        checks = checks + 2;
        if (txd !== 1'b1) fail("txd idle level");
        if (m_tvalid !== 1'b0) fail("m_tvalid after reset");

        // D2: transmit at prescale 1, 2, 3, including 0x00, 0xFF and back-to-back bytes
        $display("PHASE D2 t=%0t", $time);
        for (i = 1; i <= 3; i = i + 1) begin
            prescale = i;
            send(8'h00); send(8'hFF); send(8'hA5); send(8'h3C);
            wait_tx_done;
        end

        // D3: receive at prescale 1, 2, 3
        $display("PHASE D3 t=%0t", $time);
        for (i = 1; i <= 3; i = i + 1) begin
            prescale = i;
            rx_good(8'h00); rx_good(8'hFF); rx_good(8'h5A); rx_good(8'hC3);
        end
        prescale = 1;

        // D4: framing error (stop bit low) at prescale 2
        $display("PHASE D4 t=%0t", $time);
        prescale = 2;
        exp_ferr = exp_ferr + 1; frame(8'h81, 0);
        repeat (16) @(negedge clk);
        rx_good(8'h42);
        prescale = 1;

        // D5: overrun: two bytes arrive while m_tready is low
        $display("PHASE D5 t=%0t", $time);
        @(negedge clk); m_tready = 0;
        rx_good(8'h11);
        exp_ovr = exp_ovr + 1; rx_good(8'h22);
        repeat (8) @(negedge clk);
        m_tready = 1;
        repeat (4) @(negedge clk);

        // D6: false start at prescale 2: rxd low for 2 cycles, nothing must be received
        $display("PHASE D6 t=%0t", $time);
        prescale = 2;
        @(negedge clk); rxd_drv = 0; @(negedge clk); @(negedge clk); rxd_drv = 1;
        repeat (100) @(negedge clk);
        rx_good(8'h99);
        prescale = 1;

        // D7: loopback, full duplex
        $display("PHASE D7 t=%0t", $time);
        loop = 1;
        for (i = 0; i < 6; i = i + 1) begin
            rxq[rx_wr % 256] = 8'h10 * i + i; rx_wr = rx_wr + 1;
            send(8'h10 * i + i);
            wait_tx_done;
        end
        loop = 0;
        repeat (20) @(negedge clk);

        // D8: random transmit and receive traffic in parallel (full duplex)
        $display("PHASE D8 t=%0t", $time);
        fork
            for (i = 0; i < 40; i = i + 1) send($random);
            for (j = 0; j < 40; j = j + 1) rx_good($random);
        join
        wait_tx_done;

        // D9: reset during a transmission and during a reception
        $display("PHASE D9 t=%0t", $time);
        tx_chk = 0;
        send(8'h55);
        repeat (30) @(negedge clk);
        rst = 1; @(negedge clk); rst = 0;
        wait_tx_done;
        repeat (100) @(negedge clk);
        tx_rd = tx_wr;
        tx_chk = 1;
        rx_chk = 0;
        fork
            frame(8'h77, 1);
            begin repeat (40) @(negedge clk); rst = 1; @(negedge clk); rst = 0; end
        join
        repeat (100) @(negedge clk);
        rx_rd = rx_wr;
        rx_chk = 1;
        send(8'h6E); rx_good(8'h6E);
        wait_tx_done;
        repeat (20) @(negedge clk);

        // v2 D10: streaming transmit at prescale 1 and 2
        $display("PHASE D10 t=%0t", $time);
        prescale = 1; stream(6); wait_tx_done;
        prescale = 2; stream(4); wait_tx_done;
        prescale = 1;

        // v2 D11: resets during operation, each followed at once by normal traffic
        $display("PHASE D11 t=%0t", $time);
        // (a) during a transmission: the next byte goes out straight after the reset
        tx_chk = 0;
        send(8'hA7);
        repeat (20) @(negedge clk);
        pulse_reset;
        tx_rd = tx_wr;
        tx_chk = 1;
        send(8'h3D); wait_tx_done;
        // (a2) during the start bit (txd low)
        tx_chk = 0;
        send(8'hC6);
        repeat (2) @(negedge clk);
        pulse_reset;
        tx_rd = tx_wr;
        tx_chk = 1;
        send(8'h29); wait_tx_done;
        // (b) during the data bits of a received 0xFF: the line stays high, so nothing is received
        busy_chk = 0;
        fork
            frame(8'hFF, 1);
            begin repeat (30) @(negedge clk); pulse_reset; end
        join
        busy_chk = 1;
        rx_good(8'h4B);
        // (b2) during the data bits of a received 0xFF, with the next frame starting at once
        busy_chk = 0;
        @(negedge clk); rxd_drv = 0;
        repeat (8 * prescale) @(negedge clk);
        rxd_drv = 1;
        repeat (20 * prescale) @(negedge clk);
        busy_chk = 1;
        pulse_reset;
        rx_good(8'h69);
        // (c) with the line low during the reset, released high at the end of the reset
        @(negedge clk); rxd_drv = 0; rst = 1;
        @(negedge clk); @(negedge clk); rxd_drv = 1; rst = 0;
        repeat (20) @(negedge clk);
        rx_good(8'hB4);
        // (d) right after a framing error and right after an overrun
        prescale = 2;
        exp_ferr = exp_ferr + 1;
        fork
            frame(8'h81, 0);
            begin @(posedge ferr); pulse_reset; end
        join
        repeat (16) @(negedge clk);
        prescale = 1;
        @(negedge clk); m_tready = 0;
        rx_good(8'h12);
        exp_ovr = exp_ovr + 1;
        fork
            rx_good(8'h34);
            begin @(posedge ovr); pulse_reset; rx_rd = rx_wr; end
        join
        m_tready = 1;
        repeat (10) @(negedge clk);
        rx_good(8'h56);

        // v2 D12: receiver tolerance after a false start: bit periods 23 and 25 cycles at prescale 3
        $display("PHASE D12 t=%0t", $time);
        prescale = 3;
        @(negedge clk); rxd_drv = 0; @(negedge clk); @(negedge clk); rxd_drv = 1;
        repeat (100) @(negedge clk);
        for (i = 0; i < 2; i = i + 1) begin
            bitp = (i == 0) ? 23 : 25;
            rx_good(8'hA5); rx_good(8'h5A); rx_good(8'h00); rx_good(8'hFF);
        end
        bitp = 0; prescale = 1;
        repeat (20) @(negedge clk);

        // end of test checks
        checks = checks + 4;
        if (tx_rd !== tx_wr) fail("tx bytes missing");
        if (rx_rd !== rx_wr) fail("rx bytes missing");
        if (got_ferr !== exp_ferr) begin fail("frame error count"); $display("  got %0d exp %0d", got_ferr, exp_ferr); end
        if (got_ovr  !== exp_ovr)  begin fail("overrun count"); $display("  got %0d exp %0d", got_ovr, exp_ovr); end

        cov.report;
        $display("SUMMARY: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display("RESULT : ALL TESTS PASSED");
        else             $display("RESULT : FAILED");
        $finish;
    end

    // watchdog
    initial begin #20000000; $display("ERROR watchdog"); $display("SUMMARY: %0d checks, %0d errors", checks, errors + 1); $display("RESULT : FAILED"); $finish; end
endmodule
