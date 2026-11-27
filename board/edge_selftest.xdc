## Programmable memory controller: EDGE Artix-7 board constraints for edge_selftest_top
## Pins and voltages taken from the EDGE master XDC rev 2.1 (schematic ARTIX7_V3).

## Configuration bank voltage
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## 50 MHz clock (oscillator Y2)
set_property -dict {PACKAGE_PIN N11 IOSTANDARD LVCMOS33} [get_ports CLK]
create_clock -name sys_clk_pin -period 20.000 -waveform {0.000 10.000} [get_ports CLK]

## Slide switches: MODE = sw[0] (SW3, rightmost), RST = sw[1] (SW4). Up = 1.
## RST is active high: leave SW4 down to run, flip it up and back down to restart.
set_property -dict {PACKAGE_PIN L5 IOSTANDARD LVCMOS33} [get_ports MODE]
set_property -dict {PACKAGE_PIN L4 IOSTANDARD LVCMOS33} [get_ports RST]

## LEDs (1 = on): D3 = PASS, D4 = FAIL, D5 = DONE, D6 = heartbeat
set_property -dict {PACKAGE_PIN J3 IOSTANDARD LVCMOS33} [get_ports {SERIAL_OUT[0]}]
set_property -dict {PACKAGE_PIN H3 IOSTANDARD LVCMOS33} [get_ports {SERIAL_OUT[1]}]
set_property -dict {PACKAGE_PIN J1 IOSTANDARD LVCMOS33} [get_ports {SERIAL_OUT[2]}]
set_property -dict {PACKAGE_PIN K1 IOSTANDARD LVCMOS33} [get_ports {SERIAL_OUT[3]}]

## Switches are asynchronous human inputs (two-flop synchronised in RTL)
set_false_path -from [get_ports {RST MODE}]
set_false_path -to   [get_ports {SERIAL_OUT[*]}]
