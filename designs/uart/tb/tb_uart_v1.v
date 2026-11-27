// Self-checking testbench for the uart top level (first version, written before mutation analysis).
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
            checks = checks + 1;
            if (txd !== 1'b0) fail("tx start bit");
            for (b = 0; b < 8; b = b + 1) begin
                repeat (8 * prescale) @(posedge clk);
                dec[b] = txd;
            end
            repeat (8 * prescale) @(posedge clk);
            checks = checks + 2;
            if (txd !== 1'b1) fail("tx stop bit");
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
        if (ferr) got_ferr = got_ferr + 1;
        if (ovr)  got_ovr  = got_ovr + 1;
    end

    // transmitter model: one frame on rxd; stop = 0 produces a framing error
    task frame(input [7:0] d, input stop);
        begin
            @(negedge clk); rxd_drv = 0;
            repeat (8 * prescale) @(negedge clk);
            for (fj = 0; fj < 8; fj = fj + 1) begin
                rxd_drv = d[fj];
                repeat (8 * prescale) @(negedge clk);
            end
            rxd_drv = stop;
            // a low stop bit is held just past its centre so that the line is idle afterwards
            repeat (stop ? 8 * prescale : 5 * prescale) @(negedge clk);
            rxd_drv = 1;
            repeat (4 * prescale) @(negedge clk);
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

        // end of test checks
        checks = checks + 4;
        if (tx_rd !== tx_wr) fail("tx bytes missing");
        if (rx_rd !== rx_wr) fail("rx bytes missing");
        if (got_ferr !== exp_ferr) fail("frame error count");
        if (got_ovr  !== exp_ovr)  fail("overrun count");

        cov.report;
        $display("SUMMARY: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display("RESULT : ALL TESTS PASSED");
        else             $display("RESULT : FAILED");
        $finish;
    end

    // watchdog
    initial begin #20000000; $display("ERROR watchdog"); $display("SUMMARY: %0d checks, %0d errors", checks, errors + 1); $display("RESULT : FAILED"); $finish; end
endmodule
