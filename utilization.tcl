set outdir "C:/MemCtrl/results/utilization"
file mkdir $outdir

set csv "$outdir/utilization_summary.csv"
set is_new [expr {![file exists $csv]}]
set fh [open $csv a]
if {$is_new} {
    puts $fh "design,slice_luts,slice_registers,slices,block_ram_tiles,dsps,wns_ns,total_power_w"
}

proc grab {txt pat} {
    if {[regexp $pat $txt -> v]} { return $v }
    return "n/a"
}

foreach dcp $argv {
    set name [file rootname [file tail $dcp]]
    puts "Processing $dcp"
    open_checkpoint $dcp

    report_utilization -file "$outdir/${name}_utilization.rpt"
    report_utilization -hierarchical -file "$outdir/${name}_utilization_hier.rpt"
    report_timing_summary -file "$outdir/${name}_timing.rpt"
    report_power -file "$outdir/${name}_power.rpt"

    set util [report_utilization -return_string]
    set pwr  [report_power -return_string]

    set luts  [grab $util {\|\s*Slice LUTs\*?\s*\|\s*(\d+)}]
    set regs  [grab $util {\|\s*Slice Registers\s*\|\s*(\d+)}]
    set slc   [grab $util {\|\s*Slice\s*\|\s*(\d+)}]
    set bram  [grab $util {\|\s*Block RAM Tile\s*\|\s*([\d.]+)}]
    set dsp   [grab $util {\|\s*DSPs\s*\|\s*(\d+)}]
    set power [grab $pwr  {Total On-Chip Power \(W\)\s*\|\s*([\d.]+)}]

    set wns "n/a"
    set paths [get_timing_paths -max_paths 1 -nworst 1 -setup]
    if {[llength $paths] > 0} { set wns [get_property SLACK [lindex $paths 0]] }

    puts $fh "$name,$luts,$regs,$slc,$bram,$dsp,$wns,$power"
    close_design
}

close $fh
puts "Wrote $csv"
