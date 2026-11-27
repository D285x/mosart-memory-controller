"""Cross-check only: the memory controller in the generic flow, used to compare the yices-based
equivalence backend of flow.py with the yosys sat results of mutate.py on the same mutants."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'mutation'))
import mutlib
NAME = 'memctrl_xcheck'
TOP = 'mem_ctrl_top'
FILES = mutlib.FILES
STK = ['busy', 'ready', 'error', 'mem_we', 'mem_re']
FSM_STATES = ['S_IDLE', 'S_READ', 'S_WRITE', 'S_WAIT', 'S_DONE', 'S_ERROR']
FSM_ALTS = ('S_IDLE', 'S_ERROR', 'S_DONE')
DIRECTED = mutlib.DIRECTED
PORT_MITER = 'equiv/port_miter.sv'
EQ_RUNS = [{'depth': 24}]
RTL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'rtl')
