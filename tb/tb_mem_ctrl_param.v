//============================================================================
// Testbench   : tb_mem_ctrl_param
// Project     : Programmable Memory Controller (MOSART Project 8)
// Description : Self-checking testbench that works for any data width and for
//               address widths 2 to 6. A reference model mirrors every
//               accepted write. Every read, every error flag, every access
//               latency and every status and configuration read-back is
//               compared against the model. Directed tests come first, then a
//               seeded constrained-random run. A passive coverage monitor
//               reports which bins were reached.
//
//   Parameters : DATA_W, ADDR_W, NRAND (random iterations), SEED
//   Latency    : accepted access = 2 + wait states cycles, rejected request
//                = 1 cycle (measured from the cycle after the request is
//                applied to the cycle in which ready is seen)
//============================================================================
`timescale 1ns/1ps
module tb_mem_ctrl_param;
    parameter DATA_W = 8;
    parameter ADDR_W = 4;
    parameter NRAND  = 3000;
    parameter SEED   = 1;

    localparam DEPTH = (1 << ADDR_W);
    localparam CLK_P = 10;
    localparam [DATA_W-1:0] ONES = {DATA_W{1'b1}};

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

    cov_monitor #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) cov (
        .clk(clk), .reset(reset),
        .rd(read_enable), .wr(write_enable), .addr(address), .wdata(write_data),
        .busy(busy),
        .cfg_we(cfg_we), .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata),
        .cfg_rdata(cfg_rdata),
        .en(dut.u_cfg.en), .wp(dut.u_cfg.wp),
        .ws(dut.u_cfg.wait_states), .limit(dut.u_cfg.addr_limit)
    );

    always #(CLK_P/2) clk = ~clk;

    // ---------------- reference model and bookkeeping ----------------
    reg [DATA_W-1:0] model [0:DEPTH-1];
    integer errors = 0, checks = 0, test_errors_start = 0;
    integer seed = SEED;
    integer lat, k, n, ws_i, ad_i;
    integer n_rd = 0, n_wr = 0, n_rej = 0;
    reg       got_err;
    reg [DATA_W-1:0] held;
    // shadow of the programmed configuration and of the sticky status bits
    reg       m_en = 1, m_wp = 0;
    integer   m_ws = 0, m_limit = DEPTH;
    reg [3:0] sticky = 4'b0000;

    function integer rnd(input integer m);
        begin
            rnd = ($random(seed) & 32'h7FFFFFFF) % m;
        end
    endfunction

    function [DATA_W-1:0] rnd_data(input integer dummy);
        reg [31:0] r;
        begin
            r = $random(seed);
            rnd_data = r[DATA_W-1:0];
        end
    endfunction

    task check(input [255:0] what, input [31:0] got, input [31:0] exp);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  ** FAIL %0s : got 0x%0h expected 0x%0h @ %0t",
                         what, got, exp, $time);
            end
        end
    endtask

    task begin_test(input [255:0] name);
        begin
            test_errors_start = errors;
            $display("[%0t] TEST: %0s", $time, name);
        end
    endtask

    task end_test(input [255:0] name);
        begin
            if (errors == test_errors_start) $display("    -> PASS  %0s", name);
            else                             $display("    -> FAIL  %0s", name);
        end
    endtask

    // ---------------- configuration port ----------------
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

    task set_ws(input integer v);
        begin cfg_write(2'd1, v[7:0]); m_ws = v; end
    endtask

    task set_limit(input integer v);
        begin
            cfg_write(2'd2, v[7:0]);
            m_limit = (v > DEPTH) ? DEPTH : v;
        end
    endtask

    task set_wp(input v);
        begin cfg_write(2'd0, {6'b0, v, 1'b1}); m_wp = v; end
    endtask

    task clear_status(input [3:0] mask);
        begin cfg_write(2'd3, {4'b0, mask}); sticky = sticky & ~mask; end
    endtask

    task expect_status;
        begin cfg_expect(2'd3, {3'b000, 1'b0, sticky}); end
    endtask

    // ---------------- host transactions ----------------
    task idle(input integer cycles);
        begin repeat (cycles) @(negedge clk); end
    endtask

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

    // expected error of a single (non-colliding) request under the shadow config
    function exp_err_of(input is_wr, input integer ad);
        begin
            exp_err_of = (ad >= m_limit) || (is_wr && m_wp);
        end
    endfunction

    // keep the shadow sticky bits in step with a request made while idle
    task note_event(input rd, input wr, input integer ad);
        begin
            if (rd && wr)               sticky[0] = 1;
            else if (ad >= m_limit)     sticky[1] = 1;
            else if (wr && m_wp)        sticky[2] = 1;
        end
    endtask

    task mem_write(input [ADDR_W-1:0] ad, input [DATA_W-1:0] dat);
        reg e;
        begin
            e = exp_err_of(1, ad);
            do_access(0, 1, ad, dat, lat, got_err);
            check("write error flag", got_err, e);
            check("write latency", lat, e ? 1 : 2 + m_ws);
            note_event(0, 1, ad);
            if (!e) begin model[ad] = dat; n_wr = n_wr + 1; end
            else    n_rej = n_rej + 1;
        end
    endtask

    task mem_read(input [ADDR_W-1:0] ad);
        reg e;
        begin
            e = exp_err_of(0, ad);
            do_access(1, 0, ad, {DATA_W{1'b0}}, lat, got_err);
            check("read error flag", got_err, e);
            check("read latency", lat, e ? 1 : 2 + m_ws);
            note_event(1, 0, ad);
            if (!e) begin
                check("read data", read_data, model[ad]);
                n_rd = n_rd + 1;
            end else n_rej = n_rej + 1;
        end
    endtask

    task collide(input [ADDR_W-1:0] ad, input [DATA_W-1:0] dat);
        begin
            do_access(1, 1, ad, dat, lat, got_err);
            check("collision error flag", got_err, 1);
            check("collision latency", lat, 1);
            note_event(1, 1, ad);
            n_rej = n_rej + 1;
        end
    endtask

    // second request arrives while the first is in flight and is dropped
    task overrun(input [ADDR_W-1:0] a1, input [ADDR_W-1:0] a2);
        begin
            @(negedge clk);
            write_enable = 1; address = a1; write_data = rnd_data(0);
            model[a1] = write_data; n_wr = n_wr + 1;
            @(negedge clk);
            write_enable = 1; address = a2; write_data = ~write_data;
            @(negedge clk);
            write_enable = 0;
            while (!ready) @(negedge clk);
            sticky[3] = 1;
        end
    endtask

    // ---------------- stimulus ----------------
    integer r, op, v, g;
    initial begin
        for (k = 0; k < DEPTH; k = k + 1) model[k] = {DATA_W{1'b0}};

        repeat (3) @(negedge clk);
        reset = 0;

        //--------------------------------------------------------------
        begin_test("D1 reset values of the configuration registers");
        cfg_expect(2'd0, 8'h01);
        cfg_expect(2'd1, 8'h00);
        cfg_expect(2'd2, DEPTH[7:0]);
        cfg_expect(2'd3, 8'h00);
        check("busy after reset", busy, 0);
        check("ready after reset", ready, 0);
        end_test("D1");

        //--------------------------------------------------------------
        begin_test("D1b memory contents and read data after power-up are zero");
        check("read_data at power-up", read_data, 0);
        for (k = 0; k < DEPTH; k = k + 1) mem_read(k);
        end_test("D1b");

        //--------------------------------------------------------------
        begin_test("D2 write every word, read every word, zero wait states");
        for (k = 0; k < DEPTH; k = k + 1)
            mem_write(k, (k == 0) ? {DATA_W{1'b0}} : (k == 1) ? ONES : rnd_data(0));
        for (k = 0; k < DEPTH; k = k + 1) mem_read(k);
        end_test("D2");

        //--------------------------------------------------------------
        begin_test("D3 programmable wait states 1 to 7");
        for (ws_i = 1; ws_i < 8; ws_i = ws_i + 1) begin
            set_ws(ws_i);
            mem_write(ws_i % DEPTH, rnd_data(0));
            mem_read (ws_i % DEPTH);
        end
        set_ws(0);
        end_test("D3");

        //--------------------------------------------------------------
        begin_test("D4 simultaneous read and write request is rejected");
        collide(DEPTH - 1, rnd_data(0));
        expect_status;
        mem_read(DEPTH - 1);
        clear_status(4'b0001);
        expect_status;
        end_test("D4");

        //--------------------------------------------------------------
        begin_test("D5 address limit, saturation and the full range");
        set_limit(DEPTH / 2);
        cfg_expect(2'd2, (DEPTH / 2));
        mem_write(DEPTH / 2, rnd_data(0));
        mem_read (DEPTH - 1);
        expect_status;
        mem_write(DEPTH / 2 - 1, rnd_data(0));
        mem_read (DEPTH / 2 - 1);
        set_limit(0);
        mem_read(0);
        set_limit(8'hFF);
        cfg_expect(2'd2, DEPTH[7:0]);
        mem_read(DEPTH - 1);
        clear_status(4'b1111);
        expect_status;
        end_test("D5");

        //--------------------------------------------------------------
        begin_test("D6 write protect");
        set_wp(1);
        mem_write(0, rnd_data(0));
        expect_status;
        mem_read(0);
        set_wp(0);
        clear_status(4'b1111);
        mem_write(0, rnd_data(0));
        mem_read(0);
        end_test("D6");

        //--------------------------------------------------------------
        begin_test("D7 request while busy is dropped and flagged");
        set_ws(4);
        overrun(1, DEPTH - 1);
        expect_status;
        mem_read(1);
        mem_read(DEPTH - 1);
        clear_status(4'b1111);
        set_ws(0);
        end_test("D7");

        //--------------------------------------------------------------
        begin_test("D8 controller disabled ignores requests");
        cfg_write(2'd0, 8'h00);
        m_en = 0;
        @(negedge clk);
        write_enable = 1; address = 1; write_data = rnd_data(0);
        repeat (4) begin
            @(negedge clk);
            check("busy while disabled", busy, 0);
            check("ready while disabled", ready, 0);
        end
        write_enable = 0;
        cfg_write(2'd0, 8'h01);
        m_en = 1;
        mem_read(1);
        end_test("D8");

        //--------------------------------------------------------------
        begin_test("D9 reset during a transaction");
        set_ws(5);
        @(negedge clk);
        read_enable = 1; address = 0;
        @(negedge clk); read_enable = 0;
        @(negedge clk); @(negedge clk);
        check("busy mid-transaction", busy, 1);
        reset = 1; @(negedge clk); reset = 0;
        check("busy after reset", busy, 0);
        m_ws = 0; m_limit = DEPTH; m_wp = 0; m_en = 1; sticky = 0;
        cfg_expect(2'd1, 8'd0);
        cfg_expect(2'd2, DEPTH[7:0]);
        mem_read(0);
        end_test("D9");

        //--------------------------------------------------------------
        begin_test("D10 STATUS read while busy shows the BUSY bit");
        set_ws(3);
        @(negedge clk);
        read_enable = 1; address = 1;
        @(negedge clk);
        read_enable = 0; cfg_addr = 2'd3; #1;
        check("STATUS while busy", cfg_rdata, {3'b000, 1'b1, sticky});
        while (!ready) @(negedge clk);
        n_rd = n_rd + 1;
        check("read data", read_data, model[1]);
        set_ws(0);
        end_test("D10");

        //--------------------------------------------------------------
        begin_test("D11 an event and a clear in the same cycle: the event wins");
        @(negedge clk);
        read_enable = 1; write_enable = 1; address = 0;     // collision
        @(negedge clk);
        read_enable = 0; write_enable = 0;
        cfg_we = 1; cfg_addr = 2'd3; cfg_wdata = 8'h01;      // clear COLL while the event pulse is active
        @(negedge clk);
        cfg_we = 0;
        sticky[0] = 1; n_rej = n_rej + 1;
        expect_status;
        clear_status(4'b1111);
        expect_status;
        end_test("D11");

        //--------------------------------------------------------------
        begin_test("D12 an out-of-range request while disabled raises no event");
        set_limit(DEPTH / 2);
        cfg_write(2'd0, 8'h00);
        m_en = 0;
        @(negedge clk);
        read_enable = 1; address = DEPTH - 1;
        repeat (4) @(negedge clk);
        read_enable = 0;
        expect_status;                                       // must still be zero
        cfg_write(2'd0, 8'h01);
        m_en = 1;
        set_limit(DEPTH);
        end_test("D12");

        //--------------------------------------------------------------
        begin_test("D13 read data is held until the next read");
        mem_write(0, rnd_data(0));
        mem_write(1, rnd_data(0));
        mem_read(0);
        held = read_data;
        idle(3);
        check("read_data held while idle", read_data, held);
        mem_write(1, ~model[1]);
        idle(2);
        check("read_data held after a write", read_data, held);
        mem_read(1);
        check("read_data follows the new read", read_data, model[1]);
        end_test("D13");

        //--------------------------------------------------------------
        begin_test("R1 constrained-random regression");
        for (k = 0; k < NRAND; k = k + 1) begin
            g = rnd(8);
            idle((g < 4) ? 0 : (g < 6) ? 1 : rnd(4));
            r = rnd(100);
            if (r < 55) begin
                op = rnd(2);
                if (rnd(8) == 0)      ad_i = DEPTH - 1;
                else if (rnd(8) == 0) ad_i = (m_limit > 0) ? m_limit - 1 : 0;
                else                  ad_i = rnd(DEPTH);
                if (op) mem_write(ad_i, (rnd(12) == 0) ? {DATA_W{1'b0}} :
                                        (rnd(12) == 0) ? ONES : rnd_data(0));
                else    mem_read(ad_i);
            end else if (r < 62) begin
                collide(rnd(DEPTH), rnd_data(0));
            end else if (r < 70) begin
                set_ws(rnd(8));
            end else if (r < 78) begin
                v = rnd(DEPTH + 4);
                if (rnd(6) == 0) v = DEPTH;
                if (rnd(10) == 0) v = 0;
                set_limit(v);
            end else if (r < 84) begin
                set_wp(!m_wp);
            end else if (r < 92) begin
                expect_status;
            end else if (r < 96) begin
                clear_status(rnd(16));
            end else if (m_limit > 1 && !m_wp) begin
                overrun(rnd(m_limit), rnd(DEPTH));
            end
        end
        set_wp(0);
        set_limit(DEPTH);
        set_ws(0);
        clear_status(4'b1111);
        expect_status;
        for (k = 0; k < DEPTH; k = k + 1) mem_read(k);
        end_test("R1");

        //--------------------------------------------------------------
        repeat (3) @(negedge clk);
        $display("============================================================");
        $display(" CONFIG : DATA_W=%0d ADDR_W=%0d NRAND=%0d SEED=%0d", DATA_W, ADDR_W, NRAND, SEED);
        $display(" SUMMARY: %0d checks, %0d errors | %0d writes, %0d reads, %0d rejected",
                 checks, errors, n_wr, n_rd, n_rej);
        cov.report;
        if (errors == 0) $display(" RESULT : ALL TESTS PASSED");
        else             $display(" RESULT : FAILURES DETECTED");
        $display("============================================================");
        $finish;
    end

    // watchdog
    initial begin
        #200_000_000;
        $display("TIMEOUT"); $finish;
    end
endmodule
