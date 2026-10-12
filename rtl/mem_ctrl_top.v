//============================================================================
// Module      : mem_ctrl_top
// Project     : MOSART Project 8 - Programmable Memory Controller
// Author      : Shaun Praneeth Raj
// Description : Top level. Connects the configuration register bank, the
//               controller FSM and the 16 x 8 synchronous register-array
//               memory. All logic is in a single clock domain (clk) with a
//               synchronous active-high reset.
//============================================================================
`timescale 1ns / 1ps
module mem_ctrl_top #(
    parameter DATA_W = 8,
    parameter ADDR_W = 4
)(
    input  wire              clk,
    input  wire              reset,
    // host request interface
    input  wire              read_enable,
    input  wire              write_enable,
    input  wire [ADDR_W-1:0] address,
    input  wire [DATA_W-1:0] write_data,
    output wire [DATA_W-1:0] read_data,
    output wire              ready,
    output wire              busy,
    output wire              error,
    // configuration interface
    input  wire              cfg_we,
    input  wire [1:0]        cfg_addr,
    input  wire [7:0]        cfg_wdata,
    output wire [7:0]        cfg_rdata
);
    wire              en, wp;
    wire [2:0]        wait_states;
    wire [ADDR_W:0]   addr_limit;
    wire              mem_we, mem_re;
    wire [ADDR_W-1:0] mem_addr;
    wire [DATA_W-1:0] mem_wdata;
    wire              ev_coll, ev_range, ev_wpv, ev_ovr;

    cfg_regs #(.ADDR_W(ADDR_W)) u_cfg (
        .clk(clk), .reset(reset),
        .cfg_we(cfg_we), .cfg_addr(cfg_addr),
        .cfg_wdata(cfg_wdata), .cfg_rdata(cfg_rdata),
        .en(en), .wp(wp), .wait_states(wait_states), .addr_limit(addr_limit),
        .ev_coll(ev_coll), .ev_range(ev_range), .ev_wpv(ev_wpv),
        .ev_ovr(ev_ovr), .busy(busy)
    );

    mem_ctrl_fsm #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_fsm (
        .clk(clk), .reset(reset),
        .read_enable(read_enable), .write_enable(write_enable),
        .address(address), .write_data(write_data),
        .ready(ready), .busy(busy), .error(error),
        .en(en), .wp(wp), .wait_states(wait_states), .addr_limit(addr_limit),
        .mem_we(mem_we), .mem_re(mem_re),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .ev_coll(ev_coll), .ev_range(ev_range), .ev_wpv(ev_wpv), .ev_ovr(ev_ovr)
    );

    sync_mem #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_mem (
        .clk(clk),
        .mem_we(mem_we), .mem_re(mem_re),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_rdata(read_data)
    );
endmodule
