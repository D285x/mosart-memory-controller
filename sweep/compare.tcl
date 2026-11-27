## Wrapper overhead and vendor baseline: one design point per call.
## Usage: vivado -mode batch -source compare.tcl -tclargs <design> <DATA_W> <ADDR_W> <period_ns>
##   design : core      mem_ctrl_top (bare controller)
##            axil      axil_mem_ctrl (AXI4-Lite wrapper around mem_ctrl_top)
##            bramctrl  Xilinx AXI BRAM Controller IP in AXI4-Lite mode (controller only,
##                      the block RAM itself is outside the IP and is not counted)
## Out-of-context, post-route, Default directives, register-to-register timing.
## Appends one row to results/compare/compare_data.csv
set part xc7a35tftg256-1

set design [lindex $argv 0]
set dw     [lindex $argv 1]
set aw     [lindex $argv 2]
set period [lindex $argv 3]

set root   [file normalize [file join [file dirname [info script]] ..]]
set outdir [file join $root results compare]
file mkdir $outdir
set csv [file join $outdir compare_data.csv]

proc grab {rpt label} {
    if {[regexp "\\|\\s*${label}\\s*\\|\\s*(\[0-9.\]+)\\s*\\|" $rpt -> v]} { return $v }
    return NA
}

set status ok
set note ""

if {$design eq "core" || $design eq "axil"} {
    set top [expr {$design eq "core" ? "mem_ctrl_top" : "axil_mem_ctrl"}]
    set clkport [expr {$design eq "core" ? "clk" : "aclk"}]
    read_verilog [glob [file join $root rtl *.v]]
    synth_design -top $top -part $part -mode out_of_context \
        -generic DATA_W=$dw -generic ADDR_W=$aw
} elseif {$design eq "bramctrl"} {
    set clkport s_axi_aclk
    create_project -in_memory -part $part
    set ipdir [file join $outdir ip_bramctrl]
    file delete -force $ipdir
    file mkdir $ipdir
    create_ip -name axi_bram_ctrl -vendor xilinx.com -library ip \
        -module_name axi_bram_ctrl_0 -dir $ipdir
    set ip [get_ips axi_bram_ctrl_0]
    foreach {k v} [list PROTOCOL AXI4LITE SINGLE_PORT_BRAM 1 DATA_WIDTH 32 ECC_TYPE 0] {
        if {[catch {set_property CONFIG.$k $v $ip} err]} {
            puts "NOTE: could not set CONFIG.$k = $v ($err)"
            append note "$k not set; "
        }
    }
    foreach k {PROTOCOL SINGLE_PORT_BRAM DATA_WIDTH MEM_DEPTH ECC_TYPE} {
        catch {puts "IP CONFIG.$k = [get_property CONFIG.$k $ip]"}
    }
    catch {set aw [expr {int(log([get_property CONFIG.MEM_DEPTH $ip]) / log(2))}]}
    set xci [get_files axi_bram_ctrl_0.xci]
    set_property GENERATE_SYNTH_CHECKPOINT false $xci
    generate_target all $xci
    synth_design -top axi_bram_ctrl_0 -part $part -mode out_of_context
} else {
    puts "ERROR: unknown design $design"
    exit 1
}

create_clock -name clk -period $period [get_ports $clkport]
set_false_path -from [get_ports -filter "DIRECTION == IN && NAME != $clkport"]
set_false_path -to   [get_ports -filter {DIRECTION == OUT}]

opt_design
place_design
route_design

set wns [get_property SLACK [get_timing_paths -setup -max_paths 1]]
set fmax NA
if {$wns ne ""} {
    set fmax [format %.1f [expr {1000.0 / ($period - $wns)}]]
    set wns  [format %.3f $wns]
} else { set wns NA }

set prpt [report_power -return_string]
set ptot NA; set pdyn NA
regexp {Total On-Chip Power \(W\)\s*\|\s*([0-9.]+)} $prpt -> ptot
regexp {\| Dynamic \(W\)\s*\|\s*([0-9.]+)} $prpt -> pdyn

set urpt [report_utilization -return_string]
set luts   [grab $urpt {Slice LUTs\*?}]
set lutlog [grab $urpt {LUT as Logic}]
set lutmem [grab $urpt {LUT as Memory}]
set ffs    [grab $urpt {Slice Registers}]
set bram   [grab $urpt {Block RAM Tile}]

set rptdir [file join $outdir reports]
file mkdir $rptdir
set base "${design}_${dw}_${aw}_${period}"
report_utilization -hierarchical -file [file join $rptdir ${base}_util_hier.rpt]
report_timing -max_paths 1 -file [file join $rptdir ${base}_critical_path.rpt]

set new [expr {![file exists $csv]}]
set fh [open $csv a]
if {$new} {
    puts $fh "design,data_w,addr_w,period_ns,luts,lut_logic,lut_mem,ffs,bram,wns_ns,fmax_est_mhz,power_total_w,power_dynamic_w,status,note"
}
puts $fh [join [list $design $dw $aw $period $luts $lutlog $lutmem $ffs $bram $wns $fmax $ptot $pdyn $status [string trim $note]] ,]
close $fh
puts "COMPARE DONE: $design DATA_W=$dw ADDR_W=$aw period=$period LUTs=$luts (logic $lutlog, mem $lutmem) FFs=$ffs BRAM=$bram WNS=$wns Fmax_est=$fmax"
