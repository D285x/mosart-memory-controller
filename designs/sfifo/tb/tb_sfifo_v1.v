// Self-checking testbench for sfifo (first version, written before mutation analysis).
// Configuration: BW = 8, LGFLEN = 4, OPT_ASYNC_READ = 0 (registered read with bypass),
// OPT_WRITE_ON_FULL = 0, OPT_READ_ON_EMPTY = 0.
// Reference model: a queue. Inputs are driven on the falling edge; the model is updated on
// the rising edge. Checked every cycle: o_full, o_empty and o_fill against the model.
// Checked on every accepted read: o_data equals the oldest entry of the model.
`timescale 1ns/1ps
module tb_sfifo;
    localparam BW = 8, LGFLEN = 4, FLEN = 16;

    reg clk = 0, rst = 1, wr = 0, rd = 0;
    reg [BW-1:0] din = 0;
    wire [BW-1:0] dout;
    wire full, empty;
    wire [LGFLEN:0] fill;

    sfifo #(.BW(BW), .LGFLEN(LGFLEN), .OPT_ASYNC_READ(1'b0)) dut (
        .i_clk(clk), .i_reset(rst),
        .i_wr(wr), .i_data(din), .o_full(full), .o_fill(fill),
        .i_rd(rd), .o_data(dout), .o_empty(empty));

    cov_sfifo #(.LGFLEN(LGFLEN)) cov (.clk(clk), .rst(rst), .wr(wr), .rd(rd),
        .full(full), .empty(empty), .fill(fill));

    always #5 clk = ~clk;

    reg [BW-1:0] q [0:FLEN-1];
    integer head = 0, count = 0, checks = 0, errors = 0, i, k;
    reg wacc, racc;

    task fail(input [8*48-1:0] what);
        begin
            errors = errors + 1;
            if (errors <= 10) $display("ERROR t=%0t %0s (count %0d fill %0d full %b empty %b)",
                                       $time, what, count, fill, full, empty);
        end
    endtask

    // checks just before each rising edge, model update on the edge
    always @(posedge clk) begin
        if (!rst) begin
            checks = checks + 3;
            if (full  !== (count == FLEN)) fail("o_full");
            if (empty !== (count == 0))    fail("o_empty");
            if (fill  !== count)           fail("o_fill");
            if (rd && count > 0) begin
                checks = checks + 1;
                if (dout !== q[head]) fail("o_data on read");
            end
            // model update: a write is accepted when not full, a read when not empty
            wacc = wr && (count < FLEN);
            racc = rd && (count > 0);
            if (wacc) q[(head + count) % FLEN] = din;
            if (racc) head = (head + 1) % FLEN;
            count = count + wacc - racc;
        end else begin
            head = 0; count = 0;
        end
    end

    task cyc(input w, input r, input [BW-1:0] d);
        begin
            @(negedge clk); wr = w; rd = r; din = d;
        end
    endtask

    task idle(input integer n);
        begin
            for (k = 0; k < n; k = k + 1) cyc(0, 0, 0);
        end
    endtask

    initial begin
        // D1: reset
        cyc(0, 0, 0); cyc(0, 0, 0);
        @(negedge clk); rst = 0;
        idle(2);

        // D2: fill to full, then a write while full
        for (i = 0; i < FLEN; i = i + 1) cyc(1, 0, 8'h10 + i);
        cyc(1, 0, 8'hEE); cyc(1, 0, 8'hEF);
        idle(1);

        // D3: read and write together when full
        cyc(1, 1, 8'hA0);
        idle(1);

        // D4: drain to empty, then a read while empty
        for (i = 0; i < FLEN; i = i + 1) cyc(0, 1, 0);
        cyc(0, 1, 0); cyc(0, 1, 0);
        idle(1);

        // D5: read and write together when empty
        cyc(1, 1, 8'h5A);
        idle(1);
        cyc(0, 1, 0);
        idle(1);

        // D6: write then read on the next cycle (level 1), repeated
        for (i = 0; i < 8; i = i + 1) begin cyc(1, 0, 8'hC0 + i); cyc(0, 1, 0); end
        idle(1);

        // D7: half fill, then read and write together at mid level
        for (i = 0; i < FLEN / 2; i = i + 1) cyc(1, 0, 8'h30 + i);
        for (i = 0; i < 10; i = i + 1) cyc(1, 1, 8'h60 + i);
        idle(1);

        // D8: reset while not empty, then normal operation
        @(negedge clk); rst = 1; wr = 0; rd = 0;
        @(negedge clk); rst = 0;
        idle(1);
        for (i = 0; i < 4; i = i + 1) cyc(1, 0, 8'h70 + i);
        for (i = 0; i < 5; i = i + 1) cyc(0, 1, 0);

        // D9: constrained random, three traffic mixes
        for (i = 0; i < 3000; i = i + 1) begin
            if (i < 1000)      cyc(($random & 3) != 0, ($random & 3) == 0, $random);  // mostly writes
            else if (i < 2000) cyc(($random & 3) == 0, ($random & 3) != 0, $random);  // mostly reads
            else               cyc($random, $random, $random);                        // balanced
        end
        idle(2);

        cov.report;
        $display("SUMMARY: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display("RESULT : ALL TESTS PASSED");
        else             $display("RESULT : FAILED");
        $finish;
    end
endmodule
