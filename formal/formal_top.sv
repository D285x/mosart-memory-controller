// End-to-end memory consistency property for mem_ctrl_top.
// One address (f_addr, chosen freely by the solver but constant) is tracked.
// Whenever the host has an accepted write to that address, the expected value
// is updated. Whenever an accepted read of that address completes, the data
// returned must equal the expected value. The accept decision is computed from a
// shadow of the programmed configuration built from the configuration port, so
// the property checks the wiring of the top level as well as the sub-blocks.
`default_nettype none
module formal_top #(
    parameter DATA_W = 4,
    parameter ADDR_W = 3
)(
    input wire clk
);
    localparam DEPTH = (1 << ADDR_W);

    (* anyseq *) wire                reset;
    (* anyseq *) wire                read_enable;
    (* anyseq *) wire                write_enable;
    (* anyseq *) wire [ADDR_W-1:0]   address;
    (* anyseq *) wire [DATA_W-1:0]   write_data;
    (* anyseq *) wire                cfg_we;
    (* anyseq *) wire [1:0]          cfg_addr;
    (* anyseq *) wire [7:0]          cfg_wdata;
    (* anyconst *) wire [ADDR_W-1:0] f_addr;

    wire [DATA_W-1:0] read_data;
    wire              ready, busy, error;
    wire [7:0]        cfg_rdata;

    mem_ctrl_top #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) dut (
        .clk(clk), .reset(reset),
        .read_enable(read_enable), .write_enable(write_enable),
        .address(address), .write_data(write_data), .read_data(read_data),
        .ready(ready), .busy(busy), .error(error),
        .cfg_we(cfg_we), .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata),
        .cfg_rdata(cfg_rdata)
    );

    // shadow of the programmed configuration (specification)
    reg            m_en = 1'b1, m_wp = 1'b0;
    reg [ADDR_W:0] m_limit = DEPTH;
    always @(posedge clk) begin
        if (reset) begin
            m_en <= 1'b1; m_wp <= 1'b0; m_limit <= DEPTH;
        end else if (cfg_we) begin
            if (cfg_addr == 2'd0) begin m_en <= cfg_wdata[0]; m_wp <= cfg_wdata[1]; end
            if (cfg_addr == 2'd2) m_limit <= (cfg_wdata[ADDR_W:0] > DEPTH) ? DEPTH : cfg_wdata[ADDR_W:0];
        end
    end

    reg f_past_valid = 1'b0;
    always @(posedge clk) f_past_valid <= 1'b1;
    always @(*) if (!f_past_valid) assume (reset);

    wire in_range = ({1'b0, address} < m_limit);
    wire acc_wr = !reset && !busy && m_en && write_enable && !read_enable && in_range && !m_wp;
    wire acc_rd = !reset && !busy && m_en && read_enable && !write_enable && in_range;

    reg [DATA_W-1:0] f_val   = {DATA_W{1'b0}};
    reg              f_known = 1'b0;
    reg              pend_rd = 1'b0;
    reg [ADDR_W-1:0] pend_a  = {ADDR_W{1'b0}};

    always @(posedge clk) begin
        if (acc_wr && address == f_addr) begin
            f_val <= write_data; f_known <= 1'b1;
        end
        if (reset)        pend_rd <= 1'b0;
        else if (acc_rd)  begin pend_rd <= 1'b1; pend_a <= address; end
        else if (ready)   pend_rd <= 1'b0;
    end

    wire chk = f_past_valid && ready && !error && pend_rd && pend_a == f_addr && f_known;

    always @(posedge clk) if (f_past_valid) begin
        if (chk) assert (read_data == f_val);
        // a read that was accepted always completes without error
        if (ready && pend_rd) assert (!error);
    end

    always @(posedge clk) if (f_past_valid && !reset) begin
        cover (chk);
    end
endmodule
