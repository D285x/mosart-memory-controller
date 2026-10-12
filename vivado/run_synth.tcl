## MOSART Project 8 - Vivado non-project synthesis flow
## Usage (from this folder):  vivado -mode batch -source run_synth.tcl
set part xc7a35tcpg236-1
file mkdir reports
read_verilog [glob ../rtl/*.v]
read_xdc mem_ctrl.xdc
synth_design -top mem_ctrl_top -part $part
report_utilization     -file reports/utilization.rpt
report_utilization     -hierarchical -file reports/utilization_hier.rpt
report_timing_summary  -file reports/timing_summary.rpt
report_timing -max_paths 5 -file reports/critical_paths.rpt
write_checkpoint -force reports/mem_ctrl_synth.dcp
puts "Reports written to [pwd]/reports"
