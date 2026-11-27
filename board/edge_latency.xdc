## EDGE Artix-7 constraints for edge_latency_top (xc7a35tftg256-1)
## Pins copied from the EDGE master XDC rev 2.1 (schematic ARTIX7_V3)
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property -dict { PACKAGE_PIN N11 IOSTANDARD LVCMOS33 } [get_ports { CLK }];
create_clock -period 20.000 -name sys_clk_pin -waveform {0.000 10.000} [get_ports { CLK }];
set_property -dict { PACKAGE_PIN L5  IOSTANDARD LVCMOS33 } [get_ports { sw[0] }];  # SW3  (LSB)
set_property -dict { PACKAGE_PIN L4  IOSTANDARD LVCMOS33 } [get_ports { sw[1] }];  # SW4
set_property -dict { PACKAGE_PIN M4  IOSTANDARD LVCMOS33 } [get_ports { sw[2] }];  # SW5
set_property -dict { PACKAGE_PIN M2  IOSTANDARD LVCMOS33 } [get_ports { sw[3] }];  # SW6
set_property -dict { PACKAGE_PIN M1  IOSTANDARD LVCMOS33 } [get_ports { sw[4] }];  # SW7
set_property -dict { PACKAGE_PIN N3  IOSTANDARD LVCMOS33 } [get_ports { sw[5] }];  # SW8
set_property -dict { PACKAGE_PIN N2  IOSTANDARD LVCMOS33 } [get_ports { sw[6] }];  # SW9
set_property -dict { PACKAGE_PIN N1  IOSTANDARD LVCMOS33 } [get_ports { sw[7] }];  # SW10
set_property -dict { PACKAGE_PIN P1  IOSTANDARD LVCMOS33 } [get_ports { sw[8] }];  # SW11
set_property -dict { PACKAGE_PIN P4  IOSTANDARD LVCMOS33 } [get_ports { sw[9] }];  # SW12
set_property -dict { PACKAGE_PIN T8  IOSTANDARD LVCMOS33 } [get_ports { sw[10] }]; # SW13
set_property -dict { PACKAGE_PIN R8  IOSTANDARD LVCMOS33 } [get_ports { sw[11] }]; # SW15
set_property -dict { PACKAGE_PIN N6  IOSTANDARD LVCMOS33 } [get_ports { sw[12] }]; # SW17
set_property -dict { PACKAGE_PIN T7  IOSTANDARD LVCMOS33 } [get_ports { sw[13] }]; # SW14
set_property -dict { PACKAGE_PIN P8  IOSTANDARD LVCMOS33 } [get_ports { sw[14] }]; # SW16
set_property -dict { PACKAGE_PIN M6  IOSTANDARD LVCMOS33 } [get_ports { sw[15] }]; # SW18 (MSB)
set_property -dict { PACKAGE_PIN J3  IOSTANDARD LVCMOS33 } [get_ports { led[0] }];  # D3  (LSB)
set_property -dict { PACKAGE_PIN H3  IOSTANDARD LVCMOS33 } [get_ports { led[1] }];  # D4
set_property -dict { PACKAGE_PIN J1  IOSTANDARD LVCMOS33 } [get_ports { led[2] }];  # D5
set_property -dict { PACKAGE_PIN K1  IOSTANDARD LVCMOS33 } [get_ports { led[3] }];  # D6
set_property -dict { PACKAGE_PIN L3  IOSTANDARD LVCMOS33 } [get_ports { led[4] }];  # D8
set_property -dict { PACKAGE_PIN L2  IOSTANDARD LVCMOS33 } [get_ports { led[5] }];  # D9
set_property -dict { PACKAGE_PIN K3  IOSTANDARD LVCMOS33 } [get_ports { led[6] }];  # D10
set_property -dict { PACKAGE_PIN K2  IOSTANDARD LVCMOS33 } [get_ports { led[7] }];  # D11
set_property -dict { PACKAGE_PIN K5  IOSTANDARD LVCMOS33 } [get_ports { led[8] }];  # D12
set_property -dict { PACKAGE_PIN P6  IOSTANDARD LVCMOS33 } [get_ports { led[9] }];  # D13
set_property -dict { PACKAGE_PIN R7  IOSTANDARD LVCMOS33 } [get_ports { led[10] }]; # D14
set_property -dict { PACKAGE_PIN R6  IOSTANDARD LVCMOS33 } [get_ports { led[11] }]; # D15
set_property -dict { PACKAGE_PIN T5  IOSTANDARD LVCMOS33 } [get_ports { led[12] }]; # D16
set_property -dict { PACKAGE_PIN R5  IOSTANDARD LVCMOS33 } [get_ports { led[13] }]; # D17
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { led[14] }]; # D18
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { led[15] }]; # D19 (MSB)
set_property -dict { PACKAGE_PIN K13 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { pb[0] }]; # SW21 top
set_property -dict { PACKAGE_PIN L14 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { pb[1] }]; # SW23 bottom
set_property -dict { PACKAGE_PIN M12 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { pb[2] }]; # SW19 left
set_property -dict { PACKAGE_PIN L13 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { pb[3] }]; # SW20 right
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { pb[4] }]; # SW22 centre (CPU reset in MicroBlaze designs)
set_property -dict { PACKAGE_PIN F2  IOSTANDARD LVCMOS33 } [get_ports { digit[0] }]; # DISP1 (left)
set_property -dict { PACKAGE_PIN E1  IOSTANDARD LVCMOS33 } [get_ports { digit[1] }]; # DISP2
set_property -dict { PACKAGE_PIN G5  IOSTANDARD LVCMOS33 } [get_ports { digit[2] }]; # DISP3
set_property -dict { PACKAGE_PIN G4  IOSTANDARD LVCMOS33 } [get_ports { digit[3] }]; # DISP4 (right)
set_property -dict { PACKAGE_PIN G2  IOSTANDARD LVCMOS33 } [get_ports { Seven_Seg[0] }]; # A  (= SDRAM A5)
set_property -dict { PACKAGE_PIN G1  IOSTANDARD LVCMOS33 } [get_ports { Seven_Seg[1] }]; # B  (= SDRAM A6)
set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports { Seven_Seg[2] }]; # C  (= SDRAM A12)
set_property -dict { PACKAGE_PIN H4  IOSTANDARD LVCMOS33 } [get_ports { Seven_Seg[3] }]; # D  (= SDRAM A11)
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports { Seven_Seg[4] }]; # E  (= SDRAM A8)
set_property -dict { PACKAGE_PIN J4  IOSTANDARD LVCMOS33 } [get_ports { Seven_Seg[5] }]; # F  (= SDRAM A10)
set_property -dict { PACKAGE_PIN H2  IOSTANDARD LVCMOS33 } [get_ports { Seven_Seg[6] }]; # G  (= SDRAM A9)
set_property -dict { PACKAGE_PIN H1  IOSTANDARD LVCMOS33 } [get_ports { Seven_Seg[7] }]; # DP (= SDRAM A7)

## Human inputs are synchronised in RTL; outputs are not timing critical
set_false_path -from [get_ports {sw[*] pb[*]}]
set_false_path -to   [get_ports {led[*] digit[*] Seven_Seg[*]}]
