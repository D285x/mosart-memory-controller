//==============================================================================
// Testbench   : tb_axil_mem_ctrl
// Description : Self-checking testbench for the AXI4-Lite wrapper. Directed
//               tests for register access, responses (OKAY, SLVERR, DECERR),
//               latency versus wait states and back-pressure, followed by a
//               random test against a behavioural model.
//==============================================================================
`timescale 1ns / 1ps
module tb_axil_mem_ctrl;
    parameter DATA_W = 8;
    parameter ADDR_W = 4;
    parameter NRAND  = 2000;
    parameter SEED   = 7;
    localparam DEPTH = 1 << ADDR_W;
    localparam MEM = 12'h400;

    reg aclk = 0, aresetn = 0;
    always #10 aclk = ~aclk;

    reg  [11:0] awaddr = 0; reg awvalid = 0; wire awready;
    reg  [31:0] wdata = 0;  reg [3:0] wstrb = 4'hF; reg wvalid = 0; wire wready;
    wire [1:0]  bresp; wire bvalid; reg bready = 0;
    reg  [11:0] araddr = 0; reg arvalid = 0; wire arready;
    wire [31:0] rdata; wire [1:0] rresp; wire rvalid; reg rready = 0;

    axil_mem_ctrl #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready));

    integer errors = 0, checks = 0;
    integer lat;                       // cycles from request to response valid
    reg [31:0] mem_model [0:DEPTH-1];
    reg        m_en, m_wp;
    integer    m_wait, m_limit;
    integer seed;

    task check(input cond, input [255:0] what);
        begin
            checks = checks + 1;
            if (!cond) begin errors = errors + 1; $display("ERROR t=%0t %0s", $time, what); end
        end
    endtask

    task axi_write(input [11:0] a, input [31:0] d, input integer bdelay, output [1:0] resp);
        integer n;
        begin
            @(posedge aclk); #1; awaddr = a; wdata = d; awvalid = 1; wvalid = 1; lat = 0;
            @(posedge aclk);                       // ready is sampled at the edge
            while (!(awready && wready)) begin @(posedge aclk); lat = lat + 1; end
            #1; awvalid = 0; wvalid = 0; lat = lat + 1;
            while (!bvalid) begin @(posedge aclk); #1; lat = lat + 1; end
            for (n = 0; n < bdelay; n = n + 1) begin @(posedge aclk); #1; end
            bready = 1; resp = bresp;
            @(posedge aclk); #1; bready = 0;
        end
    endtask

    task axi_read(input [11:0] a, input integer rdelay, output [31:0] d, output [1:0] resp);
        integer n;
        begin
            @(posedge aclk); #1; araddr = a; arvalid = 1; lat = 0;
            @(posedge aclk);
            while (!arready) begin @(posedge aclk); lat = lat + 1; end
            #1; arvalid = 0; lat = lat + 1;
            while (!rvalid) begin @(posedge aclk); #1; lat = lat + 1; end
            for (n = 0; n < rdelay; n = n + 1) begin @(posedge aclk); #1; end
            rready = 1; d = rdata; resp = rresp;
            @(posedge aclk); #1; rready = 0;
        end
    endtask

    // model helpers
    function integer decode(input [11:0] a);   // 0 cfg, 1 mem, 2 bad
        begin
            if (a[11:4] == 8'h00 && a[1:0] == 2'b00) decode = 0;
            else if (a[11:10] == 2'b01 && a[9:ADDR_W+2] == 0 && a[1:0] == 2'b00) decode = 1;
            else decode = 2;
        end
    endfunction

    reg [1:0]  r;
    reg [31:0] d;
    integer i, n, k, lat0, a_i, op;
    reg [31:0] dmask;
    reg [1:0]  exp_resp;

    task set_cfg(input [11:0] a, input [31:0] v);
        reg [1:0] rr;
        begin axi_write(a, v, 0, rr); check(rr == 2'b00, "cfg write OKAY"); end
    endtask

    task model_cfg_write(input [11:0] a, input [31:0] v);
        begin
            case (a[3:2])
                2'd0: begin m_en = v[0]; m_wp = v[1]; end
                2'd1: m_wait = v[2:0];
                2'd2: m_limit = (v[ADDR_W:0] > DEPTH) ? DEPTH : v[ADDR_W:0];
                default: ;
            endcase
        end
    endtask

    task do_random;
        integer j;
        reg [11:0] ra; reg [31:0] rv; reg isw; integer dec, idx; reg [1:0] cw;
        begin
            for (j = 0; j < NRAND; j = j + 1) begin
                op = $random(seed) & 15;
                isw = ($random(seed) & 1);
                rv = $random(seed);
                // choose an address
                case (op)
                    0, 1: begin cw = $random(seed); ra = {8'h00, 2'b00, cw, 2'b00}; end  // config word (valid)
                    2:    ra = $random(seed);                                              // anything
                    3:    ra = MEM + 4 * (DEPTH + ($random(seed) & 3));                    // just past the end
                    default: ra = MEM + 4 * ($random(seed) & (DEPTH - 1));                // memory word
                endcase
                dec = decode(ra);
                idx = ra[ADDR_W+1:2];
                if (isw) begin
                    axi_write(ra, rv, $random(seed) & 3, r);
                    if (dec == 2) check(r == 2'b11, "rand write DECERR");
                    else if (dec == 0) begin check(r == 2'b00, "rand cfg write OKAY"); model_cfg_write(ra, rv); end
                    else begin
                        if (!m_en || idx >= m_limit || m_wp) check(r == 2'b10, "rand mem write SLVERR");
                        else begin check(r == 2'b00, "rand mem write OKAY"); mem_model[idx] = rv & dmask; end
                    end
                end else begin
                    axi_read(ra, $random(seed) & 3, d, r);
                    if (dec == 2) check(r == 2'b11 && d == 0, "rand read DECERR");
                    else if (dec == 0) begin
                        check(r == 2'b00, "rand cfg read OKAY");
                        case (ra[3:2])
                            2'd0: check(d == {30'd0, m_wp, m_en}, "rand cfg CTRL");
                            2'd1: check(d == m_wait, "rand cfg WAIT");
                            2'd2: check(d == m_limit, "rand cfg LIMIT");
                            default: ;
                        endcase
                    end else begin
                        if (!m_en || idx >= m_limit) check(r == 2'b10, "rand mem read SLVERR");
                        else begin check(r == 2'b00, "rand mem read OKAY"); check(d == mem_model[idx], "rand mem read data"); end
                    end
                end
                // clear sticky flags so STATUS never matters
                if ((j & 63) == 63) begin axi_write(12'h00C, 32'hF, 0, r); end
            end
        end
    endtask

    integer lat_base;
    initial begin
        seed = SEED;
        dmask = (DATA_W == 32) ? 32'hFFFFFFFF : ((32'd1 << DATA_W) - 1);
        for (i = 0; i < DEPTH; i = i + 1) mem_model[i] = 0;
        m_en = 1; m_wp = 0; m_wait = 0; m_limit = DEPTH;
        repeat (4) @(posedge aclk);
        #1 aresetn = 1;
        repeat (2) @(posedge aclk);

        // D1 reset values through the register window
        axi_read(12'h000, 0, d, r); check(d == 32'h1 && r == 0, "reset CTRL");
        axi_read(12'h004, 0, d, r); check(d == 0 && r == 0, "reset WAIT");
        axi_read(12'h008, 0, d, r); check(d == DEPTH && r == 0, "reset LIMIT");
        axi_read(12'h00C, 0, d, r); check(d == 0 && r == 0, "reset STATUS");

        // D2 write then read every word, wait states 0..7, latency constant offset + N
        lat_base = -1;
        for (n = 0; n < 8; n = n + 1) begin
            set_cfg(12'h004, n); m_wait = n;
            for (i = 0; i < DEPTH; i = i + 1) begin
                axi_write(MEM + 4 * i, (i * 37 + n * 11 + 5) & dmask, 0, r);
                check(r == 2'b00, "write OKAY");
                if (i == 0) begin
                    if (n == 0) lat_base = lat;
                    check(lat == lat_base + n, "write latency = base + N");
                end
                mem_model[i] = (i * 37 + n * 11 + 5) & dmask;
            end
            for (i = 0; i < DEPTH; i = i + 1) begin
                axi_read(MEM + 4 * i, 0, d, r);
                check(r == 2'b00, "read OKAY");
                check(d == mem_model[i], "read data");
                if (i == 0) check(lat == lat_base + n, "read latency = base + N");
            end
        end
        $display("AXI write/read response latency at N=0: %0d cycles (controller alone: 2 cycles)", lat_base);
        set_cfg(12'h004, 0); m_wait = 0;

        // D3 error responses
        axi_read(MEM + 4 * DEPTH, 0, d, r); check(r == 2'b11 && d == 0, "read past end DECERR");
        axi_write(MEM + 4 * DEPTH, 32'h1, 0, r); check(r == 2'b11, "write past end DECERR");
        axi_read(12'h010, 0, d, r); check(r == 2'b11, "unmapped cfg DECERR");
        axi_read(12'h800, 0, d, r); check(r == 2'b11, "high address DECERR");
        axi_read(12'h401, 0, d, r); check(r == 2'b11, "misaligned DECERR");
        axi_write(12'h002, 32'h1, 0, r); check(r == 2'b11, "misaligned cfg DECERR");

        // D4 limit: out-of-range request gives SLVERR and sets RANGE
        set_cfg(12'h008, DEPTH / 2); m_limit = DEPTH / 2;
        axi_read(MEM + 4 * (DEPTH - 1), 0, d, r); check(r == 2'b10 && d == 0, "range read SLVERR");
        axi_write(MEM + 4 * (DEPTH - 1), 32'h55, 0, r); check(r == 2'b10, "range write SLVERR");
        axi_read(12'h00C, 0, d, r); check((d & 32'h2) == 32'h2, "RANGE flag set");
        axi_write(12'h00C, 32'h2, 0, r);
        axi_read(12'h00C, 0, d, r); check((d & 32'h2) == 0, "RANGE flag cleared");
        axi_read(MEM + 4 * 1, 0, d, r); check(r == 2'b00 && d == mem_model[1], "in-range after limit");
        set_cfg(12'h008, 2 * DEPTH - 1); m_limit = DEPTH;
        axi_read(12'h008, 0, d, r); check(d == DEPTH, "limit saturates");

        // D5 write protect
        set_cfg(12'h000, 32'h3); m_wp = 1;
        axi_write(MEM + 4 * 2, 32'h99 & dmask, 0, r); check(r == 2'b10, "WP write SLVERR");
        axi_read(MEM + 4 * 2, 0, d, r); check(r == 2'b00 && d == mem_model[2], "WP leaves data");
        axi_read(12'h00C, 0, d, r); check((d & 32'h4) == 32'h4, "WPV flag set");
        axi_write(12'h00C, 32'hF, 0, r);

        // D6 disabled controller
        set_cfg(12'h000, 32'h0); m_en = 0; m_wp = 0;
        axi_write(MEM + 4 * 1, 32'h11, 0, r); check(r == 2'b10, "disabled write SLVERR");
        axi_read(MEM + 4 * 1, 0, d, r); check(r == 2'b10, "disabled read SLVERR");
        axi_read(12'h000, 0, d, r); check(d == 0 && r == 0, "CTRL readable while disabled");
        set_cfg(12'h000, 32'h1); m_en = 1;
        axi_read(MEM + 4 * 1, 0, d, r); check(r == 2'b00 && d == mem_model[1], "enabled again");

        // D7 back-pressure on B and R
        axi_write(MEM + 4 * (DEPTH - 2), 32'h2A & dmask, 7, r); check(r == 0, "slow bready"); mem_model[DEPTH - 2] = 32'h2A & dmask;
        axi_read(MEM + 4 * (DEPTH - 2), 9, d, r); check(r == 0 && d == mem_model[DEPTH - 2], "slow rready");

        // D8 read and write presented together: the write is served first
        @(posedge aclk); #1;
        awaddr = MEM + 4 * (DEPTH - 1); wdata = 32'h3C & dmask; awvalid = 1; wvalid = 1;
        araddr = MEM + 4 * (DEPTH - 1); arvalid = 1; bready = 1; rready = 1;
        @(posedge aclk);
        check(awready && wready && !arready, "write wins arbitration");
        #1; awvalid = 0; wvalid = 0; mem_model[DEPTH - 1] = 32'h3C & dmask;
        @(posedge aclk); while (!arready) @(posedge aclk);
        #1; arvalid = 0;
        @(posedge aclk); while (!rvalid) @(posedge aclk);
        check(rdata == (32'h3C & dmask) && rresp == 0, "read after simultaneous write sees new data");
        #1; bready = 0; rready = 0;

        // random
        do_random;

        $display("============================================================");
        $display(" CONFIG : DATA_W=%0d ADDR_W=%0d NRAND=%0d SEED=%0d", DATA_W, ADDR_W, NRAND, SEED);
        $display(" SUMMARY: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display(" RESULT : ALL TESTS PASSED"); else $display(" RESULT : FAILED");
        $display("============================================================");
        $finish;
    end

    initial begin #200000000; $display("TIMEOUT"); $display(" RESULT : FAILED"); $finish; end
endmodule
