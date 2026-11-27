// Passive functional coverage monitor for sfifo (OPT_ASYNC_READ = 0).
// It watches the ports only and counts how often each bin is hit.
// report() prints every bin and the number of bins hit.
`timescale 1ns/1ps
module cov_sfifo #(parameter LGFLEN = 4) (
    input wire            clk,
    input wire            rst,
    input wire            wr,
    input wire            rd,
    input wire            full,
    input wire            empty,
    input wire [LGFLEN:0] fill
);
    localparam FLEN = (1 << LGFLEN);
    localparam NB = 21;
    integer hits [0:NB-1];
    reg [8*40-1:0] name [0:NB-1];
    integer i, wr_cnt, rd_cnt;
    reg prev_rd_acc, prev_wr_acc;
    reg [LGFLEN:0] prev_fill;

    initial begin
        for (i = 0; i < NB; i = i + 1) hits[i] = 0;
        name[0]  = "fill level 0";
        name[1]  = "fill level 1";
        name[2]  = "fill level 2 to FLEN-2";
        name[3]  = "fill level FLEN-1";
        name[4]  = "fill level FLEN (full)";
        name[5]  = "write accepted when empty";
        name[6]  = "write accepted at mid level";
        name[7]  = "write accepted at FLEN-1";
        name[8]  = "write rejected when full";
        name[9]  = "read accepted at level 1";
        name[10] = "read accepted at mid level";
        name[11] = "read accepted when full";
        name[12] = "read rejected when empty";
        name[13] = "read and write when empty";
        name[14] = "read and write when full";
        name[15] = "read and write at mid level";
        name[16] = "reset while not empty";
        name[17] = "write pointer wraps";
        name[18] = "read pointer wraps";
        name[19] = "back-to-back reads";
        name[20] = "write then read at level 1";
        wr_cnt = 0; rd_cnt = 0;
        prev_rd_acc = 0; prev_wr_acc = 0; prev_fill = 0;
    end

    wire wr_acc = wr && !full;
    wire rd_acc = rd && !empty;
    wire mid    = (fill >= 2) && (fill <= FLEN - 2);

    always @(posedge clk) begin
        if (rst) begin
            if (!empty) hits[16] = hits[16] + 1;
            wr_cnt = 0; rd_cnt = 0;
            prev_rd_acc = 0; prev_wr_acc = 0;
        end else begin
            if (fill == 0)        hits[0] = hits[0] + 1;
            if (fill == 1)        hits[1] = hits[1] + 1;
            if (mid)              hits[2] = hits[2] + 1;
            if (fill == FLEN - 1) hits[3] = hits[3] + 1;
            if (fill == FLEN)     hits[4] = hits[4] + 1;
            if (wr_acc && empty)            hits[5] = hits[5] + 1;
            if (wr_acc && mid)              hits[6] = hits[6] + 1;
            if (wr_acc && fill == FLEN - 1) hits[7] = hits[7] + 1;
            if (wr && full)                 hits[8] = hits[8] + 1;
            if (rd_acc && fill == 1)        hits[9] = hits[9] + 1;
            if (rd_acc && mid)              hits[10] = hits[10] + 1;
            if (rd_acc && full)             hits[11] = hits[11] + 1;
            if (rd && empty)                hits[12] = hits[12] + 1;
            if (rd && wr && empty)          hits[13] = hits[13] + 1;
            if (rd && wr && full)           hits[14] = hits[14] + 1;
            if (rd && wr && mid)            hits[15] = hits[15] + 1;
            if (wr_acc) begin
                wr_cnt = wr_cnt + 1;
                if (wr_cnt == FLEN + 1) hits[17] = hits[17] + 1;
            end
            if (rd_acc) begin
                rd_cnt = rd_cnt + 1;
                if (rd_cnt == FLEN + 1) hits[18] = hits[18] + 1;
            end
            if (rd_acc && prev_rd_acc)                    hits[19] = hits[19] + 1;
            if (rd_acc && fill == 1 && prev_wr_acc && prev_fill == 0) hits[20] = hits[20] + 1;
            prev_rd_acc = rd_acc; prev_wr_acc = wr_acc; prev_fill = fill;
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
