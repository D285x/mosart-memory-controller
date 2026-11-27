// Formal properties for cfg_regs.
// A shadow model of the specification (register map in cfg_regs.v) is kept in
// this wrapper and compared with the design on every cycle.
`default_nettype none
module formal_cfg #(
    parameter ADDR_W = 3
)(
    input wire clk
);
    localparam DEPTH = (1 << ADDR_W);

    (* anyseq *) wire        reset;
    (* anyseq *) wire        cfg_we;
    (* anyseq *) wire [1:0]  cfg_addr;
    (* anyseq *) wire [7:0]  cfg_wdata;
    (* anyseq *) wire        ev_coll, ev_range, ev_wpv, ev_ovr, busy;

    wire [7:0]      cfg_rdata;
    wire            en, wp;
    wire [2:0]      wait_states;
    wire [ADDR_W:0] addr_limit;

    cfg_regs #(.ADDR_W(ADDR_W)) dut (
        .clk(clk), .reset(reset),
        .cfg_we(cfg_we), .cfg_addr(cfg_addr), .cfg_wdata(cfg_wdata),
        .cfg_rdata(cfg_rdata),
        .en(en), .wp(wp), .wait_states(wait_states), .addr_limit(addr_limit),
        .ev_coll(ev_coll), .ev_range(ev_range), .ev_wpv(ev_wpv), .ev_ovr(ev_ovr),
        .busy(busy)
    );

    // ---------------- shadow model of the specification ----------------
    reg       m_en = 1'b1, m_wp = 1'b0;
    reg [2:0] m_ws = 3'd0;
    reg [ADDR_W:0] m_limit = DEPTH;
    reg [3:0] m_sticky = 4'b0000;

    wire [ADDR_W:0] wr_limit = (cfg_wdata[ADDR_W:0] > DEPTH) ? DEPTH : cfg_wdata[ADDR_W:0];
    wire [3:0] clr = (cfg_we && cfg_addr == 2'd3) ? cfg_wdata[3:0] : 4'b0;
    wire [3:0] set = {ev_ovr, ev_wpv, ev_range, ev_coll};

    always @(posedge clk) begin
        if (reset) begin
            m_en <= 1'b1; m_wp <= 1'b0; m_ws <= 3'd0; m_limit <= DEPTH; m_sticky <= 4'b0;
        end else begin
            if (cfg_we && cfg_addr == 2'd0) begin m_en <= cfg_wdata[0]; m_wp <= cfg_wdata[1]; end
            if (cfg_we && cfg_addr == 2'd1) m_ws <= cfg_wdata[2:0];
            if (cfg_we && cfg_addr == 2'd2) m_limit <= wr_limit;
            m_sticky <= (m_sticky & ~clr) | set;       // a new event wins over a clear
        end
    end

    reg f_past_valid = 1'b0;
    always @(posedge clk) f_past_valid <= 1'b1;
    always @(*) if (!f_past_valid) assume (reset);

    // ---------------- properties ----------------
    always @(posedge clk) if (f_past_valid) begin
        // registers follow the specification
        assert (en == m_en);
        assert (wp == m_wp);
        assert (wait_states == m_ws);
        assert (addr_limit == m_limit);
        assert (addr_limit <= DEPTH);

        // read-back follows the specification for every register address
        case (cfg_addr)
            2'd0: assert (cfg_rdata == {6'b0, m_wp, m_en});
            2'd1: assert (cfg_rdata == {5'b0, m_ws});
            2'd2: assert (cfg_rdata == {{(7-ADDR_W){1'b0}}, m_limit});
            2'd3: assert (cfg_rdata == {3'b0, busy, m_sticky});
        endcase

        // reset values
        if ($past(reset)) begin
            assert (en && !wp && wait_states == 3'd0 && addr_limit == DEPTH);
            assert (m_sticky == 4'b0);
        end

        // a write to one register does not disturb another
        if (!$past(reset) && $past(cfg_we) && $past(cfg_addr) != 2'd0)
            assert (en == $past(en) && wp == $past(wp));
        if (!$past(reset) && $past(cfg_we) && $past(cfg_addr) != 2'd1)
            assert (wait_states == $past(wait_states));
        if (!$past(reset) && $past(cfg_we) && $past(cfg_addr) != 2'd2)
            assert (addr_limit == $past(addr_limit));
        if (!$past(reset) && !$past(cfg_we))
            assert (en == $past(en) && wp == $past(wp) &&
                    wait_states == $past(wait_states) && addr_limit == $past(addr_limit));

        // an event is never lost: it is visible in the sticky register next cycle
        if (!$past(reset) && $past(ev_coll))  assert (m_sticky[0]);
        if (!$past(reset) && $past(ev_range)) assert (m_sticky[1]);
        if (!$past(reset) && $past(ev_wpv))   assert (m_sticky[2]);
        if (!$past(reset) && $past(ev_ovr))   assert (m_sticky[3]);
    end

    always @(posedge clk) if (f_past_valid && !reset) begin
        cover (cfg_we && cfg_addr == 2'd2 && cfg_wdata[ADDR_W:0] > DEPTH);   // saturation
        cover (cfg_we && cfg_addr == 2'd3 && (cfg_wdata[3:0] & m_sticky) != 4'b0); // W1C of a set bit
        cover (ev_coll && cfg_we && cfg_addr == 2'd3 && cfg_wdata[0]);        // event and clear together
    end
endmodule
