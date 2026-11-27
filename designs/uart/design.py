"""Mutation-flow configuration for verilog-uart (Alex Forencich, MIT licence): uart_tx, uart_rx and the uart top."""
NAME = 'uart'
TOP = 'uart'
FILES = ['uart_tx.v', 'uart_rx.v', 'uart.v']
STK = ['s_axis_tready', 'txd', 'busy', 'm_axis_tvalid', 'overrun_error', 'frame_error']
FSM_STATES = None
FSM_ALTS = None
SIM_DEFINES = []
TB_V1 = ['tb/cov_uart.v', 'tb/tb_uart_v1.v']
TB_V2 = ['tb/cov_uart.v', 'tb/tb_uart_v2.v']
SIM_TIMEOUT = 40

FORMAL = [('formal/uart.sby', 'bmc', 240)]
FORMAL_DEEP = [('formal/uart.sby', 'deep', 600)]
FORMAL_FILES = ['formal/formal_uart.sv']

# equivalence: DATA_WIDTH 2 inside the miter; prescale fixed (a frame lasts 32 cycles at prescale 1,
# 64 at 2; depth 80 covers two received frames at prescale 1, needed for an overrun); a mutant
# counts as equivalent only if no difference is found in either run
PORT_MITER = 'equiv/port_miter.sv'
EQ_RUNS = [{'depth': 80, 'params': {'PRESCALE': 1}}, {'depth': 80, 'params': {'PRESCALE': 2}}]

TX_BIT = """                bit_cnt <= bit_cnt - 1;
                prescale_reg <= (prescale << 3)-1;
                {data_reg, txd_reg} <= {1'b0, data_reg};"""
RX_START_OK = """                if (!rxd_reg) begin
                    bit_cnt <= bit_cnt - 1;"""
RX_STOP_OK = """                if (rxd_reg) begin
                    m_axis_tdata_reg <= data_reg;"""

DIRECTED = [
 ('U01', 'uart_tx.v', TX_BIT, TX_BIT.replace('(prescale << 3)-1', '(prescale << 3)-2'), 'tx data bits one cycle short'),
 ('U02', 'uart_tx.v', "bit_cnt <= DATA_WIDTH+1;", "bit_cnt <= DATA_WIDTH;", 'tx sends one data bit too few'),
 ('U03', 'uart_tx.v', "prescale_reg <= (prescale << 3);", "prescale_reg <= (prescale << 2);", 'tx stop bit half length'),
 ('U04', 'uart_tx.v', "        txd_reg <= 1;\n        prescale_reg <= 0;", "        txd_reg <= 0;\n        prescale_reg <= 0;", 'txd low after reset'),
 ('U05', 'uart_tx.v', "s_axis_tready_reg <= !s_axis_tready_reg;", "s_axis_tready_reg <= 1;", 'tready left high when a byte is taken'),
 ('U06', 'uart_rx.v', "prescale_reg <= (prescale << 2)-2;", "prescale_reg <= (prescale << 1)-2;", 'rx samples a quarter bit early'),
 ('U07', 'uart_rx.v', "data_reg <= {rxd_reg, data_reg[DATA_WIDTH-1:1]};", "data_reg <= {data_reg[DATA_WIDTH-2:0], rxd_reg};", 'rx assembles bits MSB first'),
 ('U08', 'uart_rx.v', RX_START_OK, RX_START_OK.replace("if (!rxd_reg) begin", "if (1'b1) begin"), 'rx start bit not validated (no false-start rejection)'),
 ('U09', 'uart_rx.v', "frame_error_reg <= 1;", "frame_error_reg <= 1;\n                    m_axis_tvalid_reg <= 1;", 'byte with a bad stop bit is delivered'),
 ('U10', 'uart_rx.v', RX_STOP_OK, RX_STOP_OK.replace("if (rxd_reg) begin", "if (1'b1) begin"), 'rx stop bit not checked'),
 ('U11', 'uart_rx.v', "bit_cnt <= DATA_WIDTH+2;", "bit_cnt <= DATA_WIDTH+1;", 'rx receives one data bit too few'),
 ('U12', 'uart_rx.v', "overrun_error_reg <= m_axis_tvalid_reg;", "overrun_error_reg <= 1;", 'overrun flagged on every received byte'),
 ('U13', 'uart.v', ".m_axis_tready(m_axis_tready),", ".m_axis_tready(1'b1),", 'receiver tready tied high at the top level'),
]

# specification miter: compares only what the specification defines (m_axis_tdata only while
# m_axis_tvalid is high), prescale 1, one received frame lasts 32 cycles, depth 80 covers two
SPEC_MITER = 'equiv/spec_miter.sv'
SPEC_MITER_PU = 'equiv/spec_miter_powerup.sv'
SPEC_DEPTH = 80

# survivors that the tools report as distinguishable but that meet the specification, with the
# argument (not tool-checked; listed separately in the results)
ARGUED = {
 'G008': 'reset no longer clears s_axis_tready: the only difference is s_axis_tready high while reset is '
         'applied or in the first cycle after it, when the transmitter is idle; AXI-Stream allows tready in '
         'any cycle and no transfer takes place during reset',
 'G030': 'the stop bit ends after exactly one bit period (8 x prescale cycles) instead of one bit period plus '
         'one cycle; both meet the 8N1 framing, only the idle time before the next frame differs by one cycle',
}
