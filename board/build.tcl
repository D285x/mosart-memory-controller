## Build a bitstream for the EDGE Artix-7 board.
## Usage (from the project root):
##   vivado -mode batch -source board/build.tcl -tclargs selftest
##   vivado -mode batch -source board/build.tcl -tclargs latency
## Output: build/<variant>/<variant>.bit and the reports next to it.
set part xc7a35tftg256-1
set variant [lindex $argv 0]
set root [file normalize [file join [file dirname [info script]] ..]]

switch -- $variant {
    selftest {
        set top edge_selftest_top
        set srcs [list [file join $root board edge_selftest_top.v]]
        set xdc  [file join $root board edge_selftest.xdc]
    }
    latency {
        set top edge_latency_top
        set srcs [list [file join $root board seg7_driver.v] [file join $root board edge_latency_top.v]]
        set xdc  [file join $root board edge_latency.xdc]
    }
    default { error "variant must be selftest or latency" }
}

set out [file join $root build $variant]
file mkdir $out
read_verilog [glob [file join $root rtl *.v]]
read_verilog $srcs
read_xdc $xdc
synth_design -top $top -part $part
opt_design
place_design
route_design
report_utilization              -file [file join $out utilization.rpt]
report_utilization -hierarchical -file [file join $out utilization_hier.rpt]
report_timing_summary           -file [file join $out timing_summary.rpt]
report_timing -max_paths 5      -file [file join $out critical_paths.rpt]
report_power                    -file [file join $out power.rpt]
report_drc                      -file [file join $out drc.rpt]
write_bitstream -force [file join $out $variant.bit]
puts "Bitstream: [file join $out $variant.bit]"
