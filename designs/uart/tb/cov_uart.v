// Passive functional coverage monitor for the uart top level (uart_tx + uart_rx).
// It watches ports only; loop tells it whether rxd is connected to txd.
`timescale 1ns/1ps
module cov_uart (
    input wire        clk,
    input wire        rst,
    input wire [7:0]  s_tdata,
    input wire        s_tvalid,
    input wire        s_tready,
    input wire [7:0]  m_tdata,
    input wire        m_tvalid,
    input wire        m_tready,
    input wire        tx_busy,
    input wire        rx_busy,
    input wire        ovr,
    input wire        ferr,
    input wire [15:0] prescale,
    input wire        loop,
    input wire        rxd
);
    localparam NB = 19;
    integer hits [0:NB-1];
    reg [8*40-1:0] name [0:NB-1];
    integer i, low_cnt;

    initial begin
        for (i = 0; i < NB; i = i + 1) hits[i] = 0;
        name[0]  = "tx byte at prescale 1";
        name[1]  = "tx byte at prescale 2";
        name[2]  = "tx byte at prescale 3";
        name[3]  = "rx byte at prescale 1";
        name[4]  = "rx byte at prescale 2";
        name[5]  = "rx byte at prescale 3";
        name[6]  = "tx data 0x00";
        name[7]  = "tx data 0xFF";
        name[8]  = "rx data 0x00";
        name[9]  = "rx data 0xFF";
        name[10] = "tx back-to-back bytes";
        name[11] = "rx frame error";
        name[12] = "rx overrun";
        name[13] = "rx false start (short low pulse)";
        name[14] = "rx backpressure (tvalid, no tready)";
        name[15] = "loopback byte";
        name[16] = "reset during tx";
        name[17] = "reset during rx";
        name[18] = "tx and rx busy together";
        low_cnt = 0;
    end

    wire tx_hs = s_tvalid && s_tready;
    wire rx_hs = m_tvalid && m_tready;

    always @(posedge clk) begin
        if (rst) begin
            if (tx_busy) hits[16] = hits[16] + 1;
            if (rx_busy) hits[17] = hits[17] + 1;
        end else begin
            if (tx_hs) begin
                if (prescale == 1) hits[0] = hits[0] + 1;
                if (prescale == 2) hits[1] = hits[1] + 1;
                if (prescale == 3) hits[2] = hits[2] + 1;
                if (s_tdata == 8'h00) hits[6] = hits[6] + 1;
                if (s_tdata == 8'hFF) hits[7] = hits[7] + 1;
                // a new byte offered and accepted while the previous one is still being sent
                if (tx_busy) hits[10] = hits[10] + 1;
            end
            if (rx_hs) begin
                if (prescale == 1) hits[3] = hits[3] + 1;
                if (prescale == 2) hits[4] = hits[4] + 1;
                if (prescale == 3) hits[5] = hits[5] + 1;
                if (m_tdata == 8'h00) hits[8] = hits[8] + 1;
                if (m_tdata == 8'hFF) hits[9] = hits[9] + 1;
                if (loop) hits[15] = hits[15] + 1;
            end
            if (ferr) hits[11] = hits[11] + 1;
            if (ovr)  hits[12] = hits[12] + 1;
            if (m_tvalid && !m_tready) hits[14] = hits[14] + 1;
            if (tx_busy && rx_busy) hits[18] = hits[18] + 1;
            // false start: rxd low for fewer than 4 * prescale cycles while the receiver is idle
            if (!rxd) low_cnt = low_cnt + 1;
            else begin
                if (low_cnt > 0 && low_cnt < 4 * prescale && !loop) hits[13] = hits[13] + 1;
                low_cnt = 0;
            end
        end
    end

    task report;
        integer n;
        begin
            n = 0;
            for (i = 0; i < NB; i = i + 1) begin
                $display("COVER %-40s %0d", name[i], hits[i]);
                if (hits[i] > 0) n = n + 1;
            end
            $display("COVERAGE: %0d of %0d bins hit", n, NB);
        end
    endtask
endmodule
