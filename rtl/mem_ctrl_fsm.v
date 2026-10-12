//============================================================================
// Module      : mem_ctrl_fsm
// Project     : MOSART Project 8 - Programmable Memory Controller
// Author      : Shaun Praneeth Raj
// Description : Control path. Accepts one request at a time from the host,
//               validates it, drives the memory strobes, inserts the
//               programmed number of wait states and signals completion.
//
//   States : IDLE -> READ  -> [WAIT] -> DONE -> IDLE
//            IDLE -> WRITE -> [WAIT] -> DONE -> IDLE
//            IDLE -> ERROR -> IDLE              (rejected request)
//
//   busy  = 1 in every state except IDLE
//   ready = 1 for one cycle in DONE or ERROR (transaction finished)
//   error = 1 for one cycle in ERROR (request rejected, memory untouched)
//============================================================================
`timescale 1ns / 1ps
module mem_ctrl_fsm #(
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
    output wire              ready,
    output wire              busy,
    output wire              error,
    // programmed configuration
    input  wire              en,
    input  wire              wp,
    input  wire [2:0]        wait_states,
    input  wire [ADDR_W:0]   addr_limit,
    // memory control
    output wire              mem_we,
    output wire              mem_re,
    output wire [ADDR_W-1:0] mem_addr,
    output wire [DATA_W-1:0] mem_wdata,
    // error events to the status register
    output reg               ev_coll,
    output reg               ev_range,
    output reg               ev_wpv,
    output reg               ev_ovr
);
    localparam [2:0] S_IDLE  = 3'd0,
                     S_READ  = 3'd1,
                     S_WRITE = 3'd2,
                     S_WAIT  = 3'd3,
                     S_DONE  = 3'd4,
                     S_ERROR = 3'd5;

    reg [2:0]        state, next_state;
    reg [ADDR_W-1:0] addr_q;
    reg [DATA_W-1:0] wdata_q;
    reg [2:0]        wcnt;

    wire req      = read_enable | write_enable;
    wire coll     = read_enable & write_enable;
    wire range_bad = ({1'b0, address} >= addr_limit);
    wire wp_bad   = write_enable & wp;

    // ---------------- next-state logic ----------------
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:
                if (en && req) begin
                    if (coll || range_bad || wp_bad) next_state = S_ERROR;
                    else if (write_enable)           next_state = S_WRITE;
                    else                             next_state = S_READ;
                end
            S_READ,
            S_WRITE: next_state = (wait_states != 3'd0) ? S_WAIT : S_DONE;
            S_WAIT : next_state = (wcnt == 3'd0) ? S_DONE : S_WAIT;
            S_DONE : next_state = S_IDLE;
            S_ERROR: next_state = S_IDLE;
            default: next_state = S_IDLE;
        endcase
    end

    // ---------------- state, request latch, wait counter ----------------
    always @(posedge clk) begin
        if (reset) begin
            state   <= S_IDLE;
            addr_q  <= {ADDR_W{1'b0}};
            wdata_q <= {DATA_W{1'b0}};
            wcnt    <= 3'd0;
        end else begin
            state <= next_state;
            if (state == S_IDLE && en && req) begin
                addr_q  <= address;
                wdata_q <= write_data;
            end
            if ((state == S_READ || state == S_WRITE) && wait_states != 3'd0)
                wcnt <= wait_states - 3'd1;
            else if (state == S_WAIT && wcnt != 3'd0)
                wcnt <= wcnt - 3'd1;
        end
    end

    // ---------------- error event pulses (registered) ----------------
    always @(posedge clk) begin
        if (reset) begin
            ev_coll <= 1'b0; ev_range <= 1'b0; ev_wpv <= 1'b0; ev_ovr <= 1'b0;
        end else begin
            ev_coll  <= (state == S_IDLE) && en && coll;
            ev_range <= (state == S_IDLE) && en && req && !coll && range_bad;
            ev_wpv   <= (state == S_IDLE) && en && !coll && !range_bad && wp_bad;
            ev_ovr   <= (state != S_IDLE) && req;
        end
    end

    // ---------------- Moore outputs ----------------
    assign busy      = (state != S_IDLE);
    assign ready     = (state == S_DONE) || (state == S_ERROR);
    assign error     = (state == S_ERROR);
    assign mem_we    = (state == S_WRITE);
    assign mem_re    = (state == S_READ);
    assign mem_addr  = addr_q;
    assign mem_wdata = wdata_q;
endmodule
