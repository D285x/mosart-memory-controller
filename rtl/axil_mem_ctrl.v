//==============================================================================
// Module      : axil_mem_ctrl
// Project     : MOSART Project 8 - Programmable Memory Controller
// Author      : Shaun Praneeth Raj (24EG104B27)
// Description : AXI4-Lite slave wrapper around mem_ctrl_top. One outstanding
//               transaction at a time (writes take priority when both channels
//               present a request in the same cycle).
//
// Address map (12-bit byte address, 32-bit words)
//   0x000  CTRL    bit0 EN, bit1 WP                 (configuration space)
//   0x004  WAIT    bits[2:0] wait states
//   0x008  LIMIT   address limit
//   0x00C  STATUS  {BUSY, OVR, WPV, RANGE, COLL}, write 1 to clear
//   0x400 + 4*i    memory word i, i < 2**ADDR_W
//
// Responses
//   OKAY   (2'b00) access completed
//   SLVERR (2'b10) controller rejected the request (collision, out of range,
//                  write protected) or is disabled (EN = 0)
//   DECERR (2'b11) address outside the map above
// Byte strobes (WSTRB) are ignored: every write updates the full word.
//==============================================================================
`default_nettype none
module axil_mem_ctrl #(
    parameter DATA_W = 8,
    parameter ADDR_W = 4
)(
    input  wire        aclk,
    input  wire        aresetn,
    // write address
    input  wire [11:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    // write data
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    // write response
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    // read address
    input  wire [11:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    // read data
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready
);
    localparam [2:0] IDLE = 3'd0, CFG = 3'd1, ISSUE = 3'd2, WAITRDY = 3'd3, RESP = 3'd4;

    reg [2:0]  st;
    reg        is_wr;
    reg [11:0] addr_q;
    reg [31:0] wdata_q;

    wire reset = ~aresetn;

    wire aw_ok  = s_axi_awvalid & s_axi_wvalid;
    wire take_w = (st == IDLE) & aw_ok;
    wire take_r = (st == IDLE) & s_axi_arvalid & ~aw_ok;
    assign s_axi_awready = take_w;
    assign s_axi_wready  = take_w;
    assign s_axi_arready = take_r;

    // controller connections
    reg              rd_en, wr_en, cfg_we;
    wire [DATA_W-1:0] read_data;
    wire             ready, busy, error;
    wire [7:0]       cfg_rdata;

    mem_ctrl_top #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_ctrl (
        .clk(aclk), .reset(reset),
        .read_enable(rd_en), .write_enable(wr_en),
        .address(addr_q[ADDR_W+1:2]), .write_data(wdata_q[DATA_W-1:0]),
        .read_data(read_data), .ready(ready), .busy(busy), .error(error),
        .cfg_we(cfg_we), .cfg_addr(addr_q[3:2]), .cfg_wdata(wdata_q[7:0]),
        .cfg_rdata(cfg_rdata)
    );

    reg first;   // first cycle after the request was presented

    always @(*) begin
        rd_en  = (st == ISSUE) && !is_wr;
        wr_en  = (st == ISSUE) &&  is_wr;
        cfg_we = (st == CFG)   &&  is_wr;
    end

    always @(posedge aclk) begin
        if (reset) begin
            st <= IDLE; is_wr <= 1'b0; addr_q <= 12'd0; wdata_q <= 32'd0; first <= 1'b0;
            s_axi_bvalid <= 1'b0; s_axi_bresp <= 2'b00;
            s_axi_rvalid <= 1'b0; s_axi_rresp <= 2'b00; s_axi_rdata <= 32'd0;
        end else begin
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;

            case (st)
            IDLE: begin
                if (take_w) begin
                    is_wr <= 1'b1; addr_q <= s_axi_awaddr; wdata_q <= s_axi_wdata; st <= RESP; first <= 1'b0;
                    // decode on the incoming address (addr_q not yet valid)
                    if (s_axi_awaddr[11:4] == 8'h00 && s_axi_awaddr[1:0] == 2'b00) st <= CFG;
                    else if (s_axi_awaddr[11:10] == 2'b01 && (s_axi_awaddr[9:ADDR_W+2] == 0) && s_axi_awaddr[1:0] == 2'b00) st <= ISSUE;
                    else begin st <= RESP; s_axi_bresp <= 2'b11; end
                end else if (take_r) begin
                    is_wr <= 1'b0; addr_q <= s_axi_araddr; first <= 1'b0;
                    if (s_axi_araddr[11:4] == 8'h00 && s_axi_araddr[1:0] == 2'b00) st <= CFG;
                    else if (s_axi_araddr[11:10] == 2'b01 && (s_axi_araddr[9:ADDR_W+2] == 0) && s_axi_araddr[1:0] == 2'b00) st <= ISSUE;
                    else begin st <= RESP; s_axi_rresp <= 2'b11; s_axi_rdata <= 32'd0; end
                end
            end
            CFG: begin
                // write: cfg_we is high this cycle. read: cfg_rdata is valid this cycle.
                st <= RESP;
                if (is_wr) s_axi_bresp <= 2'b00;
                else begin s_axi_rresp <= 2'b00; s_axi_rdata <= {24'd0, cfg_rdata}; end
            end
            ISSUE: begin
                st <= WAITRDY; first <= 1'b1;
            end
            WAITRDY: begin
                first <= 1'b0;
                if (first && !busy) begin
                    // controller ignored the request: disabled
                    st <= RESP;
                    if (is_wr) s_axi_bresp <= 2'b10; else begin s_axi_rresp <= 2'b10; s_axi_rdata <= 32'd0; end
                end else if (ready) begin
                    st <= RESP;
                    if (is_wr) s_axi_bresp <= error ? 2'b10 : 2'b00;
                    else begin
                        s_axi_rresp <= error ? 2'b10 : 2'b00;
                        s_axi_rdata <= error ? 32'd0 : {{(32-DATA_W){1'b0}}, read_data};
                    end
                end
            end
            RESP: begin
                // wait until the previous response slot is free, then publish
                if (is_wr) begin
                    if (!s_axi_bvalid || s_axi_bready) begin s_axi_bvalid <= 1'b1; st <= IDLE; end
                end else begin
                    if (!s_axi_rvalid || s_axi_rready) begin s_axi_rvalid <= 1'b1; st <= IDLE; end
                end
            end
            default: st <= IDLE;
            endcase
        end
    end
endmodule
