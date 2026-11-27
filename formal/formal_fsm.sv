// Formal properties for mem_ctrl_fsm.
// Inputs are free (anyseq) so the solver explores every possible host and
// configuration behaviour. Properties are written in terms of the module ports
// and past input values, i.e. as a specification of the interface.
//   CONST_CFG = 1 holds the configuration constant (anyconst) so that the exact
//   access latency can be proven.
`default_nettype none
module formal_fsm #(
    parameter DATA_W    = 4,
    parameter ADDR_W    = 3,
    parameter CONST_CFG = 0
)(
    input wire clk
);
    localparam DEPTH = (1 << ADDR_W);

    (* anyseq *) wire                reset;
    (* anyseq *) wire                read_enable;
    (* anyseq *) wire                write_enable;
    (* anyseq *) wire [ADDR_W-1:0]   address;
    (* anyseq *) wire [DATA_W-1:0]   write_data;
    (* anyseq *) wire                en_s;
    (* anyseq *) wire                wp_s;
    (* anyseq *) wire [2:0]          ws_s;
    (* anyseq *) wire [ADDR_W:0]     lim_s;
    (* anyconst *) wire              en_k;
    (* anyconst *) wire              wp_k;
    (* anyconst *) wire [2:0]        ws_k;
    (* anyconst *) wire [ADDR_W:0]   lim_k;

    wire              en          = CONST_CFG ? en_k  : en_s;
    wire              wp          = CONST_CFG ? wp_k  : wp_s;
    wire [2:0]        wait_states = CONST_CFG ? ws_k  : ws_s;
    wire [ADDR_W:0]   addr_limit  = CONST_CFG ? lim_k : lim_s;

    wire              ready, busy, error, mem_we, mem_re;
    wire [ADDR_W-1:0] mem_addr;
    wire [DATA_W-1:0] mem_wdata;
    wire              ev_coll, ev_range, ev_wpv, ev_ovr;

    mem_ctrl_fsm #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) dut (
        .clk(clk), .reset(reset),
        .read_enable(read_enable), .write_enable(write_enable),
        .address(address), .write_data(write_data),
        .ready(ready), .busy(busy), .error(error),
        .en(en), .wp(wp), .wait_states(wait_states), .addr_limit(addr_limit),
        .mem_we(mem_we), .mem_re(mem_re),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .ev_coll(ev_coll), .ev_range(ev_range), .ev_wpv(ev_wpv), .ev_ovr(ev_ovr)
    );

    // ---------------- environment ----------------
    reg f_past_valid = 1'b0;
    always @(posedge clk) f_past_valid <= 1'b1;

    always @(*) begin
        if (!f_past_valid) assume (reset);        // start from reset
        assume (addr_limit <= DEPTH);             // guaranteed by cfg_regs
    end

    // ---------------- derived request attributes ----------------
    wire req       = read_enable | write_enable;
    wire coll      = read_enable & write_enable;
    wire range_bad = ({1'b0, address} >= addr_limit);
    wire wp_bad    = write_enable & wp;
    wire idle_now  = !reset && !busy;             // request would be sampled by the FSM

    wire acc_wr = idle_now && en && write_enable && !read_enable && !range_bad && !wp_bad;
    wire acc_rd = idle_now && en && read_enable  && !write_enable && !range_bad;
    wire rej    = idle_now && en && req && (coll || range_bad || wp_bad);

    reg [4:0] f_cnt = 5'd0;
    always @(posedge clk) f_cnt <= busy ? f_cnt + 5'd1 : 5'd0;

    // ---------------- properties ----------------
    always @(posedge clk) if (f_past_valid) begin
        // P1 to P4: output consistency
        assert (!(mem_we && mem_re));
        assert (!(mem_we || mem_re) || busy);
        assert (!(mem_we || mem_re) || (!ready && !error));
        assert (!error || ready);
        assert (!ready || busy);

        // P5: reset returns the controller to idle
        if ($past(reset)) assert (!busy && !ready && !error && !mem_we && !mem_re);

        // P6: the memory strobes occur exactly one cycle after an accepted request
        assert (mem_we == $past(acc_wr));
        assert (mem_re == $past(acc_rd));

        // P7: a request is rejected exactly when it is invalid
        assert (error == $past(rej));

        // P8: the accepted request is latched and held for the whole transaction
        if (mem_we || mem_re) begin
            assert (mem_addr  == $past(address));
            assert (mem_wdata == $past(write_data));
        end
        if ($past(busy) && busy && !$past(reset)) assert (mem_addr == $past(mem_addr));

        // P9: status event pulses
        assert (ev_coll  == $past(idle_now && en && coll));
        assert (ev_range == $past(idle_now && en && req && !coll && range_bad));
        assert (ev_wpv   == $past(idle_now && en && !coll && !range_bad && wp_bad));
        assert (ev_ovr   == $past(!reset && busy && req));
        // a rejected request raises exactly one of the three request events
        assert (error == (ev_coll || ev_range || ev_wpv));
        assert (!(ev_coll && ev_range) && !(ev_coll && ev_wpv) && !(ev_range && ev_wpv));

        // P10: bounded busy time (READ or WRITE, up to 7 wait states, DONE)
        assert (!busy || f_cnt <= 5'd8);
        // rejected requests finish after one cycle
        if (ready && error) assert (f_cnt == 5'd0);

        // P11: exact latency of an accepted access under a constant configuration
        if (CONST_CFG && ready && !error) assert (f_cnt == 5'd1 + {2'b00, wait_states});
    end

    // ---------------- cover: the interesting behaviours are reachable ----------------
    always @(posedge clk) if (f_past_valid && !reset) begin
        cover (ready && !error && f_cnt == 5'd1);                 // zero wait states
        cover (ready && !error && f_cnt == 5'd8);                 // seven wait states
        cover (mem_we);
        cover (mem_re);
        cover (ready && error && ev_coll);
        cover (ready && error && ev_range);
        cover (ready && error && ev_wpv);
        cover (ev_ovr);
    end
endmodule
