//============================================================================
// Module      : sync_mem
// Project     : MOSART Project 8 - Programmable Memory Controller
// Author      : Shaun Praneeth Raj
// Description : Single-port synchronous on-chip memory built from a register
//               array. Write is synchronous; read data is registered, so the
//               word addressed while mem_re is high appears on dout one clock
//               later and is held until the next read.
//============================================================================
`timescale 1ns / 1ps
module sync_mem #(
    parameter DATA_W = 8,
    parameter ADDR_W = 4
)(
    input  wire              clk,
    input  wire              mem_we,
    input  wire              mem_re,
    input  wire [ADDR_W-1:0] mem_addr,
    input  wire [DATA_W-1:0] mem_wdata,
    output reg  [DATA_W-1:0] mem_rdata
);
    localparam DEPTH = (1 << ADDR_W);

    reg [DATA_W-1:0] mem [0:DEPTH-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = {DATA_W{1'b0}};
        mem_rdata = {DATA_W{1'b0}};
    end

    always @(posedge clk) begin
        if (mem_we)
            mem[mem_addr] <= mem_wdata;
        if (mem_re)
            mem_rdata <= mem[mem_addr];
    end
endmodule
