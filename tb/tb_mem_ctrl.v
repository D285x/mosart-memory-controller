//============================================================================
// Testbench   : tb_mem_ctrl
// Project     : MOSART Project 8 - Programmable Memory Controller
// Author      : Shaun Praneeth Raj
// Description : Self-checking testbench. A behavioural reference model
//               (model[]) mirrors every accepted write; every read and every
//               status/config read-back is compared against it. Stimulus is
//               driven on the falling edge, outputs are sampled on the
//               rising edge. Ends with a PASS/FAIL summary.
//============================================================================
`timescale 1ns/1ps
module tb_mem_ctrl;
    localparam DATA_W = 8, ADDR_W = 4, DEPTH = 16;
    localparam CLK_P  = 10;                         // 100 MHz

    reg               clk = 0, reset = 1;
    reg               read_enable = 0, write_enable = 0;
    reg  [ADDR_W-1:0] address = 0;
    reg  [DATA_W-1:0] write_data = 0;
    wire [DATA_W-1:0] read_data;
    wire              ready, busy, error;
    reg               cfg_we = 0;
    reg  [1:0]        cfg_addr = 0;
    reg  [7:0]        cfg_wdata = 0;
    wire [7:0]        cfg_rdata;

    mem_ctrl_top #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) dut (
        .clk(clk), .reset(reset),
        .read_enable(read_enable), .write_enable(write_enable),
        .address(address), .write_data(write_data), .read_data(read_data),
        .ready(ready), .busy(busy), .error(error),
        .cfg_we(cfg_we), .cfg_addr(cfg_addr),
        .cfg_wdata(cfg_wdata), .cfg_rdata(cfg_rdata)
    );

    always #(CLK_P/2) clk = ~clk;

    // ---------------- reference model & bookkeeping ----------------
    reg [DATA_W-1:0] model [0:DEPTH-1];
    integer errors = 0, checks = 0, test_errors_start = 0;
    integer lat, k, n, a, d, op, ws;
    integer n_rd = 0, n_wr = 0, n_rej = 0;
    reg [7:0] cur_wait = 0;
    reg [4:0] cur_limit = 16;
    reg       cur_wp = 0;
    reg       got_err;

    task check(input [639:0] what, input [31:0] got, input [31:0] exp);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  ** FAIL %0s : got 0x%0h expected 0x%0h @ %0t",
                         what, got, exp, $time);
            end
        end
    endtask

    task begin_test(input [639:0] name);
        begin
            test_errors_start = errors;
            $display("[%0t] TEST: %0s", $time, name);
        end
    endtask

    task end_test(input [639:0] name);
        begin
            if (errors == test_errors_start) $display("    -> PASS  %0s", name);
            else                             $display("    -> FAIL  %0s", name);
        end
    endtask

    // ---------------- config bus ----------------
    task cfg_write(input [1:0] ad, input [7:0] dat);
        begin
            @(negedge clk); cfg_we = 1; cfg_addr = ad; cfg_wdata = dat;
            @(negedge clk); cfg_we = 0;
        end
    endtask

    task cfg_expect(input [1:0] ad, input [7:0] exp);
        begin
            @(negedge clk); cfg_addr = ad; #1;
            check("cfg readback", cfg_rdata, exp);
        end
    endtask

    // ---------------- host transactions ----------------
    // Issues one request, waits for ready, returns latency (cycles from the
    // edge that samples the request to the edge that samples ready) and
    // whether the controller flagged an error.
    task do_access(input rd, input wr, input [ADDR_W-1:0] ad,
                   input [DATA_W-1:0] dat, output integer cycles,
                   output reg err);
        begin
            @(negedge clk);
            read_enable = rd; write_enable = wr; address = ad; write_data = dat;
            @(negedge clk);
            read_enable = 0; write_enable = 0;
            cycles = 1;
            while (!ready) begin
                check("busy during access", busy, 1);
                @(negedge clk); cycles = cycles + 1;
            end
            err = error;
        end
    endtask

    task mem_write(input [ADDR_W-1:0] ad, input [DATA_W-1:0] dat,
                   input exp_err);
        begin
            do_access(0, 1, ad, dat, lat, got_err);
            check("write error flag", got_err, exp_err);
            if (!got_err) begin model[ad] = dat; n_wr = n_wr + 1; end
            else n_rej = n_rej + 1;
        end
    endtask

    task mem_read(input [ADDR_W-1:0] ad, input exp_err);
        begin
            do_access(1, 0, ad, 8'h00, lat, got_err);
            check("read error flag", got_err, exp_err);
            if (!got_err) begin
                check("read data", read_data, model[ad]);
                n_rd = n_rd + 1;
            end else n_rej = n_rej + 1;
        end
    endtask

    // ---------------- stimulus ----------------
    initial begin
        $dumpfile("mem_ctrl.vcd");
        $dumpvars(0, tb_mem_ctrl);
        for (k = 0; k < DEPTH; k = k + 1) model[k] = 0;

        repeat (3) @(negedge clk);
        reset = 0;

        //--------------------------------------------------------------
        begin_test("T1 reset values of configuration registers");
        cfg_expect(2'd0, 8'h01);   // EN=1, WP=0
        cfg_expect(2'd1, 8'h00);   // WAIT=0
        cfg_expect(2'd2, 8'h10);   // LIMIT=16
        cfg_expect(2'd3, 8'h00);   // STATUS clear, not busy
        check("busy after reset", busy, 0);
        check("ready after reset", ready, 0);
        end_test("T1");

        //--------------------------------------------------------------
        begin_test("T2 write all 16 words, read back, zero wait states");
        for (k = 0; k < DEPTH; k = k + 1) begin
            mem_write(k, 8'hA0 ^ (k * 8'h11), 0);
            check("write latency WAIT=0", lat, 2);
        end
        for (k = 0; k < DEPTH; k = k + 1) begin
            mem_read(k, 0);
            check("read latency WAIT=0", lat, 2);
        end
        end_test("T2");

        //--------------------------------------------------------------
        begin_test("T3 programmable wait states 1..7");
        for (ws = 1; ws < 8; ws = ws + 1) begin
            cfg_write(2'd1, ws);
            mem_write(ws, 8'h30 + ws, 0);
            check("write latency", lat, 2 + ws);
            mem_read(ws, 0);
            check("read latency", lat, 2 + ws);
        end
        cfg_write(2'd1, 8'd3);
        mem_write(4'hF, 8'h5A, 0);
        mem_read (4'hF, 0);
        check("read latency WAIT=3", lat, 5);
        cfg_write(2'd1, 8'd0);
        end_test("T3");

        //--------------------------------------------------------------
        begin_test("T4 simultaneous read + write request is rejected");
        do_access(1, 1, 4'h2, 8'hEE, lat, got_err);
        check("collision error", got_err, 1);
        n_rej = n_rej + 1;
        cfg_expect(2'd3, 8'h01);   // COLL set
        mem_read(4'h2, 0);         // memory must be unchanged
        cfg_write(2'd3, 8'h01);    // W1C
        cfg_expect(2'd3, 8'h00);
        end_test("T4");

        //--------------------------------------------------------------
        begin_test("T5 address limit (LIMIT = 8)");
        cfg_write(2'd2, 8'd8);
        cfg_expect(2'd2, 8'd8);
        mem_write(4'd10, 8'h99, 1);    // out of range -> error
        mem_read (4'd12, 1);
        cfg_expect(2'd3, 8'h02);       // RANGE set
        mem_write(4'd7, 8'h77, 0);     // last valid word
        mem_read (4'd7, 0);
        cfg_write(2'd2, 8'd31);        // oversize value saturates to 16
        cfg_expect(2'd2, 8'd16);
        mem_read (4'd10, 0);           // old contents intact
        cfg_write(2'd3, 8'h0F);
        end_test("T5");

        //--------------------------------------------------------------
        begin_test("T6 write protect");
        cfg_write(2'd0, 8'h03);        // EN=1, WP=1
        mem_write(4'd3, 8'hFF, 1);
        cfg_expect(2'd3, 8'h04);       // WPV set
        mem_read (4'd3, 0);            // reads still allowed, data unchanged
        cfg_write(2'd0, 8'h01);
        cfg_write(2'd3, 8'h0F);
        mem_write(4'd3, 8'h3C, 0);
        mem_read (4'd3, 0);
        end_test("T6");

        //--------------------------------------------------------------
        begin_test("T7 request while busy is dropped and flagged");
        cfg_write(2'd1, 8'd4);
        @(negedge clk);
        write_enable = 1; address = 4'd5; write_data = 8'h55;
        @(negedge clk);
        write_enable = 1; address = 4'd6; write_data = 8'h66;  // arrives while busy
        @(negedge clk);
        write_enable = 0;
        while (!ready) @(negedge clk);
        model[5] = 8'h55; n_wr = n_wr + 1;
        cfg_expect(2'd3, 8'h08);       // OVR set
        mem_read(4'd6, 0);             // location 6 must NOT be 0x66
        mem_read(4'd5, 0);
        cfg_write(2'd3, 8'h0F);
        cfg_write(2'd1, 8'd0);
        end_test("T7");

        //--------------------------------------------------------------
        begin_test("T8 controller disabled (EN = 0) ignores requests");
        cfg_write(2'd0, 8'h00);
        @(negedge clk);
        write_enable = 1; address = 4'd1; write_data = 8'hBD;
        repeat (4) begin
            @(negedge clk);
            check("busy while disabled", busy, 0);
            check("ready while disabled", ready, 0);
        end
        write_enable = 0;
        cfg_write(2'd0, 8'h01);
        mem_read(4'd1, 0);             // not overwritten
        end_test("T8");

        //--------------------------------------------------------------
        begin_test("T9 reset during a transaction");
        cfg_write(2'd1, 8'd5);
        @(negedge clk);
        read_enable = 1; address = 4'd9;
        @(negedge clk); read_enable = 0;
        @(negedge clk); @(negedge clk);
        check("busy mid-transaction", busy, 1);
        reset = 1; @(negedge clk); reset = 0;
        check("busy after reset", busy, 0);
        cfg_expect(2'd1, 8'd0);        // config back to default
        mem_read(4'd9, 0);             // memory array keeps its contents
        end_test("T9");

        //--------------------------------------------------------------
        begin_test("T10 constrained-random regression (500 accesses)");
        n = 0;
        for (k = 0; k < 500; k = k + 1) begin
            if (k % 50 == 0) begin
                cfg_write(2'd1, $urandom % 8);
            end
            a  = $urandom % DEPTH;
            d  = $urandom % 256;
            op = $urandom % 2;
            if (op) mem_write(a, d, 0);
            else    mem_read (a, 0);
        end
        for (k = 0; k < DEPTH; k = k + 1) mem_read(k, 0);
        end_test("T10");

        //--------------------------------------------------------------
        repeat (3) @(negedge clk);
        $display("============================================================");
        $display(" SUMMARY: %0d checks, %0d errors | %0d writes, %0d reads, %0d rejected",
                 checks, errors, n_wr, n_rd, n_rej);
        if (errors == 0) $display(" RESULT : ALL TESTS PASSED");
        else             $display(" RESULT : FAILURES DETECTED");
        $display("============================================================");
        $finish;
    end

    // watchdog
    initial begin
        #2_000_000;
        $display("TIMEOUT"); $finish;
    end
endmodule
