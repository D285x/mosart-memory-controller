## One design point of the parameter and clock sweep.
## Usage: vivado -mode batch -source point.tcl -tclargs <tag> <DATA_W> <ADDR_W> <period_ns> <synth|impl> [place_directive]
## Appends one row to results/sweep/sweep_data.csv
##   tag    : label written to the CSV ("cfg" for the configuration sweep, "clk" for the clock sweep)
##   impl   : full place and route, post-route numbers (area, WNS, power)
##   synth  : synthesis only, post-synthesis area
## Timing is the internal register-to-register timing of the controller:
## the design is synthesised out of context (no I/O pins), and paths from inputs
## and to outputs are excluded.
set part xc7a35tftg256-1

set tag    [lindex $argv 0]
set dw     [lindex $argv 1]
set aw     [lindex $argv 2]
set period [lindex $argv 3]
set mode   [lindex $argv 4]
set dir    [expr {[llength $argv] > 5 ? [lindex $argv 5] : "Default"}]

set root [file normalize [file join [file dirname [info script]] ..]]
set outdir [file join $root results sweep]
file mkdir $outdir
set csv [file join $outdir sweep_data.csv]

proc grab {rpt label} {
    # first numeric column of a utilization table row whose first cell is $label
    if {[regexp "\\|\\s*${label}\\s*\\|\\s*(\[0-9.\]+)\\s*\\|" $rpt -> v]} { return $v }
    return NA
}

read_verilog [glob [file join $root rtl *.v]]
synth_design -top mem_ctrl_top -part $part -mode out_of_context \
    -generic DATA_W=$dw -generic ADDR_W=$aw

create_clock -name clk -period $period [get_ports clk]
set_false_path -from [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_false_path -to   [get_ports -filter {DIRECTION == OUT}]

set wns NA
set fmax NA
set ptot NA
set pdyn NA
set pstat NA

if {$mode eq "impl"} {
    opt_design
    place_design -directive $dir
    route_design
    set wns [get_property SLACK [get_timing_paths -setup -max_paths 1]]
    if {$wns ne "" && $wns ne "NA"} {
        set fmax [format %.1f [expr {1000.0 / ($period - $wns)}]]
        set wns  [format %.3f $wns]
    } else { set wns NA }
    set prpt [report_power -return_string]
    if {[regexp {Total On-Chip Power \(W\)\s*\|\s*([0-9.]+)} $prpt -> v]} { set ptot  $v }
    if {[regexp {\| Dynamic \(W\)\s*\|\s*([0-9.]+)} $prpt -> v]}          { set pdyn  $v }
    if {[regexp {Device Static \(W\)\s*\|\s*([0-9.]+)} $prpt -> v]}        { set pstat $v }
}

set urpt [report_utilization -return_string]
set luts   [grab $urpt {Slice LUTs\*?}]
set lutlog [grab $urpt {LUT as Logic}]
set lutmem [grab $urpt {LUT as Memory}]
set ffs    [grab $urpt {Slice Registers}]
set bram   [grab $urpt {Block RAM Tile}]

set depth [expr {1 << $aw}]
set bits  [expr {$depth * $dw}]
set new [expr {![file exists $csv]}]
set fh [open $csv a]
if {$new} {
    puts $fh "tag,mode,data_w,addr_w,words,mem_bits,period_ns,luts,lut_logic,lut_mem,ffs,bram,wns_ns,fmax_est_mhz,power_total_w,power_dynamic_w,power_static_w,directive"
}
puts $fh [join [list $tag $mode $dw $aw $depth $bits $period $luts $lutlog $lutmem $ffs $bram $wns $fmax $ptot $pdyn $pstat $dir] ,]
close $fh
puts "POINT DONE: $tag $mode dir=$dir DATA_W=$dw ADDR_W=$aw period=$period LUTs=$luts FFs=$ffs WNS=$wns Fmax_est=$fmax"
