//============================================================================
// Module      : cov_monitor
// Project     : Programmable Memory Controller (MOSART Project 8)
// Description : Passive functional coverage monitor. It observes the host
//               interface, the configuration port and the live configuration
//               values of the design under test, counts how often each
//               coverage bin is hit, and prints a table when report() is
//               called. It never drives any signal.
//
//   Bin groups
//     operations      : accepted reads and writes, per programmed wait state
//     address         : first word, last word, interior word, last valid word
//                       below the programmed limit
//     error classes   : collision, range, write-protect violation, overrun
//     status register : every sticky bit seen set, every sticky bit cleared
//                       by a write-one-to-clear
//     configuration   : limit at zero, partial and full; limit saturation;
//                       write protect active during an accepted read;
//                       request while disabled
//     timing          : back-to-back, one-idle-cycle and longer gaps between
//                       transactions
//     data            : all-zero, all-one and mixed write data
//     reset           : reset applied while a transaction is in flight
//============================================================================
`timescale 1ns/1ps
module cov_monitor #(
    parameter DATA_W = 8,
    parameter ADDR_W = 4
)(
    input  wire              clk,
    input  wire              reset,
    input  wire              rd,
    input  wire              wr,
    input  wire [ADDR_W-1:0] addr,
    input  wire [DATA_W-1:0] wdata,
    input  wire              busy,
    input  wire              cfg_we,
    input  wire [1:0]        cfg_addr,
    input  wire [7:0]        cfg_wdata,
    input  wire [7:0]        cfg_rdata,
    input  wire              en,
    input  wire              wp,
    input  wire [2:0]        ws,
    input  wire [ADDR_W:0]   limit
);
    localparam DEPTH = (1 << ADDR_W);

    integer c_rd_acc = 0, c_wr_acc = 0;
    integer c_ws_rd [0:7];
    integer c_ws_wr [0:7];
    integer c_a_first = 0, c_a_last = 0, c_a_mid = 0, c_a_lim1 = 0;
    integer c_e_coll = 0, c_e_range = 0, c_e_wpv = 0, c_e_ovr = 0;
    integer c_st_seen [0:3];
    integer c_st_clr  [0:3];
    integer c_lim0 = 0, c_lim_part = 0, c_lim_full = 0, c_lim_sat = 0;
    integer c_wp_read = 0, c_en0_req = 0;
    integer c_gap0 = 0, c_gap1 = 0, c_gap2p = 0;
    integer c_d0 = 0, c_d1 = 0, c_dmix = 0;
    integer c_rst_busy = 0;
    integer idle_run = 0;
    integer i;

    initial begin
        for (i = 0; i < 8; i = i + 1) begin c_ws_rd[i] = 0; c_ws_wr[i] = 0; end
        for (i = 0; i < 4; i = i + 1) begin c_st_seen[i] = 0; c_st_clr[i] = 0; end
    end

    wire req      = rd | wr;
    wire idle_req = !busy && req && en;

    always @(posedge clk) begin
        if (reset && busy) c_rst_busy = c_rst_busy + 1;

        if (!reset) begin
            // ---------------- transactions ----------------
            if (idle_req) begin
                if (rd && wr)              c_e_coll  = c_e_coll  + 1;
                else if ({1'b0, addr} >= limit) c_e_range = c_e_range + 1;
                else if (wr && wp)         c_e_wpv   = c_e_wpv   + 1;
                else begin
                    if (wr) begin
                        c_wr_acc = c_wr_acc + 1; c_ws_wr[ws] = c_ws_wr[ws] + 1;
                        if (wdata == {DATA_W{1'b0}})      c_d0   = c_d0   + 1;
                        else if (wdata == {DATA_W{1'b1}}) c_d1   = c_d1   + 1;
                        else                              c_dmix = c_dmix + 1;
                    end else begin
                        c_rd_acc = c_rd_acc + 1; c_ws_rd[ws] = c_ws_rd[ws] + 1;
                        if (wp) c_wp_read = c_wp_read + 1;
                    end
                    if (addr == {ADDR_W{1'b0}})              c_a_first = c_a_first + 1;
                    else if (addr == DEPTH - 1)              c_a_last  = c_a_last  + 1;
                    else                                     c_a_mid   = c_a_mid   + 1;
                    if ({1'b0, addr} == limit - 1 && limit != DEPTH) c_a_lim1 = c_a_lim1 + 1;
                    if (idle_run == 0)      c_gap0  = c_gap0  + 1;
                    else if (idle_run == 1) c_gap1  = c_gap1  + 1;
                    else                    c_gap2p = c_gap2p + 1;
                end
                idle_run = 0;
            end else if (busy) begin
                idle_run = 0;
                if (req) c_e_ovr = c_e_ovr + 1;
            end else begin
                idle_run = idle_run + 1;
            end
            if (!en && req) c_en0_req = c_en0_req + 1;

            // ---------------- configuration and status ----------------
            if (limit == 0)          c_lim0     = c_lim0     + 1;
            else if (limit == DEPTH) c_lim_full = c_lim_full + 1;
            else                     c_lim_part = c_lim_part + 1;

            if (cfg_we && cfg_addr == 2'd2 && cfg_wdata[ADDR_W:0] > DEPTH)
                c_lim_sat = c_lim_sat + 1;

            if (cfg_addr == 2'd3) begin
                for (i = 0; i < 4; i = i + 1)
                    if (cfg_rdata[i]) c_st_seen[i] = c_st_seen[i] + 1;
                if (cfg_we)
                    for (i = 0; i < 4; i = i + 1)
                        if (cfg_wdata[i] && cfg_rdata[i]) c_st_clr[i] = c_st_clr[i] + 1;
            end
        end
    end

    // ---------------- report ----------------
    integer total, hit;
    task cov_bin(input [255:0] name, input integer cnt);
        begin
            total = total + 1;
            if (cnt > 0) begin hit = hit + 1; $display("  HIT   %-34s %0d", name, cnt); end
            else                               $display("  MISS  %-34s 0", name);
        end
    endtask

    task report;
        begin
            total = 0; hit = 0;
            $display("---------------- functional coverage ----------------");
            cov_bin("read accepted",            c_rd_acc);
            cov_bin("write accepted",           c_wr_acc);
            cov_bin("read,  wait states = 0", c_ws_rd[0]);
            cov_bin("write, wait states = 0", c_ws_wr[0]);
            cov_bin("read,  wait states = 1", c_ws_rd[1]);
            cov_bin("write, wait states = 1", c_ws_wr[1]);
            cov_bin("read,  wait states = 2", c_ws_rd[2]);
            cov_bin("write, wait states = 2", c_ws_wr[2]);
            cov_bin("read,  wait states = 3", c_ws_rd[3]);
            cov_bin("write, wait states = 3", c_ws_wr[3]);
            cov_bin("read,  wait states = 4", c_ws_rd[4]);
            cov_bin("write, wait states = 4", c_ws_wr[4]);
            cov_bin("read,  wait states = 5", c_ws_rd[5]);
            cov_bin("write, wait states = 5", c_ws_wr[5]);
            cov_bin("read,  wait states = 6", c_ws_rd[6]);
            cov_bin("write, wait states = 6", c_ws_wr[6]);
            cov_bin("read,  wait states = 7", c_ws_rd[7]);
            cov_bin("write, wait states = 7", c_ws_wr[7]);
            cov_bin("address = first word",     c_a_first);
            cov_bin("address = last word",      c_a_last);
            cov_bin("address = interior word",  c_a_mid);
            cov_bin("address = limit - 1",      c_a_lim1);
            cov_bin("error: collision",         c_e_coll);
            cov_bin("error: out of range",      c_e_range);
            cov_bin("error: write protect",     c_e_wpv);
            cov_bin("error: overrun (busy)",    c_e_ovr);
            cov_bin("status COLL seen set",     c_st_seen[0]);
            cov_bin("status RANGE seen set",    c_st_seen[1]);
            cov_bin("status WPV seen set",      c_st_seen[2]);
            cov_bin("status OVR seen set",      c_st_seen[3]);
            cov_bin("status COLL cleared (W1C)", c_st_clr[0]);
            cov_bin("status RANGE cleared (W1C)", c_st_clr[1]);
            cov_bin("status WPV cleared (W1C)", c_st_clr[2]);
            cov_bin("status OVR cleared (W1C)", c_st_clr[3]);
            cov_bin("limit = 0",                c_lim0);
            cov_bin("limit partial",            c_lim_part);
            cov_bin("limit = full depth",       c_lim_full);
            cov_bin("limit write saturates",    c_lim_sat);
            cov_bin("read accepted with WP = 1", c_wp_read);
            cov_bin("request while disabled",   c_en0_req);
            cov_bin("gap 0 (back to back)",     c_gap0);
            cov_bin("gap 1 idle cycle",         c_gap1);
            cov_bin("gap 2 or more idle cycles", c_gap2p);
            cov_bin("write data all zero",      c_d0);
            cov_bin("write data all one",       c_d1);
            cov_bin("write data mixed",         c_dmix);
            cov_bin("reset while busy",         c_rst_busy);
            $display("  COVERAGE: %0d of %0d bins hit (%0d percent)",
                     hit, total, (hit * 100) / total);
            $display("-----------------------------------------------------");
        end
    endtask
endmodule
