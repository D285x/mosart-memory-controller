## MOSART Project 8 - Vivado simulator (xsim) batch run
## Usage (from this folder):  vivado -mode batch -source run_sim.tcl
exec xvlog ../rtl/sync_mem.v ../rtl/cfg_regs.v ../rtl/mem_ctrl_fsm.v ../rtl/mem_ctrl_top.v ../tb/tb_mem_ctrl.v
exec xelab -debug typical tb_mem_ctrl -s tb_sim
puts [exec xsim tb_sim -runall]
