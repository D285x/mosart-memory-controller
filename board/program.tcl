## Program the EDGE board over JTAG.
## Usage (from the project root):  vivado -mode batch -source board/program.tcl -tclargs selftest|latency
## The device name below is for the XC7A35T board; change xc7a35t_0 for the 50T or 100T variants.
set variant [lindex $argv 0]
set root [file normalize [file join [file dirname [info script]] ..]]
open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a35t_0] 0]
current_hw_device $dev
set_property PROGRAM.FILE [file join $root build $variant $variant.bit] $dev
program_hw_devices $dev
close_hw_manager
