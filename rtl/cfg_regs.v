//============================================================================
// Module      : cfg_regs
// Project     : MOSART Project 8 - Programmable Memory Controller
// Author      : Shaun Praneeth Raj
// Description : Configuration and status register bank. Programs the
//               controller behaviour at run time.
//
//   Addr  Name    Bits   Access  Reset  Meaning
//   0x0   CTRL    [0]    RW      1      EN  : controller enable
//                 [1]    RW      0      WP  : write protect (writes rejected)
//   0x1   WAIT    [2:0]  RW      0      number of wait states per access
//   0x2   LIMIT   [4:0]  RW      16     number of valid words (addr < LIMIT)
//   0x3   STATUS  [0]    W1C     0      COLL : simultaneous read+write request
//                 [1]    W1C     0      RANGE: address >= LIMIT
//                 [2]    W1C     0      WPV  : write attempted while WP = 1
//                 [3]    W1C     0      OVR  : request dropped while busy
//                 [4]    RO      -      BUSY : controller busy (live)
//                 [7:5]  RO      0      reserved
//============================================================================
`timescale 1ns / 1ps
module cfg_regs #(
    parameter ADDR_W = 4
)(
    input  wire          clk,
    input  wire          reset,       // synchronous, active high
    // configuration port
    input  wire          cfg_we,
    input  wire [1:0]    cfg_addr,
    input  wire [7:0]    cfg_wdata,
    output reg  [7:0]    cfg_rdata,
    // decoded controls to the FSM
    output reg           en,
    output reg           wp,
    output reg  [2:0]    wait_states,
    output reg  [ADDR_W:0] addr_limit,
    // error events from the FSM (one-cycle pulses)
    input  wire          ev_coll,
    input  wire          ev_range,
    input  wire          ev_wpv,
    input  wire          ev_ovr,
    input  wire          busy
);
    localparam A_CTRL = 2'd0, A_WAIT = 2'd1, A_LIMIT = 2'd2, A_STAT = 2'd3;

    reg [3:0] sticky;   // {OVR, WPV, RANGE, COLL}

    wire [3:0] clr = (cfg_we && cfg_addr == A_STAT) ? cfg_wdata[3:0] : 4'b0;
    wire [3:0] set = {ev_ovr, ev_wpv, ev_range, ev_coll};

    always @(posedge clk) begin
        if (reset) begin
            en          <= 1'b1;
            wp          <= 1'b0;
            wait_states <= 3'd0;
            addr_limit  <= (1 << ADDR_W);
            sticky      <= 4'b0;
        end else begin
            if (cfg_we) begin
                case (cfg_addr)
                    A_CTRL : begin en <= cfg_wdata[0]; wp <= cfg_wdata[1]; end
                    A_WAIT : wait_states <= cfg_wdata[2:0];
                    A_LIMIT: addr_limit  <= (cfg_wdata[ADDR_W:0] > (1 << ADDR_W))
                                            ? (1 << ADDR_W) : cfg_wdata[ADDR_W:0];
                    default: ;
                endcase
            end
            // a new event in the same cycle wins over the clear
            sticky <= (sticky & ~clr) | set;
        end
    end

    // combinational read-back
    always @(*) begin
        case (cfg_addr)
            A_CTRL : cfg_rdata = {6'b0, wp, en};
            A_WAIT : cfg_rdata = {5'b0, wait_states};
            A_LIMIT: cfg_rdata = {{(7-ADDR_W){1'b0}}, addr_limit};
            default: cfg_rdata = {3'b0, busy, sticky};
        endcase
    end
endmodule
