`timescale 1ns/1ps
// Checks the board wrapper: MODE=0, MODE=1 must PASS; a forced read fault must FAIL.
module tb_edge_selftest;
    reg clk = 0;
    always #10 clk = ~clk;            // 50 MHz
    reg rst = 1;
    reg mode0 = 0, mode1 = 1, mode_f = 0;
    wire [3:0] o0, o1, of;

    edge_selftest_top #(.CLK_HZ(200)) d0 (.CLK(clk), .RST(rst), .MODE(mode0),  .SERIAL_OUT(o0));
    edge_selftest_top #(.CLK_HZ(200)) d1 (.CLK(clk), .RST(rst), .MODE(mode1),  .SERIAL_OUT(o1));
    edge_selftest_top #(.CLK_HZ(200)) df (.CLK(clk), .RST(rst), .MODE(mode_f), .SERIAL_OUT(of));

    integer errors = 0;
    task chk(input [255:0] name, input cond);
        begin
            if (!cond) begin errors = errors + 1; $display("FAIL: %0s", name); end
            else $display("ok  : %0s", name);
        end
    endtask

    initial begin
        #200 rst = 0;
        #1000;
        force df.u_dut.u_mem.mem_rdata = 8'h00;   // inject a read fault
        #20000;
        $display("outputs: mode0=%b mode1=%b fault=%b", o0, o1, of);
        chk("MODE=0 done",        o0[2]);
        chk("MODE=0 pass",        o0[0] && !o0[1]);
        chk("MODE=1 done",        o1[2]);
        chk("MODE=1 pass",        o1[0] && !o1[1]);
        chk("fault run detected", of[1] && !of[0]);
        // heartbeat toggles
        begin : hbt
            integer k, hi, lo; hi = 0; lo = 0;
            for (k = 0; k < 300; k = k + 1) begin
                @(posedge clk); if (o0[3]) hi = hi + 1; else lo = lo + 1;
            end
            chk("heartbeat toggles", hi > 0 && lo > 0);
        end
        // reset restarts the sequence
        rst = 1; #100; chk("reset clears done", !o0[2]); rst = 0; #20000;
        chk("re-run after reset passes", o0[0] && o0[2] && !o0[1]);
        if (errors == 0) $display("RESULT : ALL TESTS PASSED");
        else             $display("RESULT : %0d FAILURES", errors);
        $finish;
    end
endmodule
