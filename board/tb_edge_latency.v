`timescale 1ns/1ps
// Self-checking testbench for edge_latency_top.
//  - the sweep finishes, PASS is lit and every stored measurement equals the
//    design equations (L = 2 + N, T = 16 * (3 + N))
//  - the decoded 7-segment display shows the right number for every
//    combination of sw[2:0] and sw[4:3]
//  - an injected fault (wait states forced to zero) is reported as FAIL
//  - the centre button restarts the sweep
module tb_edge_latency;
    reg CLK = 0;
    always #10 CLK = ~CLK;            // 50 MHz

    reg  [15:0] sw = 0;
    reg  [4:0]  pb = 5'b10000;        // centre button held: reset
    wire [15:0] led;
    wire [3:0]  digit;
    wire [7:0]  Seven_Seg;

    edge_latency_top #(.CLK_HZ(200), .SCAN_BITS(3)) dut (
        .CLK(CLK), .sw(sw), .pb(pb), .led(led), .digit(digit), .Seven_Seg(Seven_Seg));

    wire [15:0] led_f; wire [3:0] digit_f; wire [7:0] seg_f;
    edge_latency_top #(.CLK_HZ(200), .SCAN_BITS(3)) dut_fault (
        .CLK(CLK), .sw(16'h0), .pb(pb), .led(led_f), .digit(digit_f), .Seven_Seg(seg_f));

    integer errors = 0, checks = 0;
    task check(input [255:0] what, input [31:0] got, input [31:0] exp);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  ** FAIL %0s : got %0d expected %0d", what, got, exp);
            end
        end
    endtask

    // decode one lit digit: returns 0..9, 10 blank, 11 dash, 15 unknown
    function [3:0] decode(input [6:0] seg_n);
        reg [6:0] p;
        begin
            p = ~seg_n;
            case (p)
                7'h3F: decode = 0;  7'h06: decode = 1;  7'h5B: decode = 2;
                7'h4F: decode = 3;  7'h66: decode = 4;  7'h6D: decode = 5;
                7'h7D: decode = 6;  7'h07: decode = 7;  7'h7F: decode = 8;
                7'h6F: decode = 9;  7'h00: decode = 10; 7'h40: decode = 11;
                default: decode = 15;
            endcase
        end
    endfunction

    reg [3:0] ch [0:3];
    integer t, i, nn, qq, expv, h, te, o;
    reg [3:0] e0, e1, e2, e3;

    // capture one full display frame
    task capture;
        begin
            for (t = 0; t < 40; t = t + 1) begin
                @(posedge CLK); #1;
                for (i = 0; i < 4; i = i + 1)
                    if (digit[i]) ch[i] = decode(Seven_Seg[6:0]);
            end
        end
    endtask

    initial begin
        repeat (10) @(posedge CLK);
        pb = 5'b00000;
        // wait for DONE
        begin : waitdone
            integer w;
            for (w = 0; w < 20000 && !led[2]; w = w + 1) @(posedge CLK);
        end
        check("DONE lit", led[2], 1);
        check("PASS lit", led[0], 1);
        check("FAIL dark", led[1], 0);

        for (nn = 0; nn < 8; nn = nn + 1) begin
            check("L_w equation", dut.lat_w[nn], nn + 2);
            check("L_r equation", dut.lat_r[nn], nn + 2);
            check("T equation",   dut.tp[nn],   16 * (nn + 3));
        end

        // display decode for every selection
        for (qq = 0; qq < 4; qq = qq + 1)
            for (nn = 0; nn < 8; nn = nn + 1) begin
                sw = {11'b0, qq[1:0], nn[2:0]};
                repeat (20) @(posedge CLK);
                capture;
                expv = (qq == 2) ? 16 * (nn + 3) : (qq == 3) ? (nn + 3) : (nn + 2);
                h = expv / 100; te = (expv / 10) % 10; o = expv % 10;
                e0 = nn;
                e1 = (h == 0) ? 4'd10 : h;
                e2 = (h == 0 && te == 0) ? 4'd10 : te;
                e3 = o;
                check("display digit 0", ch[0], e0);
                check("display digit 1", ch[1], e1);
                check("display digit 2", ch[2], e2);
                check("display digit 3", ch[3], e3);
            end

        // fault injection: the second instance gets its wait-state register forced to 0
        pb = 5'b10000; repeat (4) @(posedge CLK); pb = 5'b00000;
        force dut_fault.u_dut.u_cfg.wait_states = 3'd0;
        begin : waitdone2
            integer w;
            for (w = 0; w < 20000 && !led_f[2]; w = w + 1) @(posedge CLK);
        end
        check("fault run finishes", led_f[2], 1);
        check("fault run reports FAIL", led_f[1], 1);
        check("fault run not PASS", led_f[0], 0);
        release dut_fault.u_dut.u_cfg.wait_states;

        // restart by the centre button
        pb = 5'b10000; repeat (4) @(posedge CLK);
        check("DONE cleared by restart", led[2], 0);
        pb = 5'b00000;
        begin : waitdone3
            integer w;
            for (w = 0; w < 20000 && !led[2]; w = w + 1) @(posedge CLK);
        end
        check("PASS after restart", led[0] && led[2] && !led[1], 1);

        if (errors == 0) $display("RESULT : ALL TESTS PASSED (%0d checks)", checks);
        else             $display("RESULT : %0d FAILURES in %0d checks", errors, checks);
        $finish;
    end

    initial begin #50_000_000; $display("TIMEOUT"); $finish; end
endmodule
