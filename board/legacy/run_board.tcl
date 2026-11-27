## MOSART Project 8 - build bitstream for the EDGE Artix-7 board
## Usage (from this folder):  vivado -mode batch -source run_board.tcl
set part xc7a35tftg256-1
file mkdir out
read_verilog [glob ../rtl/*.v]
read_verilog edge_selftest_top.v
read_xdc edge_artix7.xdc
synth_design -top edge_selftest_top -part $part
opt_design
place_design
route_design
report_utilization    -file out/utilization.rpt
report_timing_summary -file out/timing_summary.rpt
report_drc            -file out/drc.rpt
report_power          -file out/power.rpt
report_timing         -max_paths 5 -file out/critical_paths.rpt
write_bitstream -force out/edge_selftest.bit
puts "Bitstream: [pwd]/out/edge_selftest.bit"
