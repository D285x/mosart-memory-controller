"""Mutation-flow configuration for sfifo (wb2axip, public domain), OPT_ASYNC_READ = 0."""
NAME = 'sfifo'
TOP = 'sfifo'
FILES = ['sfifo.v']
STK = ['o_full', 'o_empty']           # single-bit outputs driven by a continuous assign
FSM_STATES = None                      # no next_state FSM in this design
FSM_ALTS = None
SIM_DEFINES = []
TB_V1 = ['tb/cov_sfifo.v', 'tb/tb_sfifo_v1.v']
TB_V2 = ['tb/cov_sfifo.v', 'tb/tb_sfifo_v2.v']
SIM_TIMEOUT = 40

# formal: (sby file, task, timeout s); the second list runs only on mutants still alive
FORMAL = [('formal/sfifo.sby', 'bmc', 240)]
FORMAL_DEEP = []
FORMAL_FILES = ['formal/formal_sfifo.sv']

# bounded equivalence: port-level miter (reduced widths inside the miter), depth, miter parameters
PORT_MITER = 'equiv/port_miter.sv'
EQ_RUNS = [{'depth': 24}]

# hand-written semantic mutants, written from the specification before any mutant was run
DIRECTED = [
 ('F01', 'sfifo.v', "\tassign\tr_full = o_fill[LGFLEN];", "\tassign\tr_full = (o_fill >= FLEN-1);", 'full flag one entry early'),
 ('F02', 'sfifo.v', "\twire\tw_wr = (i_wr && !o_full);", "\twire\tw_wr = i_wr;", 'write accepted when full'),
 ('F03', 'sfifo.v', "\twire\tw_rd = (i_rd && !o_empty);", "\twire\tw_rd = i_rd;", 'read accepted when empty'),
 ('F04', 'sfifo.v', "\telse case({ w_wr, w_rd })", "\telse case({ i_wr, w_rd })", 'fill counts rejected writes'),
 ('F05', 'sfifo.v', "\t2'b01: r_empty <= (o_fill <= 1);", "\t2'b01: r_empty <= (o_fill <= 2);", 'empty flag set one entry early'),
 ('F06', 'sfifo.v', "\t\t\telse if (r_empty || (i_rd && (o_fill == 1)))", "\t\t\telse if (r_empty)", 'no bypass when the last entry is read during a write'),
 ('F07', 'sfifo.v', "\t\t\trd_next = rd_addr[LGFLEN-1:0] + 1;", "\t\t\trd_next = rd_addr[LGFLEN-1:0];", 'read-ahead address not advanced'),
 ('F08', 'sfifo.v', "\t\tmem[wr_addr[(LGFLEN-1):0]] <= i_data;", "\t\tmem[rd_addr[(LGFLEN-1):0]] <= i_data;", 'memory written at the read address'),
 ('F09', 'sfifo.v', "\t\tif (r_empty || i_rd)\n\t\t\tbypass_data <= i_data;", "\t\t\tbypass_data <= i_data;", 'bypass register loaded every cycle'),
 ('F10', 'sfifo.v', "\telse if (w_wr)\n\t\twr_addr", "\telse if (i_wr)\n\t\twr_addr", 'write pointer advances on a rejected write'),
 ('F11', 'sfifo.v', "\t\tif (w_rd)\n\t\t\trd_data", "\t\tif (i_rd)\n\t\t\trd_data", 'read register advances on a rejected read'),
 ('F12', 'sfifo.v', "\tif (w_wr)\n\t\tmem[", "\tif (i_wr)\n\t\tmem[", 'memory written on a rejected write'),
]

# specification miter: compares only what the specification defines (o_data only while not empty)
SPEC_MITER = 'equiv/spec_miter.sv'
SPEC_MITER_PU = 'equiv/spec_miter_powerup.sv'
SPEC_DEPTH = 24
