# Hardware Results

MOSART Project 8: Programmable 8-bit Memory Controller on the EDGE Artix-7 board
Shaun Praneeth Raj (24EG104B27)
Run date: 2026-11-20 (build about 12:10 IST, board programmed 12:12:42 IST)

This file holds every piece of data collected for the hardware run: the summary tables, the setup, the board mapping, the test description, the results, the problems met and how they were fixed, and, in the appendices, the complete raw reports and logs, unedited.

---

## 1. Outcome in one line

The memory controller, wrapped in a self-test, was built for the EDGE Artix-7 (xc7a35tftg256-1), programmed over JTAG, and ran correctly on the board. The self-test finished with PASS and DONE lit, FAIL off, and the heartbeat blinking. Both xsim simulations pass.

## 2. Target and tools

| Item | Value |
|---|---|
| Board | EDGE Artix 7 FPGA Development Board (Invent Logics / allaboutfpga.com), master XDC rev 2.1, schematic ARTIX7_V3 |
| FPGA part | XC7A35T-1FTG256C, Vivado part xc7a35tftg256-1 |
| Board clock | 50 MHz oscillator Y2, pin N11 |
| I/O standard | LVCMOS33 (config bank 3.3 V, CFGBVS VCCO) |
| Tools | Vivado / xsim 2025.2, installed at C:\Xilinx\2025.2\Vivado |
| Programming | JTAG through Vivado hardware manager, device xc7a35t_0, hw_server on localhost:3121 |
| Bitstream | board\out\edge_selftest.bit, 2,192,141 bytes |
| Top module | edge_selftest_top (wrapper) around the unmodified mem_ctrl_top |
| Project folder | C:\Vivado Projects\P8_MemCtrl |

## 3. Design under test

Programmable memory controller: 16 x 8 register-array memory, 6-state Moore FSM (IDLE, READ, WRITE, WAIT, DONE, ERROR), single clock domain, synchronous active-high reset.

Configuration registers (2-bit address):

| Addr | Name | Bits | Meaning |
|---|---|---|---|
| 0x0 | CTRL | [0] EN (reset 1), [1] WP (reset 0) | enable, write protect |
| 0x1 | WAIT | [2:0] | wait states per access (0 to 7) |
| 0x2 | LIMIT | [4:0] (reset 16) | number of valid words, address < LIMIT |
| 0x3 | STATUS | [0] COLL, [1] RANGE, [2] WPV, [3] OVR (all W1C sticky), [4] BUSY (RO) | error flags |

Timing behaviour (from the FSM): an access takes 3 cycles with 0 wait states (IDLE, READ or WRITE, DONE) and 3 + N cycles with N wait states. Request-to-ready latency is 2 cycles + N.

Derived throughput at 50 MHz: 16.7 M accesses/s with N = 0 (16.7 MB/s on the 8-bit bus); 8.3 M accesses/s with N = 3.

## 4. Board wrapper and pin mapping

The controller has 27 inputs and 19 outputs, more than the board can use directly, so a wrapper (board\edge_selftest_top.v) drives it from an internal self-test sequencer and shows the verdict on four LEDs. RST and MODE pass through two-flop synchronisers.

| Port | Pin | Board item | Function |
|---|---|---|---|
| CLK | N11 | 50 MHz oscillator Y2 | clock (period 20 ns) |
| MODE | L5 | slide switch SW3 (sw[0], rightmost) | 0 = 0 wait states, 1 = 3 wait states (sampled at start) |
| RST | L4 | slide switch SW4 (sw[1]) | active high; keep down to run, flip up and down to restart |
| SERIAL_OUT[0] | J3 | LED D3 | PASS (steady on) |
| SERIAL_OUT[1] | H3 | LED D4 | FAIL (sticky) |
| SERIAL_OUT[2] | J1 | LED D5 | DONE |
| SERIAL_OUT[3] | K1 | LED D6 | heartbeat, about 1 Hz |

Timing constraints: create_clock -period 20.000 on CLK; false paths from RST and MODE and to SERIAL_OUT.

## 5. On-board self-test sequence

Starts automatically after reset:
1. Program the WAIT register (MODE = 0 gives 0, MODE = 1 gives 3).
2. Write all 16 words with the pattern ({i, ~i} XOR 0x5A) and check no error is raised.
3. Read all 16 words back and compare.
4. Set LIMIT = 8, read address 9. Expect an error and STATUS.RANGE set.
5. Clear status, restore LIMIT = 16.
6. Set WP = 1, write address 0. Expect an error and STATUS.WPV set.
7. Clear status, WP = 0, read address 0. It must still hold the original value (the rejected write must not change memory).

## 6. Results

### 6.1 On the board

| Check | Result |
|---|---|
| Bitstream programmed | Success, "End of startup status: HIGH", Vivado exited 12:12:42 |
| LEDs after programming | D3 (PASS) on, D5 (DONE) on, D4 (FAIL) off, D6 (heartbeat) blinking, FPGA DONE LED on (photo: evidence\board_leds_photo.png) |
| User verdict | "It works." |
| MODE = 1 (3 wait states) | Tested on the board at 12:26 IST: SW3 up, SW4 flipped up and down. User confirmed the pass result (D3 and D5 on, D4 off, D6 blinking). Reported by the user; no separate photo. |

### 6.2 Simulation in Vivado xsim (2025.2)

| Testbench | Result |
|---|---|
| tb_mem_ctrl (original, core only) | 2,749 checks, 0 errors, 288 writes, 288 reads, 4 rejected. RESULT: ALL TESTS PASSED |
| tb_edge_selftest (board wrapper) | RESULT: ALL TESTS PASSED |

### 6.3 Earlier simulation in Icarus Verilog (before the hardware run)

| Testbench | Result |
|---|---|
| tb_mem_ctrl (original, Icarus log in sim\sim_log.txt) | 3,356 checks, 0 errors, 281 writes, 295 reads, 4 rejected, 10 test groups including 500 constrained-random accesses |
| tb_edge_selftest (wrapper, cloud run) | ok: MODE=0 done, MODE=0 pass, MODE=1 done, MODE=1 pass, injected read fault detected (FAIL asserted), heartbeat toggles, reset clears done, re-run after reset passes. RESULT: ALL TESTS PASSED |

The check counts differ between simulators (3,356 versus 2,749) because the random-access test draws different numbers in each simulator. The xsim figure is the one reproduced in Vivado.

### 6.4 Post-route utilization (wrapper plus controller, xc7a35t)

| Resource | Used | Available | Utilization |
|---|---|---|---|
| Slice LUTs | 103 | 20,800 | 0.50% |
| LUT as Logic | 95 | 20,800 | 0.46% |
| LUT as Memory | 8 | 9,600 | 0.08% |
| Slice Registers | 114 | 41,600 | 0.27% |
| Block RAM tiles | 0 | 50 | 0.00% |
| Bonded IOB | 7 | 170 | 4.12% |

Earlier Yosys synth_xilinx pre-check of the core alone (no wrapper): about 162 cells including 21 LUT2, 11 LUT3, 4 LUT4, 4 LUT5, 19 LUT6 (59 LUTs), 44 flip-flops (42 FDRE, 2 FDSE), 1 RAM32M, 1 CARRY4, 10 MUXF7/F8. The wrapper adds the sequencer, 32-bit heartbeat counter and synchronisers, which is why the Vivado figure is larger. Full detail is in the appendices.

### 6.5 Timing at 50 MHz (20 ns period)

| Metric | Value |
|---|---|
| WNS | +15.325 ns |
| TNS | 0 ns |
| Estimated Fmax | about 213.9 MHz, from 1 / (20 - WNS). This is an estimate; the critical path probably lies in the wrapper (counters), not the controller. A tighter-clock run would confirm it. |

### 6.6 Power (Vivado estimate)

| Metric | Value |
|---|---|
| Total on-chip | 0.075 W |
| Dynamic | 0.003 W |
| Device static | 0.072 W |

Dynamic power is a vectorless estimate, so treat it as approximate.

## 7. Problems met and how they were fixed

| # | Problem | Cause | Fix |
|---|---|---|---|
| 1 | First constraints used LVCMOS18 | Taken from earlier pin notes; the board master XDC specifies LVCMOS33 | Rewrote edge_artix7.xdc from the master XDC (LVCMOS33, CFGBVS VCCO, 3.3 V). LED polarity confirmed active high. |
| 2 | run_all.bat said "Vivado not found" | Vivado is installed at C:\Xilinx\2025.2\Vivado\bin; the script searched C:\Xilinx\Vivado\<version> | Search extended to C:\Xilinx\<version>\Vivado\bin (and D:\ and AMD folders) |
| 3 | Simulations reported "not found" in summary.txt | xelab rejected the design: rtl files have no timescale while the testbenches do (error XSIM 43-4099 on mem_ctrl_top, cfg_regs, mem_ctrl_fsm, sync_mem) | Added -timescale 1ns/1ps to both xelab calls; added a "sim" argument to run only the simulations |
| 4 | VidSynth was running on the board | Same board is used for the VidSynth HDMI project | The memory-controller bitstream replaced it on programming (volatile, nothing lost). VidSynth is restored by reloading its own .bit file. |

Note on summary.txt: it was generated in the full run before fix 3, so its simulation lines read "(not found)". The valid simulation results are in 6.2, taken from the sim logs after the fix.

## 8. Files produced (project folder C:\Vivado Projects\P8_MemCtrl)

| File | Purpose |
|---|---|
| run_all.bat | simulate, build, collect statistics, optionally program (run_all.bat sim = simulations only) |
| board\edge_selftest_top.v | board wrapper with self-test sequencer |
| board\tb_edge_selftest.v | wrapper testbench |
| board\edge_artix7.xdc | board constraints |
| board\run_board.tcl | non-project build flow to bitstream |
| board\program_board.tcl | JTAG programming |
| board\make_stats.ps1 | statistics collector |
| board\out\ | bitstream, reports, logs, summary.txt, evidence photos |

## 9. Evidence files (board\out\evidence)

- board_leds_photo.png: the board after programming, LEDs showing the pass state
- programming_terminal.png: Vivado programming output ending "End of startup status: HIGH"
- simulation_pass_terminal.png: run_all.bat sim showing core testbench PASS and board wrapper PASS

## 10. Figures suitable for a CV or report

- Verification: 2,749 xsim checks, 0 errors (3,356 in Icarus), plus an on-board self-test covering write/read-back of 16 words, range error, write-protect violation and the rejected-write-leaves-memory-unchanged check
- Implementation: 103 LUTs (0.50%), 114 FFs, 0 BRAM on xc7a35t at 50 MHz, WNS +15.3 ns, estimated 0.075 W
- Throughput: 16.7 M accesses/s (0 wait states), 8.3 M accesses/s (3 wait states) at 50 MHz
- Caveats to state honestly: area includes the self-test wrapper; Fmax is an estimate; dynamic power is vectorless; the board test is pass/fail by LED, not a speed measurement

---

# Appendices: complete raw data (unedited)


---

## A. summary.txt (generated by make_stats.ps1, simulation lines stale, see section 7)

```text
MOSART P8 memory controller - EDGE Artix-7 (xc7a35tftg256-1) run summary
Generated: 2026-11-20 12:10

== Simulation ==
Core testbench : (not found)
                 (not found)
Board wrapper  : (not found)

== Utilization (post-route) ==
| Slice LUTs                 |  103 |     0 |          0 |     20800 |  0.50 |
| LUT as Logic                               |   95 |     0 |          0 |     20800 |  0.46 |
| LUT as Memory                              |    8 |     0 |          0 |      9600 |  0.08 |
| Slice Registers            |  114 |     0 |          0 |     41600 |  0.27 |
| Block RAM Tile |    0 |     0 |          0 |        50 |  0.00 |
| Bonded IOB                  |    7 |     7 |          0 |       170 |  4.12 |

== Timing (50 MHz, 20 ns) ==
WNS = 15.325 ns, TNS = 0 ns
Estimated Fmax = 213.9 MHz (1 / (20 - WNS); an estimate, tighten the clock to confirm)

== Power ==
| Total On-Chip Power (W)  | 0.075        |
| Dynamic (W)              | 0.003        |
| Device Static (W)        | 0.072        |

== Derived from the design ==
Access time: 3 cycles + N wait states; request-to-ready latency 2 cycles + N
At 50 MHz: 16.7 M accesses/s with N=0, 8.3 M accesses/s with N=3
```


---

## B. Utilization report (utilization.rpt)

```text
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
| Date         : Fri Nov 20 12:10:32 2026
| Host         : DESKTOP-U2MVLKN running 64-bit major release  (build 9200)
| Command      : report_utilization -file out/utilization.rpt
| Design       : edge_selftest_top
| Device       : xc7a35tftg256-1
| Speed File   : -1
| Design State : Routed
---------------------------------------------------------------------------------------------------------------------------------------------

Utilization Design Information

Table of Contents
-----------------
1. Slice Logic
1.1 Summary of Registers by Type
2. Slice Logic Distribution
3. Memory
4. DSP
5. IO and GT Specific
6. Clocking
7. Specific Feature
8. Primitives
9. Black Boxes
10. Instantiated Netlists

1. Slice Logic
--------------

+----------------------------+------+-------+------------+-----------+-------+
|          Site Type         | Used | Fixed | Prohibited | Available | Util% |
+----------------------------+------+-------+------------+-----------+-------+
| Slice LUTs                 |  103 |     0 |          0 |     20800 |  0.50 |
|   LUT as Logic             |   95 |     0 |          0 |     20800 |  0.46 |
|   LUT as Memory            |    8 |     0 |          0 |      9600 |  0.08 |
|     LUT as Distributed RAM |    8 |     0 |            |           |       |
|     LUT as Shift Register  |    0 |     0 |            |           |       |
| Slice Registers            |  114 |     0 |          0 |     41600 |  0.27 |
|   Register as Flip Flop    |  114 |     0 |          0 |     41600 |  0.27 |
|   Register as Latch        |    0 |     0 |          0 |     41600 |  0.00 |
| F7 Muxes                   |    0 |     0 |          0 |     16300 |  0.00 |
| F8 Muxes                   |    0 |     0 |          0 |      8150 |  0.00 |
| Unique Control Sets        |   15 |       |          0 |      8150 |  0.18 |
+----------------------------+------+-------+------------+-----------+-------+
* Warning! LUT value is adjusted to account for LUT combining.
** Note: Available Control Sets calculated as Slice * 1, Review the Control Sets Report for more information regarding control sets.


1.1 Summary of Registers by Type
--------------------------------

+-------+--------------+-------------+--------------+
| Total | Clock Enable | Synchronous | Asynchronous |
+-------+--------------+-------------+--------------+
| 0     |            _ |           - |            - |
| 0     |            _ |           - |          Set |
| 0     |            _ |           - |        Reset |
| 0     |            _ |         Set |            - |
| 0     |            _ |       Reset |            - |
| 0     |          Yes |           - |            - |
| 0     |          Yes |           - |          Set |
| 0     |          Yes |           - |        Reset |
| 3     |          Yes |         Set |            - |
| 111   |          Yes |       Reset |            - |
+-------+--------------+-------------+--------------+


2. Slice Logic Distribution
---------------------------

+--------------------------------------------+------+-------+------------+-----------+-------+
|                  Site Type                 | Used | Fixed | Prohibited | Available | Util% |
+--------------------------------------------+------+-------+------------+-----------+-------+
| Slice                                      |   48 |     0 |          0 |      8150 |  0.59 |
|   SLICEL                                   |   38 |     0 |            |           |       |
|   SLICEM                                   |   10 |     0 |            |           |       |
| LUT as Logic                               |   95 |     0 |          0 |     20800 |  0.46 |
|   using O5 output only                     |    0 |       |            |           |       |
|   using O6 output only                     |   71 |       |            |           |       |
|   using O5 and O6                          |   24 |       |            |           |       |
| LUT as Memory                              |    8 |     0 |          0 |      9600 |  0.08 |
|   LUT as Distributed RAM                   |    8 |     0 |            |           |       |
|     using O5 output only                   |    0 |       |            |           |       |
|     using O6 output only                   |    8 |       |            |           |       |
|     using O5 and O6                        |    0 |       |            |           |       |
|   LUT as Shift Register                    |    0 |     0 |            |           |       |
|     using O5 output only                   |    0 |       |            |           |       |
|     using O6 output only                   |    0 |       |            |           |       |
|     using O5 and O6                        |    0 |       |            |           |       |
| Slice Registers                            |  114 |     0 |          0 |     41600 |  0.27 |
|   Register driven from within the Slice    |   96 |       |            |           |       |
|   Register driven from outside the Slice   |   18 |       |            |           |       |
|     LUT in front of the register is unused |    4 |       |            |           |       |
|     LUT in front of the register is used   |   14 |       |            |           |       |
+--------------------------------------------+------+-------+------------+-----------+-------+


3. Memory
---------

+----------------+------+-------+------------+-----------+-------+
|    Site Type   | Used | Fixed | Prohibited | Available | Util% |
+----------------+------+-------+------------+-----------+-------+
| Block RAM Tile |    0 |     0 |          0 |        50 |  0.00 |
|   RAMB36/FIFO* |    0 |     0 |          0 |        50 |  0.00 |
|   RAMB18       |    0 |     0 |          0 |       100 |  0.00 |
+----------------+------+-------+------------+-----------+-------+
* Note: Each Block RAM Tile only has one FIFO logic available and therefore can accommodate only one FIFO36E1 or one FIFO18E1. However, if a FIFO18E1 occupies a Block RAM Tile, that tile can still accommodate a RAMB18E1


4. DSP
------

+-----------+------+-------+------------+-----------+-------+
| Site Type | Used | Fixed | Prohibited | Available | Util% |
+-----------+------+-------+------------+-----------+-------+
| DSPs      |    0 |     0 |          0 |        90 |  0.00 |
+-----------+------+-------+------------+-----------+-------+


5. IO and GT Specific
---------------------

+-----------------------------+------+-------+------------+-----------+-------+
|          Site Type          | Used | Fixed | Prohibited | Available | Util% |
+-----------------------------+------+-------+------------+-----------+-------+
| Bonded IOB                  |    7 |     7 |          0 |       170 |  4.12 |
|   IOB Master Pads           |    4 |       |            |           |       |
|   IOB Slave Pads            |    2 |       |            |           |       |
| Bonded IPADs                |    0 |     0 |          0 |         2 |  0.00 |
| PHY_CONTROL                 |    0 |     0 |          0 |         5 |  0.00 |
| PHASER_REF                  |    0 |     0 |          0 |         5 |  0.00 |
| OUT_FIFO                    |    0 |     0 |          0 |        20 |  0.00 |
| IN_FIFO                     |    0 |     0 |          0 |        20 |  0.00 |
| IDELAYCTRL                  |    0 |     0 |          0 |         5 |  0.00 |
| IBUFDS                      |    0 |     0 |          0 |       163 |  0.00 |
| PHASER_OUT/PHASER_OUT_PHY   |    0 |     0 |          0 |        20 |  0.00 |
| PHASER_IN/PHASER_IN_PHY     |    0 |     0 |          0 |        20 |  0.00 |
| IDELAYE2/IDELAYE2_FINEDELAY |    0 |     0 |          0 |       250 |  0.00 |
| ILOGIC                      |    0 |     0 |          0 |       170 |  0.00 |
| OLOGIC                      |    0 |     0 |          0 |       170 |  0.00 |
+-----------------------------+------+-------+------------+-----------+-------+


6. Clocking
-----------

+------------+------+-------+------------+-----------+-------+
|  Site Type | Used | Fixed | Prohibited | Available | Util% |
+------------+------+-------+------------+-----------+-------+
| BUFGCTRL   |    1 |     0 |          0 |        32 |  3.13 |
| BUFIO      |    0 |     0 |          0 |        20 |  0.00 |
| MMCME2_ADV |    0 |     0 |          0 |         5 |  0.00 |
| PLLE2_ADV  |    0 |     0 |          0 |         5 |  0.00 |
| BUFMRCE    |    0 |     0 |          0 |        10 |  0.00 |
| BUFHCE     |    0 |     0 |          0 |        72 |  0.00 |
| BUFR       |    0 |     0 |          0 |        20 |  0.00 |
+------------+------+-------+------------+-----------+-------+


7. Specific Feature
-------------------

+-------------+------+-------+------------+-----------+-------+
|  Site Type  | Used | Fixed | Prohibited | Available | Util% |
+-------------+------+-------+------------+-----------+-------+
| BSCANE2     |    0 |     0 |          0 |         4 |  0.00 |
| CAPTUREE2   |    0 |     0 |          0 |         1 |  0.00 |
| DNA_PORT    |    0 |     0 |          0 |         1 |  0.00 |
| EFUSE_USR   |    0 |     0 |          0 |         1 |  0.00 |
| FRAME_ECCE2 |    0 |     0 |          0 |         1 |  0.00 |
| ICAPE2      |    0 |     0 |          0 |         2 |  0.00 |
| PCIE_2_1    |    0 |     0 |          0 |         1 |  0.00 |
| STARTUPE2   |    0 |     0 |          0 |         1 |  0.00 |
| XADC        |    0 |     0 |          0 |         1 |  0.00 |
+-------------+------+-------+------------+-----------+-------+


8. Primitives
-------------

+----------+------+---------------------+
| Ref Name | Used | Functional Category |
+----------+------+---------------------+
| FDRE     |  111 |        Flop & Latch |
| LUT6     |   46 |                 LUT |
| LUT2     |   26 |                 LUT |
| LUT5     |   24 |                 LUT |
| LUT4     |   12 |                 LUT |
| LUT3     |   10 |                 LUT |
| RAMS32   |    8 |  Distributed Memory |
| CARRY4   |    8 |          CarryLogic |
| OBUF     |    4 |                  IO |
| IBUF     |    3 |                  IO |
| FDSE     |    3 |        Flop & Latch |
| LUT1     |    1 |                 LUT |
| BUFG     |    1 |               Clock |
+----------+------+---------------------+


9. Black Boxes
--------------

+----------+------+
| Ref Name | Used |
+----------+------+


10. Instantiated Netlists
-------------------------

+----------+------+
| Ref Name | Used |
+----------+------+
```


---

## C. Timing summary (timing_summary.rpt)

```text
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
| Date         : Fri Nov 20 12:10:32 2026
| Host         : DESKTOP-U2MVLKN running 64-bit major release  (build 9200)
| Command      : report_timing_summary -file out/timing_summary.rpt
| Design       : edge_selftest_top
| Device       : 7a35t-ftg256
| Speed File   : -1  PRODUCTION 1.23 2018-06-13
| Design State : Routed
---------------------------------------------------------------------------------------------------------------------------------------------

Timing Summary Report

------------------------------------------------------------------------------------------------
| Timer Settings
| --------------
------------------------------------------------------------------------------------------------

  Enable Multi Corner Analysis               :  Yes
  Enable Pessimism Removal                   :  Yes
  Pessimism Removal Resolution               :  Nearest Common Node
  Enable Input Delay Default Clock           :  No
  Enable Preset / Clear Arcs                 :  No
  Disable Flight Delays                      :  No
  Ignore I/O Paths                           :  No
  Timing Early Launch at Borrowing Latches   :  No
  Borrow Time for Max Delay Exceptions       :  Yes
  Merge Timing Exceptions                    :  Yes
  Inter-SLR Compensation                     :  Conservative

  Corner  Analyze    Analyze    
  Name    Max Paths  Min Paths  
  ------  ---------  ---------  
  Slow    Yes        Yes        
  Fast    Yes        Yes        


------------------------------------------------------------------------------------------------
| Report Methodology
| ------------------
------------------------------------------------------------------------------------------------

No report available as report_methodology has not been run prior. Run report_methodology on the current design for the summary of methodology violations.



check_timing report

Table of Contents
-----------------
1. checking no_clock (0)
2. checking constant_clock (0)
3. checking pulse_width_clock (0)
4. checking unconstrained_internal_endpoints (0)
5. checking no_input_delay (2)
6. checking no_output_delay (4)
7. checking multiple_clock (0)
8. checking generated_clocks (0)
9. checking loops (0)
10. checking partial_input_delay (0)
11. checking partial_output_delay (0)
12. checking latch_loops (0)

1. checking no_clock (0)
------------------------
 There are 0 register/latch pins with no clock.


2. checking constant_clock (0)
------------------------------
 There are 0 register/latch pins with constant_clock.


3. checking pulse_width_clock (0)
---------------------------------
 There are 0 register/latch pins which need pulse_width check


4. checking unconstrained_internal_endpoints (0)
------------------------------------------------
 There are 0 pins that are not constrained for maximum delay.

 There are 0 pins that are not constrained for maximum delay due to constant clock.


5. checking no_input_delay (2)
------------------------------
 There are 0 input ports with no input delay specified.

 There are 2 input ports with no input delay but user has a false path constraint. (MEDIUM)


6. checking no_output_delay (4)
-------------------------------
 There are 0 ports with no output delay specified.

 There are 4 ports with no output delay but user has a false path constraint (MEDIUM)

 There are 0 ports with no output delay but with a timing clock defined on it or propagating through it


7. checking multiple_clock (0)
------------------------------
 There are 0 register/latch pins with multiple clocks.


8. checking generated_clocks (0)
--------------------------------
 There are 0 generated clocks that are not connected to a clock source.


9. checking loops (0)
---------------------
 There are 0 combinational loops in the design.


10. checking partial_input_delay (0)
------------------------------------
 There are 0 input ports with partial input delay specified.


11. checking partial_output_delay (0)
-------------------------------------
 There are 0 ports with partial output delay specified.


12. checking latch_loops (0)
----------------------------
 There are 0 combinational latch loops in the design through latch input



------------------------------------------------------------------------------------------------
| Design Timing Summary
| ---------------------
------------------------------------------------------------------------------------------------

    WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints     WPWS(ns)     TPWS(ns)  TPWS Failing Endpoints  TPWS Total Endpoints  
    -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------     --------     --------  ----------------------  --------------------  
     15.325        0.000                      0                  319        0.079        0.000                      0                  319        8.750        0.000                       0                   123  


All user specified timing constraints are met.


------------------------------------------------------------------------------------------------
| Clock Summary
| -------------
------------------------------------------------------------------------------------------------

Clock        Waveform(ns)       Period(ns)      Frequency(MHz)
-----        ------------       ----------      --------------
sys_clk_pin  {0.000 10.000}     20.000          50.000          


------------------------------------------------------------------------------------------------
| Intra Clock Table
| -----------------
------------------------------------------------------------------------------------------------

Clock             WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints     WPWS(ns)     TPWS(ns)  TPWS Failing Endpoints  TPWS Total Endpoints  
-----             -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------     --------     --------  ----------------------  --------------------  
sys_clk_pin        15.325        0.000                      0                  319        0.079        0.000                      0                  319        8.750        0.000                       0                   123  


------------------------------------------------------------------------------------------------
| Inter Clock Table
| -----------------
------------------------------------------------------------------------------------------------

From Clock    To Clock          WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints  
----------    --------          -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------  


------------------------------------------------------------------------------------------------
| Other Path Groups Table
| -----------------------
------------------------------------------------------------------------------------------------

Path Group    From Clock    To Clock          WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints  
----------    ----------    --------          -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------  


------------------------------------------------------------------------------------------------
| Timing Details
| --------------
------------------------------------------------------------------------------------------------


---------------------------------------------------------------------------------------------------
From Clock:  sys_clk_pin
  To Clock:  sys_clk_pin

Setup :            0  Failing Endpoints,  Worst Slack       15.325ns,  Total Violation        0.000ns
Hold  :            0  Failing Endpoints,  Worst Slack        0.079ns,  Total Violation        0.000ns
PW    :            0  Failing Endpoints,  Worst Slack        8.750ns,  Total Violation        0.000ns
---------------------------------------------------------------------------------------------------


Max Delay Paths
--------------------------------------------------------------------------------------
Slack (MET) :             15.325ns  (required time - arrival time)
  Source:                 hb_cnt_reg[0]/C
                            (rising edge-triggered cell FDRE clocked by sys_clk_pin  {rise@0.000ns fall@10.000ns period=20.000ns})
  Destination:            hb_cnt_reg[29]/R
                            (rising edge-triggered cell FDRE clocked by sys_clk_pin  {rise@0.000ns fall@10.000ns period=20.000ns})
  Path Group:             sys_clk_pin
  Path Type:              Setup (Max at Slow Process Corner)
  Requirement:            20.000ns  (sys_clk_pin rise@20.000ns - sys_clk_pin rise@0.000ns)
  Data Path Delay:        4.079ns  (logic 0.704ns (17.257%)  route 3.375ns (82.743%))
  Logic Levels:           2  (LUT2=1 LUT6=1)
  Clock Path Skew:        -0.131ns (DCD - SCD + CPR)
    Destination Clock Delay (DCD):    4.916ns = ( 24.916 - 20.000 ) 
    Source Clock Delay      (SCD):    5.226ns
    Clock Pessimism Removal (CPR):    0.179ns
  Clock Uncertainty:      0.035ns  ((TSJ^2 + TIJ^2)^1/2 + DJ) / 2 + PE
    Total System Jitter     (TSJ):    0.071ns
    Total Input Jitter      (TIJ):    0.000ns
    Discrete Jitter          (DJ):    0.000ns
    Phase Error              (PE):    0.000ns

    Location             Delay type                Incr(ns)  Path(ns)    Netlist Resource(s)
  -------------------------------------------------------------------    -------------------
                         (clock sys_clk_pin rise edge)
                                                      0.000     0.000 r  
    N11                                               0.000     0.000 r  CLK (IN)
                         net (fo=0)                   0.000     0.000    CLK
    N11                  IBUF (Prop_ibuf_I_O)         1.519     1.519 r  CLK_IBUF_inst/O
                         net (fo=1, routed)           1.972     3.490    CLK_IBUF
    BUFGCTRL_X0Y0        BUFG (Prop_bufg_I_O)         0.096     3.586 r  CLK_IBUF_BUFG_inst/O
                         net (fo=122, routed)         1.639     5.226    CLK_IBUF_BUFG
    SLICE_X62Y49         FDRE                                         r  hb_cnt_reg[0]/C
  -------------------------------------------------------------------    -------------------
    SLICE_X62Y49         FDRE (Prop_fdre_C_Q)         0.456     5.682 r  hb_cnt_reg[0]/Q
                         net (fo=3, routed)           1.049     6.730    hb_cnt[0]
    SLICE_X62Y49         LUT2 (Prop_lut2_I0_O)        0.124     6.854 r  hb_cnt[31]_i_3/O
                         net (fo=1, routed)           1.297     8.152    hb_cnt[31]_i_3_n_0
    SLICE_X62Y52         LUT6 (Prop_lut6_I0_O)        0.124     8.276 r  hb_cnt[31]_i_1/O
                         net (fo=33, routed)          1.029     9.305    hb
    SLICE_X63Y56         FDRE                                         r  hb_cnt_reg[29]/R
  -------------------------------------------------------------------    -------------------

                         (clock sys_clk_pin rise edge)
                                                     20.000    20.000 r  
    N11                                               0.000    20.000 r  CLK (IN)
                         net (fo=0)                   0.000    20.000    CLK
    N11                  IBUF (Prop_ibuf_I_O)         1.448    21.448 r  CLK_IBUF_inst/O
                         net (fo=1, routed)           1.868    23.316    CLK_IBUF
    BUFGCTRL_X0Y0        BUFG (Prop_bufg_I_O)         0.091    23.407 r  CLK_IBUF_BUFG_inst/O
                         net (fo=122, routed)         1.509    24.916    CLK_IBUF_BUFG
    SLICE_X63Y56         FDRE                                         r  hb_cnt_reg[29]/C
                         clock pessimism              0.179    25.095    
                         clock uncertainty           -0.035    25.060    
    SLICE_X63Y56         FDRE (Setup_fdre_C_R)       -0.429    24.631    hb_cnt_reg[29]
  -------------------------------------------------------------------
                         required time                         24.631    
                         arrival time                          -9.305    
  -------------------------------------------------------------------
                         slack                                 15.325    





Min Delay Paths
--------------------------------------------------------------------------------------
Slack (MET) :             0.079ns  (arrival time - required time)
  Source:                 u_dut/u_fsm/addr_q_reg[3]/C
                            (rising edge-triggered cell FDRE clocked by sys_clk_pin  {rise@0.000ns fall@10.000ns period=20.000ns})
  Destination:            u_dut/u_mem/mem_reg_0_15_0_0/SP/ADR3
                            (rising edge-triggered cell RAMS32 clocked by sys_clk_pin  {rise@0.000ns fall@10.000ns period=20.000ns})
  Path Group:             sys_clk_pin
  Path Type:              Hold (Min at Fast Process Corner)
  Requirement:            0.000ns  (sys_clk_pin rise@0.000ns - sys_clk_pin rise@0.000ns)
  Data Path Delay:        0.352ns  (logic 0.141ns (40.027%)  route 0.211ns (59.973%))
  Logic Levels:           0  
  Clock Path Skew:        0.033ns (DCD - SCD - CPR)
    Destination Clock Delay (DCD):    2.048ns
    Source Clock Delay      (SCD):    1.535ns
    Clock Pessimism Removal (CPR):    0.480ns

    Location             Delay type                Incr(ns)  Path(ns)    Netlist Resource(s)
  -------------------------------------------------------------------    -------------------
                         (clock sys_clk_pin rise edge)
                                                      0.000     0.000 r  
    N11                                               0.000     0.000 r  CLK (IN)
                         net (fo=0)                   0.000     0.000    CLK
    N11                  IBUF (Prop_ibuf_I_O)         0.286     0.286 r  CLK_IBUF_inst/O
                         net (fo=1, routed)           0.634     0.920    CLK_IBUF
    BUFGCTRL_X0Y0        BUFG (Prop_bufg_I_O)         0.026     0.946 r  CLK_IBUF_BUFG_inst/O
                         net (fo=122, routed)         0.589     1.535    u_dut/u_fsm/CLK_IBUF_BUFG
    SLICE_X63Y65         FDRE                                         r  u_dut/u_fsm/addr_q_reg[3]/C
  -------------------------------------------------------------------    -------------------
    SLICE_X63Y65         FDRE (Prop_fdre_C_Q)         0.141     1.676 r  u_dut/u_fsm/addr_q_reg[3]/Q
                         net (fo=8, routed)           0.211     1.887    u_dut/u_mem/mem_reg_0_15_0_0/A3
    SLICE_X60Y65         RAMS32                                       r  u_dut/u_mem/mem_reg_0_15_0_0/SP/ADR3
  -------------------------------------------------------------------    -------------------

                         (clock sys_clk_pin rise edge)
                                                      0.000     0.000 r  
    N11                                               0.000     0.000 r  CLK (IN)
                         net (fo=0)                   0.000     0.000    CLK
    N11                  IBUF (Prop_ibuf_I_O)         0.475     0.475 r  CLK_IBUF_inst/O
                         net (fo=1, routed)           0.689     1.163    CLK_IBUF
    BUFGCTRL_X0Y0        BUFG (Prop_bufg_I_O)         0.029     1.192 r  CLK_IBUF_BUFG_inst/O
                         net (fo=122, routed)         0.855     2.048    u_dut/u_mem/mem_reg_0_15_0_0/WCLK
    SLICE_X60Y65         RAMS32                                       r  u_dut/u_mem/mem_reg_0_15_0_0/SP/CLK
                         clock pessimism             -0.480     1.568    
    SLICE_X60Y65         RAMS32 (Hold_rams32_CLK_ADR3)
                                                      0.240     1.808    u_dut/u_mem/mem_reg_0_15_0_0/SP
  -------------------------------------------------------------------
                         required time                         -1.808    
                         arrival time                           1.887    
  -------------------------------------------------------------------
                         slack                                  0.079    





Pulse Width Checks
--------------------------------------------------------------------------------------
Clock Name:         sys_clk_pin
Waveform(ns):       { 0.000 10.000 }
Period(ns):         20.000
Sources:            { CLK }

Check Type        Corner  Lib Pin     Reference Pin  Required(ns)  Actual(ns)  Slack(ns)  Location       Pin
Min Period        n/a     BUFG/I      n/a            2.155         20.000      17.845     BUFGCTRL_X0Y0  CLK_IBUF_BUFG_inst/I
Low Pulse Width   Slow    RAMS32/CLK  n/a            1.250         10.000      8.750      SLICE_X60Y65   u_dut/u_mem/mem_reg_0_15_0_0/SP/CLK
High Pulse Width  Slow    RAMS32/CLK  n/a            1.250         10.000      8.750      SLICE_X60Y65   u_dut/u_mem/mem_reg_0_15_0_0/SP/CLK
```


---

## D. Critical paths (critical_paths.rpt)

```text
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
| Date         : Fri Nov 20 12:10:34 2026
| Host         : DESKTOP-U2MVLKN running 64-bit major release  (build 9200)
| Command      : report_timing -max_paths 5 -file out/critical_paths.rpt
| Design       : edge_selftest_top
| Device       : 7a35t-ftg256
| Speed File   : -1  PRODUCTION 1.23 2018-06-13
| Design State : Routed
---------------------------------------------------------------------------------------------------------------------------------------------

Timing Report

Slack (MET) :             15.325ns  (required time - arrival time)
  Source:                 hb_cnt_reg[0]/C
                            (rising edge-triggered cell FDRE clocked by sys_clk_pin  {rise@0.000ns fall@10.000ns period=20.000ns})
  Destination:            hb_cnt_reg[29]/R
                            (rising edge-triggered cell FDRE clocked by sys_clk_pin  {rise@0.000ns fall@10.000ns period=20.000ns})
  Path Group:             sys_clk_pin
  Path Type:              Setup (Max at Slow Process Corner)
  Requirement:            20.000ns  (sys_clk_pin rise@20.000ns - sys_clk_pin rise@0.000ns)
  Data Path Delay:        4.079ns  (logic 0.704ns (17.257%)  route 3.375ns (82.743%))
  Logic Levels:           2  (LUT2=1 LUT6=1)
  Clock Path Skew:        -0.131ns (DCD - SCD + CPR)
    Destination Clock Delay (DCD):    4.916ns = ( 24.916 - 20.000 ) 
    Source Clock Delay      (SCD):    5.226ns
    Clock Pessimism Removal (CPR):    0.179ns
  Clock Uncertainty:      0.035ns  ((TSJ^2 + TIJ^2)^1/2 + DJ) / 2 + PE
    Total System Jitter     (TSJ):    0.071ns
    Total Input Jitter      (TIJ):    0.000ns
    Discrete Jitter          (DJ):    0.000ns
    Phase Error              (PE):    0.000ns

    Location             Delay type                Incr(ns)  Path(ns)    Netlist Resource(s)
  -------------------------------------------------------------------    -------------------
                         (clock sys_clk_pin rise edge)
                                                      0.000     0.000 r  
    N11                                               0.000     0.000 r  CLK (IN)
                         net (fo=0)                   0.000     0.000    CLK
    N11                  IBUF (Prop_ibuf_I_O)         1.519     1.519 r  CLK_IBUF_inst/O
                         net (fo=1, routed)           1.972     3.490    CLK_IBUF
    BUFGCTRL_X0Y0        BUFG (Prop_bufg_I_O)         0.096     3.586 r  CLK_IBUF_BUFG_inst/O
                         net (fo=122, routed)         1.639     5.226    CLK_IBUF_BUFG
    SLICE_X62Y49         FDRE                                         r  hb_cnt_reg[0]/C
  -------------------------------------------------------------------    -------------------
    SLICE_X62Y49         FDRE (Prop_fdre_C_Q)         0.456     5.682 r  hb_cnt_reg[0]/Q
                         net (fo=3, routed)           1.049     6.730    hb_cnt[0]
    SLICE_X62Y49         LUT2 (Prop_lut2_I0_O)        0.124     6.854 r  hb_cnt[31]_i_3/O
                         net (fo=1, routed)           1.297     8.152    hb_cnt[31]_i_3_n_0
    SLICE_X62Y52         LUT6 (Prop_lut6_I0_O)        0.124     8.276 r  hb_cnt[31]_i_1/O
                         net (fo=33, routed)          1.029     9.305    hb
    SLICE_X63Y56         FDRE                                         r  hb_cnt_reg[29]/R
  -------------------------------------------------------------------    -------------------

                         (clock sys_clk_pin rise edge)
                                                     20.000    20.000 r  
    N11                                               0.000    20.000 r  CLK (IN)
                         net (fo=0)                   0.000    20.000    CLK
    N11                  IBUF (Prop_ibuf_I_O)         1.448    21.448 r  CLK_IBUF_inst/O
                         net (fo=1, routed)           1.868    23.316    CLK_IBUF
    BUFGCTRL_X0Y0        BUFG (Prop_bufg_I_O)         0.091    23.407 r  CLK_IBUF_BUFG_inst/O
                         net (fo=122, routed)         1.509    24.916    CLK_IBUF_BUFG
    SLICE_X63Y56         FDRE                                         r  hb_cnt_reg[29]/C
                         clock pessimism              0.179    25.095    
                         clock uncertainty           -0.035    25.060    
    SLICE_X63Y56         FDRE (Setup_fdre_C_R)       -0.429    24.631    hb_cnt_reg[29]
  -------------------------------------------------------------------
                         required time                         24.631    
                         arrival time                          -9.305    
  -------------------------------------------------------------------
                         slack                                 15.325    

Slack (MET) :             15.325ns  (required time - arrival time)
  Source:                 hb_cnt_reg[0]/C
                            (rising edge-triggered cell FDRE clocked by sys_clk_pin  {rise@0.000ns fall@10.000ns period=20.000ns})
  Destination:            hb_cnt_reg[30]/R
                            (rising edge-triggered cell FDRE clocked by sys_clk_pin  {rise@0.000ns fall@10.000ns period=20.000ns})
  Path Group:             sys_clk_pin
  Path Type:              Setup (Max at Slow Process Corner)
  Requirement:            20.000ns  (sys_clk_pin rise@20.000ns - sys_clk_pin rise@0.000ns)
  Data Path Delay:        4.079ns  (logic 0.704ns (17.257%)  route 3.375ns (82.743%))
  Logic Levels:           2  (LUT2=1 LUT6=1)
  Clock Path Skew:        -0.131ns (DCD - SCD + CPR)
    Destination Clock Delay (DCD):    4.916ns = ( 24.916 - 20.000 ) 
    Source Clock Delay      (SCD):    5.226ns
    Clock Pessimism Removal (CPR):    0.179ns
  Clock Uncertainty:      0.035ns  ((TSJ^2 + TIJ^2)^1/2 + DJ) / 2 + PE
    Total System Jitter     (TSJ):    0.071ns
    Total Input Jitter      (TIJ):    0.000ns
    Discrete Jitter          (DJ):    0.000ns
    Phase Error              (PE):    0.000ns

    Location             Delay type                Incr(ns)  Path(ns)    Netlist Resource(s)
  -------------------------------------------------------------------    -------------------
                         (clock sys_clk_pin rise edge)
                                                      0.000     0.000 r  
    N11                                               0.000     0.000 r  CLK (IN)
                         net (fo=0)                   0.000     0.000    CLK
    N11                  IBUF (Prop_ibuf_I_O)         1.519     1.519 r  CLK_IBUF_inst/O
                         net (fo=1, routed)           1.972     3.490    CLK_IBUF
    BUFGCTRL_X0Y0        BUFG (Prop_bufg_I_O)         0.096     3.586 r  CLK_IBUF_BUFG_inst/O
                         net (fo=122, routed)         1.639     5.226    CLK_IBUF_BUFG
    SLICE_X62Y49         FDRE                                         r  hb_cnt_reg[0]/C
  -------------------------------------------------------------------    -------------------
    SLICE_X62Y49         FDRE (Prop_fdre_C_Q)         0.456     5.682 r  hb_cnt_reg[0]/Q
                         net (fo=3, routed)           1.049     6.730    hb_cnt[0]
    SLICE_X62Y49         LUT2 (Prop_lut2_I0_O)        0.124     6.854 r  hb_cnt[31]_i_3/O
                         net (fo=1, routed)           1.297     8.152    hb_cnt[31]_i_3_n_0
    SLICE_X62Y52         LUT6 (Prop_lut6_I0_O)        0.124     8.276 r  hb_cnt[31]_i_1/O
                         net (fo=33, routed)          1.029     9.305    hb
    SLICE_X63Y56         FDRE                                         r  hb_cnt_reg[30]/R
  -------------------------------------------------------------------    -------------------

                         (clock sys_clk_pin rise edge)
                                                     20.000    20.000 r  
    N11                                               0.000    20.000 r  CLK (IN)
                         net (fo=0)                   0.000    20.000    CLK
    N11                  IBUF (Prop_ibuf_I_O)         1.448    21.448 r  CLK_IBUF_inst/O
                         net (fo=1, routed)           1.868    23.316    CLK_IBUF
    BUFGCTRL_X0Y0        BUFG (Prop_bufg_I_O)         0.091    23.407 r  CLK_IBUF_BUFG_inst/O
                         net (fo=122, routed)         1.509    24.916    CLK_IBUF_BUFG
    SLICE_X63Y56         FDRE                                         r  hb_cnt_reg[30]/C
                         clock pessimism              0.179    25.095    
                         clock uncertainty           -0.035    25.060    
    SLICE_X63Y56         FDRE (Setup_fdre_C_R)       -0.429    24.631    hb_cnt_reg[30]
  -------------------------------------------------------------------
                         required time                         24.631    
                         arrival time                          -9.305    
  -------------------------------------------------------------------
                         slack                                 15.325    

Slack (MET) :             15.325ns  (required time - arrival time)
  Source:                 hb_cnt_reg[0]/C
                            (rising edge-triggered cell FDRE clocked by sys_clk_pin  {rise@0.000ns fall@10.000ns period=20.000ns})
  Destination:            hb_cnt_reg[31]/R
                            (rising edge-triggered cell FDRE clocked by sys_clk_pin  {rise@0.000ns fall@10.000ns period=20.000ns})
  Path Group:             sys_clk_pin
  Path Type:              Setup (Max at Slow Process Corner)
  Requirement:            20.000ns  (sys_clk_pin rise@20.000ns - sys_clk_pin rise@0.000ns)
  Data Path Delay:        4.079ns  (logic 0.704ns (17.257%)  route 3.375ns (82.743%))
  Logic Levels:           2  (LUT2=1 LUT6=1)
  Clock Path Skew:        -0.131ns (DCD - SCD + CPR)
    Destination Clock Delay (DCD):    4.916ns = ( 24.916 - 20.000 ) 
    Source Clock Delay      (SCD):    5.226ns
    Clock Pessimism Removal (CPR):    0.179ns
  Clock Uncertainty:      0.035ns  ((TSJ^2 + TIJ^2)^1/2 + DJ) / 2 + PE
    Total System Jitter     (TSJ):    0.071ns
    Total Input Jitter      (TIJ):    0.000ns
    Discrete Jitter          (DJ):    0.000ns
    Phase Error              (PE):    0.000ns

    Location             Delay type                Incr(ns)  Path(ns)    Netlist Resource(s)
  -------------------------------------------------------------------    -------------------
                         (clock sys_clk_pin rise edge)
                                                      0.000     0.000 r  
    N11                                               0.000     0.000 r  CLK (IN)
                         net (fo=0)                   0.000     0.000    CLK
    N11                  IBUF (Prop_ibuf_I_O)         1.519     1.519 r  CLK_IBUF_inst/O
                         net (fo=1, routed)           1.972     3.490    CLK_IBUF
    BUFGCTRL_X0Y0        BUFG (Prop_bufg_I_O)         0.096     3.586 r  CLK_IBUF_BUFG_inst/O
                         net (fo=122, routed)         1.639     5.226    CLK_IBUF_BUFG
    SLICE_X62Y49         FDRE                                         r  hb_cnt_reg[0]/C
  -------------------------------------------------------------------    -------------------
    SLICE_X62Y49         FDRE (Prop_fdre_C_Q)         0.456     5.682 r  hb_cnt_reg[0]/Q
                         net (fo=3, routed)           1.049     6.730    hb_cnt[0]
    SLICE_X62Y49         LUT2 (Prop_lut2_I0_O)        0.124     6.854 r  hb_cnt[31]_i_3/O
                         net (fo=1, routed)           1.297     8.152    hb_cnt[31]_i_3_n_0
    SLICE_X62Y52         LUT6 (Prop_lut6_I0_O)        0.124     8.276 r  hb_cnt[31]_i_1/O
                         net (fo=33, routed)          1.029     9.305    hb
    SLICE_X63Y56         FDRE                                         r  hb_cnt_reg[31]/R
  -------------------------------------------------------------------    -------------------

                         (clock sys_clk_pin rise edge)
                                                     20.000    20.000 r  
    N11                                               0.000    20.000 r  CLK (IN)
                         net (fo=0)                   0.000    20.000    CLK
    N11                  IBUF (Prop_ibuf_I_O)         1.448    21.448 r  CLK_IBUF_inst/O
                         net (fo=1, routed)           1.868    23.316    CLK_IBUF
    BUFGCTRL_X0Y0        BUFG (Prop_bufg_I_O)         0.091    23.407 r  CLK_IBUF_BUFG_inst/O
                         net (fo=122, routed)         1.509    24.916    CLK_IBUF_BUFG
    SLICE_X63Y56         FDRE                                         r  hb_cnt_reg[31]/C
                         clock pessimism              0.179    25.095    
                         clock uncertainty           -0.035    25.060    
    SLICE_X63Y56         FDRE (Setup_fdre_C_R)       -0.429    24.631    hb_cnt_reg[31]
  -------------------------------------------------------------------
                         required time                         24.631    
                         arrival time                          -9.305    
  -------------------------------------------------------------------
                         slack                                 15.325    

Slack (MET) :             15.464ns  (required time - arrival time)
  Source:                 hb_cnt_reg[0]/C
                            (rising edge-triggered cell FDRE clocked by sys_clk_pin  {rise@0.000ns fall@10.000ns period=20.000ns})
  Destination:            hb_cnt_reg[25]/R
                            (rising edge-triggered cell FDRE clocked by sys_clk_pin  {rise@0.000ns fall@10.000ns period=20.000ns})
  Path Group:             sys_clk_pin
  Path Type:              Setup (Max at Slow Process Corner)
  Requirement:            20.000ns  (sys_clk_pin rise@20.000ns - sys_clk_pin rise@0.000ns)
  Data Path Delay:        3.941ns  (logic 0.704ns (17.863%)  route 3.237ns (82.137%))
  Logic Levels:           2  (LUT2=1 LUT6=1)
  Clock Path Skew:        -0.131ns (DCD - SCD + CPR)
    Destination Clock Delay (DCD):    4.916ns = ( 24.916 - 20.000 ) 
    Source Clock Delay      (SCD):    5.226ns
    Clock Pessimism Removal (CPR):    0.179ns
  Clock Uncertainty:      0.035ns  ((TSJ^2 + TIJ^2)^1/2 + DJ) / 2 + PE
    Total System Jitter     (TSJ):    0.071ns
    Total Input Jitter      (TIJ):    0.000ns
    Discrete Jitter          (DJ):    0.000ns
    Phase Error              (PE):    0.000ns

    Location             Delay type                Incr(ns)  Path(ns)    Netlist Resource(s)
  -------------------------------------------------------------------    -------------------
                         (clock sys_clk_pin rise edge)
                                                      0.000     0.000 r  
    N11                                               0.000     0.000 r  CLK (IN)
                         net (fo=0)                   0.000     0.000    CLK
    N11                  IBUF (Prop_ibuf_I_O)         1.519     1.519 r  CLK_IBUF_inst/O
                         net (fo=1, routed)           1.972     3.490    CLK_IBUF
    BUFGCTRL_X0Y0        BUFG (Prop_bufg_I_O)         0.096     3.586 r  CLK_IBUF_BUFG_inst/O
                         net (fo=122, routed)         1.639     5.226    CLK_IBUF_BUFG
    SLICE_X62Y49         FDRE                                         r  hb_cnt_reg[0]/C
  -------------------------------------------------------------------    -------------------
    SLICE_X62Y49         FDRE (Prop_fdre_C_Q)         0.456     5.682 r  hb_cnt_reg[0]/Q
                         net (fo=3, routed)           1.049     6.730    hb_cnt[0]
    SLICE_X62Y49         LUT2 (Prop_lut2_I0_O)        0.124     6.854 r  hb_cnt[31]_i_3/O
                         net (fo=1, routed)           1.297     8.152    hb_cnt[31]_i_3_n_0
    SLICE_X62Y52         LUT6 (Prop_lut6_I0_O)        0.124     8.276 r  hb_cnt[31]_i_1/O
                         net (fo=33, routed)          0.891     9.167    hb
    SLICE_X63Y55         FDRE                                         r  hb_cnt_reg[25]/R
  -------------------------------------------------------------------    -------------------

                         (clock sys_clk_pin rise edge)
                                                     20.000    20.000 r  
    N11                                               0.000    20.000 r  CLK (IN)
                         net (fo=0)                   0.000    20.000    CLK
    N11                  IBUF (Prop_ibuf_I_O)         1.448    21.448 r  CLK_IBUF_inst/O
                         net (fo=1, routed)           1.868    23.316    CLK_IBUF
    BUFGCTRL_X0Y0        BUFG (Prop_bufg_I_O)         0.091    23.407 r  CLK_IBUF_BUFG_inst/O
                         net (fo=122, routed)         1.509    24.916    CLK_IBUF_BUFG
    SLICE_X63Y55         FDRE                                         r  hb_cnt_reg[25]/C
                         clock pessimism              0.179    25.095    
                         clock uncertainty           -0.035    25.060    
    SLICE_X63Y55         FDRE (Setup_fdre_C_R)       -0.429    24.631    hb_cnt_reg[25]
  -------------------------------------------------------------------
                         required time                         24.631    
                         arrival time                          -9.167    
  -------------------------------------------------------------------
                         slack                                 15.464    

Slack (MET) :             15.464ns  (required time - arrival time)
  Source:                 hb_cnt_reg[0]/C
                            (rising edge-triggered cell FDRE clocked by sys_clk_pin  {rise@0.000ns fall@10.000ns period=20.000ns})
  Destination:            hb_cnt_reg[26]/R
                            (rising edge-triggered cell FDRE clocked by sys_clk_pin  {rise@0.000ns fall@10.000ns period=20.000ns})
  Path Group:             sys_clk_pin
  Path Type:              Setup (Max at Slow Process Corner)
  Requirement:            20.000ns  (sys_clk_pin rise@20.000ns - sys_clk_pin rise@0.000ns)
  Data Path Delay:        3.941ns  (logic 0.704ns (17.863%)  route 3.237ns (82.137%))
  Logic Levels:           2  (LUT2=1 LUT6=1)
  Clock Path Skew:        -0.131ns (DCD - SCD + CPR)
    Destination Clock Delay (DCD):    4.916ns = ( 24.916 - 20.000 ) 
    Source Clock Delay      (SCD):    5.226ns
    Clock Pessimism Removal (CPR):    0.179ns
  Clock Uncertainty:      0.035ns  ((TSJ^2 + TIJ^2)^1/2 + DJ) / 2 + PE
    Total System Jitter     (TSJ):    0.071ns
    Total Input Jitter      (TIJ):    0.000ns
    Discrete Jitter          (DJ):    0.000ns
    Phase Error              (PE):    0.000ns

    Location             Delay type                Incr(ns)  Path(ns)    Netlist Resource(s)
  -------------------------------------------------------------------    -------------------
                         (clock sys_clk_pin rise edge)
                                                      0.000     0.000 r  
    N11                                               0.000     0.000 r  CLK (IN)
                         net (fo=0)                   0.000     0.000    CLK
    N11                  IBUF (Prop_ibuf_I_O)         1.519     1.519 r  CLK_IBUF_inst/O
                         net (fo=1, routed)           1.972     3.490    CLK_IBUF
    BUFGCTRL_X0Y0        BUFG (Prop_bufg_I_O)         0.096     3.586 r  CLK_IBUF_BUFG_inst/O
                         net (fo=122, routed)         1.639     5.226    CLK_IBUF_BUFG
    SLICE_X62Y49         FDRE                                         r  hb_cnt_reg[0]/C
  -------------------------------------------------------------------    -------------------
    SLICE_X62Y49         FDRE (Prop_fdre_C_Q)         0.456     5.682 r  hb_cnt_reg[0]/Q
                         net (fo=3, routed)           1.049     6.730    hb_cnt[0]
    SLICE_X62Y49         LUT2 (Prop_lut2_I0_O)        0.124     6.854 r  hb_cnt[31]_i_3/O
                         net (fo=1, routed)           1.297     8.152    hb_cnt[31]_i_3_n_0
    SLICE_X62Y52         LUT6 (Prop_lut6_I0_O)        0.124     8.276 r  hb_cnt[31]_i_1/O
                         net (fo=33, routed)          0.891     9.167    hb
    SLICE_X63Y55         FDRE                                         r  hb_cnt_reg[26]/R
  -------------------------------------------------------------------    -------------------

                         (clock sys_clk_pin rise edge)
                                                     20.000    20.000 r  
    N11                                               0.000    20.000 r  CLK (IN)
                         net (fo=0)                   0.000    20.000    CLK
    N11                  IBUF (Prop_ibuf_I_O)         1.448    21.448 r  CLK_IBUF_inst/O
                         net (fo=1, routed)           1.868    23.316    CLK_IBUF
    BUFGCTRL_X0Y0        BUFG (Prop_bufg_I_O)         0.091    23.407 r  CLK_IBUF_BUFG_inst/O
                         net (fo=122, routed)         1.509    24.916    CLK_IBUF_BUFG
    SLICE_X63Y55         FDRE                                         r  hb_cnt_reg[26]/C
                         clock pessimism              0.179    25.095    
                         clock uncertainty           -0.035    25.060    
    SLICE_X63Y55         FDRE (Setup_fdre_C_R)       -0.429    24.631    hb_cnt_reg[26]
  -------------------------------------------------------------------
                         required time                         24.631    
                         arrival time                          -9.167    
  -------------------------------------------------------------------
                         slack                                 15.464    
```


---

## E. Power report (power.rpt)

```text
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
-------------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version     : Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
| Date             : Fri Nov 20 12:10:34 2026
| Host             : DESKTOP-U2MVLKN running 64-bit major release  (build 9200)
| Command          : report_power -file out/power.rpt
| Design           : edge_selftest_top
| Device           : xc7a35tftg256-1
| Design State     : routed
| Grade            : commercial
| Process          : typical
| Characterization : Production
-------------------------------------------------------------------------------------------------------------------------------------------------

Power Report

Table of Contents
-----------------
1. Summary
1.1 On-Chip Components
1.2 Power Supply Summary
1.3 Confidence Level
2. Settings
2.1 Environment
2.2 Clock Constraints
3. Detailed Reports
3.1 By Hierarchy

1. Summary
----------

+--------------------------+--------------+
| Total On-Chip Power (W)  | 0.075        |
| Design Power Budget (W)  | Unspecified* |
| Power Budget Margin (W)  | NA           |
| Dynamic (W)              | 0.003        |
| Device Static (W)        | 0.072        |
| Effective TJA (C/W)      | 4.9          |
| Max Ambient (C)          | 84.6         |
| Junction Temperature (C) | 25.4         |
| Confidence Level         | Medium       |
| Setting File             | ---          |
| Simulation Activity File | ---          |
| Design Nets Matched      | NA           |
+--------------------------+--------------+
* Specify Design Power Budget using, set_operating_conditions -design_power_budget <value in Watts>


1.1 On-Chip Components
----------------------

+--------------------------+-----------+----------+-----------+-----------------+
| On-Chip                  | Power (W) | Used     | Available | Utilization (%) |
+--------------------------+-----------+----------+-----------+-----------------+
| Clocks                   |    <0.001 |        3 |       --- |             --- |
| Slice Logic              |    <0.001 |      255 |       --- |             --- |
|   LUT as Logic           |    <0.001 |       95 |     20800 |            0.46 |
|   Register               |    <0.001 |      114 |     41600 |            0.27 |
|   CARRY4                 |    <0.001 |        8 |      8150 |            0.10 |
|   LUT as Distributed RAM |    <0.001 |        8 |      9600 |            0.08 |
|   Others                 |     0.000 |        6 |       --- |             --- |
| Signals                  |    <0.001 |      185 |       --- |             --- |
| I/O                      |     0.002 |        7 |       170 |            4.12 |
| Static Power             |     0.072 |          |           |                 |
| Total                    |     0.075 |          |           |                 |
+--------------------------+-----------+----------+-----------+-----------------+


1.2 Power Supply Summary
------------------------

+-----------+-------------+-----------+-------------+------------+-------------+-------------+------------+
| Source    | Voltage (V) | Total (A) | Dynamic (A) | Static (A) | Powerup (A) | Budget (A)  | Margin (A) |
+-----------+-------------+-----------+-------------+------------+-------------+-------------+------------+
| Vccint    |       1.000 |     0.011 |       0.001 |      0.010 |       NA    | Unspecified | NA         |
| Vccaux    |       1.800 |     0.013 |       0.000 |      0.013 |       NA    | Unspecified | NA         |
| Vcco33    |       3.300 |     0.002 |       0.001 |      0.001 |       NA    | Unspecified | NA         |
| Vcco25    |       2.500 |     0.000 |       0.000 |      0.000 |       NA    | Unspecified | NA         |
| Vcco18    |       1.800 |     0.000 |       0.000 |      0.000 |       NA    | Unspecified | NA         |
| Vcco15    |       1.500 |     0.000 |       0.000 |      0.000 |       NA    | Unspecified | NA         |
| Vcco135   |       1.350 |     0.000 |       0.000 |      0.000 |       NA    | Unspecified | NA         |
| Vcco12    |       1.200 |     0.000 |       0.000 |      0.000 |       NA    | Unspecified | NA         |
| Vccaux_io |       1.800 |     0.000 |       0.000 |      0.000 |       NA    | Unspecified | NA         |
| Vccbram   |       1.000 |     0.000 |       0.000 |      0.000 |       NA    | Unspecified | NA         |
| MGTAVcc   |       1.000 |     0.000 |       0.000 |      0.000 |       NA    | Unspecified | NA         |
| MGTAVtt   |       1.200 |     0.000 |       0.000 |      0.000 |       NA    | Unspecified | NA         |
| Vccadc    |       1.800 |     0.020 |       0.000 |      0.020 |       NA    | Unspecified | NA         |
+-----------+-------------+-----------+-------------+------------+-------------+-------------+------------+


1.3 Confidence Level
--------------------

+-----------------------------+------------+-------------------------------------------------------+------------------------------------------------------------------------------------------------------------+
| User Input Data             | Confidence | Details                                               | Action                                                                                                     |
+-----------------------------+------------+-------------------------------------------------------+------------------------------------------------------------------------------------------------------------+
| Design implementation state | High       | Design is routed                                      |                                                                                                            |
| Clock nodes activity        | High       | User specified more than 95% of clocks                |                                                                                                            |
| I/O nodes activity          | Medium     | More than 5% of inputs are missing user specification | Provide missing input activity with simulation results or by editing the "By Resource Type -> I/Os" view   |
| Internal nodes activity     | Medium     | User specified less than 25% of internal nodes        | Provide missing internal nodes activity with simulation results or by editing the "By Resource Type" views |
| Device models               | High       | Device models are Production                          |                                                                                                            |
|                             |            |                                                       |                                                                                                            |
| Overall confidence level    | Medium     |                                                       |                                                                                                            |
+-----------------------------+------------+-------------------------------------------------------+------------------------------------------------------------------------------------------------------------+


2. Settings
-----------

2.1 Environment
---------------

+-----------------------+--------------------------+
| Ambient Temp (C)      | 25.0                     |
| ThetaJA (C/W)         | 4.9                      |
| Airflow (LFM)         | 250                      |
| Heat Sink             | medium (Medium Profile)  |
| ThetaSA (C/W)         | 4.6                      |
| Board Selection       | medium (10"x10")         |
| # of Board Layers     | 12to15 (12 to 15 Layers) |
| Board Temperature (C) | 25.0                     |
+-----------------------+--------------------------+


2.2 Clock Constraints
---------------------

+-------------+--------+-----------------+
| Clock       | Domain | Constraint (ns) |
+-------------+--------+-----------------+
| sys_clk_pin | CLK    |            20.0 |
+-------------+--------+-----------------+


3. Detailed Reports
-------------------

3.1 By Hierarchy
----------------

+-------------------+-----------+
| Name              | Power (W) |
+-------------------+-----------+
| edge_selftest_top |     0.003 |
+-------------------+-----------+
```


---

## F. DRC report (drc.rpt)

```text
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved. Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------------------------------------------------------------
| Tool Version : Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
| Date         : Fri Nov 20 12:10:34 2026
| Host         : DESKTOP-U2MVLKN running 64-bit major release  (build 9200)
| Command      : report_drc -file out/drc.rpt
| Design       : edge_selftest_top
| Device       : xc7a35tftg256-1
| Speed File   : -1
| Design State : Fully Routed
---------------------------------------------------------------------------------------------------------------------------------------------

Report DRC

Table of Contents
-----------------
1. REPORT SUMMARY
2. REPORT DETAILS

1. REPORT SUMMARY
-----------------
            Netlist: edge_selftest_top
          Floorplan: design_1
      Design limits: <entire design considered>
           Ruledeck: default
             Max checks: <unlimited>
             Checks found: 0
+------+----------+-------------+--------+
| Rule | Severity | Description | Checks |
+------+----------+-------------+--------+
+------+----------+-------------+--------+

2. REPORT DETAILS
-----------------
```


---

## G. Core testbench log, xsim (sim_core.log)

```text

****** xsim v2025.2 (64-bit)
  **** SW Build 6299465 on Fri Nov 14 19:35:11 GMT 2025
  **** IP Build 6300035 on Fri Nov 14 10:48:45 MST 2025
  **** SharedData Build 6298862 on Thu Nov 13 04:50:51 MST 2025
  **** Start of session at: Fri Nov 20 12:19:14 2026
    ** Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
    ** Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.

source xsim.dir/sim_core/xsim_script.tcl
# xsim {sim_core} -autoloadwcfg -runall
Time resolution is 1 ps
run -all
[30000] TEST: T1 reset values of configuration registers
    -> PASS  T1
[71000] TEST: T2 write all 16 words, read back, zero wait states
    -> PASS  T2
[1030000] TEST: T3 programmable wait states 1..7
    -> PASS  T3
[2310000] TEST: T4 simultaneous read + write request is rejected
    -> PASS  T4
[2401000] TEST: T5 address limit (LIMIT = 8)
    -> PASS  T5
[2620000] TEST: T6 write protect
    -> PASS  T6
[2800000] TEST: T7 request while busy is dropped and flagged
    -> PASS  T7
[3080000] TEST: T8 controller disabled (EN = 0) ignores requests
    -> PASS  T8
[3200000] TEST: T9 reset during a transaction
    -> PASS  T9
[3310000] TEST: T10 constrained-random regression (500 accesses)
    -> PASS  T10
============================================================
 SUMMARY: 2749 checks, 0 errors | 288 writes, 288 reads, 4 rejected
 RESULT : ALL TESTS PASSED
============================================================
$finish called at time : 30680 ns : File "C:/Vivado Projects/P8_MemCtrl/tb/tb_mem_ctrl.v" Line 286
exit
INFO: [Common 17-206] Exiting xsim at Fri Nov 20 12:19:16 2026...
```


---

## H. Board wrapper testbench log, xsim (sim_board.log)

```text

****** xsim v2025.2 (64-bit)
  **** SW Build 6299465 on Fri Nov 14 19:35:11 GMT 2025
  **** IP Build 6300035 on Fri Nov 14 10:48:45 MST 2025
  **** SharedData Build 6298862 on Thu Nov 13 04:50:51 MST 2025
  **** Start of session at: Fri Nov 20 12:19:19 2026
    ** Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
    ** Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.

source xsim.dir/sim_board/xsim_script.tcl
# xsim {sim_board} -autoloadwcfg -runall
Time resolution is 1 ps
run -all
outputs: mode0=0101 mode1=0101 fault=0110
ok  : MODE=0 done
ok  : MODE=0 pass
ok  : MODE=1 done
ok  : MODE=1 pass
ok  : fault run detected
ok  : heartbeat toggles
ok  : reset clears done
ok  : re-run after reset passes
RESULT : ALL TESTS PASSED
$finish called at time : 47290 ns : File "C:/Vivado Projects/P8_MemCtrl/board/tb_edge_selftest.v" Line 46
exit
INFO: [Common 17-206] Exiting xsim at Fri Nov 20 12:19:21 2026...
```


---

## I. Programming log (program.log)

```text
#-----------------------------------------------------------
# Vivado v2025.2 (64-bit)
# SW Build 6299465 on Fri Nov 14 19:35:11 GMT 2025
# IP Build 6300035 on Fri Nov 14 10:48:45 MST 2025
# SharedData Build 6298862 on Thu Nov 13 04:50:51 MST 2025
# Start of session at: Fri Nov 20 12:12:32 2026
# Process ID         : 17836
# Current directory  : C:/Vivado Projects/P8_MemCtrl/board
# Command line       : vivado.exe -mode batch -source program_board.tcl -log out\program.log -journal out\program.jou
# Log file           : C:/Vivado Projects/P8_MemCtrl/board/out/program.log
# Journal file       : C:/Vivado Projects/P8_MemCtrl/board\out\program.jou
# Running On         : DESKTOP-U2MVLKN
# Platform           : Windows Server 2016 or Windows 10
# Operating System   : 26300
# Processor Detail   : Intel(R) Core(TM) 7 240H
# CPU Frequency      : 2995 MHz
# CPU Physical cores : 10
# CPU Logical cores  : 16
# Host memory        : 16866 MB
# Swap memory        : 15126 MB
# Total Virtual      : 31992 MB
# Available Virtual  : 6237 MB
#-----------------------------------------------------------
source program_board.tcl
# open_hw_manager
open_hw_manager: Time (s): cpu = 00:00:07 ; elapsed = 00:00:05 . Memory (MB): peak = 529.230 ; gain = 223.750
# connect_hw_server
INFO: [Labtools 27-2285] Connecting to hw_server url TCP:localhost:3121
INFO: [Labtools 27-3415] Connecting to cs_server url TCP:localhost:0
INFO: [Labtools 27-3417] Launching cs_server...
INFO: [Labtools 27-2221] Launch Output:


******** Xilinx cs_server v2025.2.0
  ****** Build date   : Nov 14 2025-04:46:52
    **** Build number : 2025.2.1763075812
      ** Copyright 2017-2022 Xilinx, Inc. All Rights Reserved.
      ** Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.



# open_hw_target
INFO: [Labtoolstcl 44-466] Opening hw_target localhost:3121/xilinx_tcf/Digilent/210319A288EEA
# set dev [lindex [get_hw_devices xc7a35t_0] 0]
# current_hw_device $dev
# set_property PROGRAM.FILE out/edge_selftest.bit $dev
# program_hw_devices $dev
INFO: [Labtools 27-3164] End of startup status: HIGH
# close_hw_manager
INFO: [Common 17-206] Exiting Vivado at Fri Nov 20 12:12:42 2026...
```


---

## J. Constraints used (edge_artix7.xdc)

```text
## MOSART Project 8 - EDGE Artix-7 board constraints (xc7a35tftg256-1)
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
```


---

## K. Earlier Icarus simulation log (sim\sim_log.txt)

```text
VCD info: dumpfile mem_ctrl.vcd opened for output.
[30000] TEST: T1 reset values of configuration registers
    -> PASS  T1
[71000] TEST: T2 write all 16 words, read back, zero wait states
    -> PASS  T2
[1030000] TEST: T3 programmable wait states 1..7
    -> PASS  T3
[2310000] TEST: T4 simultaneous read + write request is rejected
    -> PASS  T4
[2401000] TEST: T5 address limit (LIMIT = 8)
    -> PASS  T5
[2620000] TEST: T6 write protect
    -> PASS  T6
[2800000] TEST: T7 request while busy is dropped and flagged
    -> PASS  T7
[3080000] TEST: T8 controller disabled (EN = 0) ignores requests
    -> PASS  T8
[3200000] TEST: T9 reset during a transaction
    -> PASS  T9
[3310000] TEST: T10 constrained-random regression (500 accesses)
    -> PASS  T10
============================================================
 SUMMARY: 3356 checks, 0 errors | 281 writes, 295 reads, 4 rejected
 RESULT : ALL TESTS PASSED
============================================================
../tb/tb_mem_ctrl.v:286: $finish called at 36680000 (1ps)
```


---

## L. Earlier Yosys utilization of the core (synth\yosys_utilization.txt)

```text

6. Printing statistics.

=== mem_ctrl_top ===

   Number of wires:                130
   Number of wire bits:            333
   Number of public wires:          76
   Number of public wire bits:     241
   Number of memories:               0
   Number of memory bits:            0
   Number of processes:              0
   Number of cells:                162
     BUFG                            1
     CARRY4                          1
     FDRE                           42
     FDSE                            2
     IBUF                           27
     LUT2                           21
     LUT3                           11
     LUT4                            4
     LUT5                            4
     LUT6                           19
     MUXF7                           7
     MUXF8                           3
     OBUF                           19
     RAM32M                          1
```


---

## M. Build log (build.log, full Vivado output)

```text
#-----------------------------------------------------------
# Vivado v2025.2 (64-bit)
# SW Build 6299465 on Fri Nov 14 19:35:11 GMT 2025
# IP Build 6300035 on Fri Nov 14 10:48:45 MST 2025
# SharedData Build 6298862 on Thu Nov 13 04:50:51 MST 2025
# Start of session at: Fri Nov 20 12:09:29 2026
# Process ID         : 28864
# Current directory  : C:/Vivado Projects/P8_MemCtrl/board
# Command line       : vivado.exe -mode batch -source run_board.tcl -log out\build.log -journal out\build.jou
# Log file           : C:/Vivado Projects/P8_MemCtrl/board/out/build.log
# Journal file       : C:/Vivado Projects/P8_MemCtrl/board\out\build.jou
# Running On         : DESKTOP-U2MVLKN
# Platform           : Windows Server 2016 or Windows 10
# Operating System   : 26300
# Processor Detail   : Intel(R) Core(TM) 7 240H
# CPU Frequency      : 2995 MHz
# CPU Physical cores : 10
# CPU Logical cores  : 16
# Host memory        : 16866 MB
# Swap memory        : 15219 MB
# Total Virtual      : 32085 MB
# Available Virtual  : 6316 MB
#-----------------------------------------------------------
source run_board.tcl
# set part xc7a35tftg256-1
# file mkdir out
# read_verilog [glob ../rtl/*.v]
read_verilog: Time (s): cpu = 00:00:07 ; elapsed = 00:00:05 . Memory (MB): peak = 526.227 ; gain = 219.430
# read_verilog edge_selftest_top.v
# read_xdc edge_artix7.xdc
# synth_design -top edge_selftest_top -part $part
Command: synth_design -top edge_selftest_top -part xc7a35tftg256-1
Starting synth_design
Attempting to get a license for feature 'Synthesis' and/or device 'xc7a35t'
INFO: [Common 17-349] Got license for feature 'Synthesis' and/or device 'xc7a35t'
INFO: [Device 21-403] Loading part xc7a35tftg256-1
INFO: [Synth 8-7079] Multithreading enabled for synth_design using a maximum of 2 processes.
INFO: [Synth 8-7078] Launching helper process for spawning children vivado processes
INFO: [Synth 8-7075] Helper process launched with PID 28368
---------------------------------------------------------------------------------
Starting RTL Elaboration : Time (s): cpu = 00:00:05 ; elapsed = 00:00:05 . Memory (MB): peak = 1256.469 ; gain = 540.508
---------------------------------------------------------------------------------
INFO: [Synth 8-6157] synthesizing module 'edge_selftest_top' [C:/Vivado Projects/P8_MemCtrl/board/edge_selftest_top.v:27]
INFO: [Synth 8-6157] synthesizing module 'mem_ctrl_top' [C:/Vivado Projects/P8_MemCtrl/rtl/mem_ctrl_top.v:10]
	Parameter DATA_W bound to: 8 - type: integer 
	Parameter ADDR_W bound to: 4 - type: integer 
INFO: [Synth 8-6157] synthesizing module 'cfg_regs' [C:/Vivado Projects/P8_MemCtrl/rtl/cfg_regs.v:20]
	Parameter ADDR_W bound to: 4 - type: integer 
INFO: [Synth 8-6155] done synthesizing module 'cfg_regs' (0#1) [C:/Vivado Projects/P8_MemCtrl/rtl/cfg_regs.v:20]
INFO: [Synth 8-6157] synthesizing module 'mem_ctrl_fsm' [C:/Vivado Projects/P8_MemCtrl/rtl/mem_ctrl_fsm.v:17]
	Parameter DATA_W bound to: 8 - type: integer 
	Parameter ADDR_W bound to: 4 - type: integer 
INFO: [Synth 8-6155] done synthesizing module 'mem_ctrl_fsm' (0#1) [C:/Vivado Projects/P8_MemCtrl/rtl/mem_ctrl_fsm.v:17]
INFO: [Synth 8-6157] synthesizing module 'sync_mem' [C:/Vivado Projects/P8_MemCtrl/rtl/sync_mem.v:10]
	Parameter DATA_W bound to: 8 - type: integer 
	Parameter ADDR_W bound to: 4 - type: integer 
INFO: [Synth 8-6155] done synthesizing module 'sync_mem' (0#1) [C:/Vivado Projects/P8_MemCtrl/rtl/sync_mem.v:10]
INFO: [Synth 8-6155] done synthesizing module 'mem_ctrl_top' (0#1) [C:/Vivado Projects/P8_MemCtrl/rtl/mem_ctrl_top.v:10]
WARNING: [Synth 8-589] replacing case/wildcard equality operator !== with logical equality operator != [C:/Vivado Projects/P8_MemCtrl/board/edge_selftest_top.v:118]
WARNING: [Synth 8-589] replacing case/wildcard equality operator !== with logical equality operator != [C:/Vivado Projects/P8_MemCtrl/board/edge_selftest_top.v:175]
INFO: [Synth 8-6155] done synthesizing module 'edge_selftest_top' (0#1) [C:/Vivado Projects/P8_MemCtrl/board/edge_selftest_top.v:27]
WARNING: [Synth 8-7129] Port cfg_wdata[7] in module cfg_regs is either unconnected or has no load
WARNING: [Synth 8-7129] Port cfg_wdata[6] in module cfg_regs is either unconnected or has no load
WARNING: [Synth 8-7129] Port cfg_wdata[5] in module cfg_regs is either unconnected or has no load
---------------------------------------------------------------------------------
Finished RTL Elaboration : Time (s): cpu = 00:00:06 ; elapsed = 00:00:07 . Memory (MB): peak = 1377.805 ; gain = 661.844
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Start Handling Custom Attributes
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Finished Handling Custom Attributes : Time (s): cpu = 00:00:06 ; elapsed = 00:00:07 . Memory (MB): peak = 1377.805 ; gain = 661.844
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Finished RTL Optimization Phase 1 : Time (s): cpu = 00:00:06 ; elapsed = 00:00:07 . Memory (MB): peak = 1377.805 ; gain = 661.844
---------------------------------------------------------------------------------
Netlist sorting complete. Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.006 . Memory (MB): peak = 1377.805 ; gain = 0.000
INFO: [Project 1-570] Preparing netlist for logic optimization

Processing XDC Constraints
Initializing timing engine
Parsing XDC File [C:/Vivado Projects/P8_MemCtrl/board/edge_artix7.xdc]
Finished Parsing XDC File [C:/Vivado Projects/P8_MemCtrl/board/edge_artix7.xdc]
INFO: [Project 1-236] Implementation specific constraints were found while reading constraint file [C:/Vivado Projects/P8_MemCtrl/board/edge_artix7.xdc]. These constraints will be ignored for synthesis but will be used in implementation. Impacted constraints are listed in the file [.Xil/edge_selftest_top_propImpl.xdc].
Resolution: To avoid this warning, move constraints listed in [.Xil/edge_selftest_top_propImpl.xdc] to another XDC file and exclude this new file from synthesis with the used_in_synthesis property (File Properties dialog in GUI) and re-run elaboration/synthesis.
Completed Processing XDC Constraints

Netlist sorting complete. Time (s): cpu = 00:00:00 ; elapsed = 00:00:00 . Memory (MB): peak = 1454.020 ; gain = 0.000
INFO: [Project 1-111] Unisim Transformation Summary:
No Unisim elements were transformed.

Constraint Validation Runtime : Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.004 . Memory (MB): peak = 1454.020 ; gain = 0.000
---------------------------------------------------------------------------------
Finished Constraint Validation : Time (s): cpu = 00:00:13 ; elapsed = 00:00:14 . Memory (MB): peak = 1454.020 ; gain = 738.059
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Start Loading Part and Timing Information
---------------------------------------------------------------------------------
Loading part: xc7a35tftg256-1
---------------------------------------------------------------------------------
Finished Loading Part and Timing Information : Time (s): cpu = 00:00:13 ; elapsed = 00:00:14 . Memory (MB): peak = 1454.020 ; gain = 738.059
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Start Applying 'set_property' XDC Constraints
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Finished applying 'set_property' XDC Constraints : Time (s): cpu = 00:00:13 ; elapsed = 00:00:14 . Memory (MB): peak = 1454.020 ; gain = 738.059
---------------------------------------------------------------------------------
INFO: [Synth 8-802] inferred FSM for state register 'state_reg' in module 'mem_ctrl_fsm'
---------------------------------------------------------------------------------------------------
                   State |                     New Encoding |                Previous Encoding 
---------------------------------------------------------------------------------------------------
                  S_IDLE |                           000001 |                              000
                 S_ERROR |                           000010 |                              101
                 S_WRITE |                           010000 |                              010
                  S_READ |                           100000 |                              001
                  S_WAIT |                           001000 |                              011
                  S_DONE |                           000100 |                              100
---------------------------------------------------------------------------------------------------
INFO: [Synth 8-3354] encoded FSM with state register 'state_reg' using encoding 'one-hot' in module 'mem_ctrl_fsm'
---------------------------------------------------------------------------------
Finished RTL Optimization Phase 2 : Time (s): cpu = 00:00:13 ; elapsed = 00:00:15 . Memory (MB): peak = 1454.020 ; gain = 738.059
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Start RTL Component Statistics 
---------------------------------------------------------------------------------
Detailed RTL Component Info : 
+---Adders : 
	   2 Input   32 Bit       Adders := 1     
	   2 Input    4 Bit       Adders := 2     
	   2 Input    3 Bit       Adders := 2     
+---XORs : 
	   2 Input      8 Bit         XORs := 1     
+---Registers : 
	               32 Bit    Registers := 1     
	                8 Bit    Registers := 4     
	                5 Bit    Registers := 3     
	                4 Bit    Registers := 5     
	                3 Bit    Registers := 2     
	                2 Bit    Registers := 3     
	                1 Bit    Registers := 12    
+---RAMs : 
	              128 Bit	(16 X 8 bit)          RAMs := 1     
+---Muxes : 
	   4 Input    8 Bit        Muxes := 1     
	  21 Input    8 Bit        Muxes := 2     
	   5 Input    6 Bit        Muxes := 1     
	   2 Input    6 Bit        Muxes := 4     
	   2 Input    5 Bit        Muxes := 1     
	   2 Input    4 Bit        Muxes := 2     
	  21 Input    4 Bit        Muxes := 3     
	   2 Input    3 Bit        Muxes := 3     
	  21 Input    2 Bit        Muxes := 1     
	   2 Input    2 Bit        Muxes := 1     
	   4 Input    1 Bit        Muxes := 3     
	   2 Input    1 Bit        Muxes := 4     
	   5 Input    1 Bit        Muxes := 1     
	  21 Input    1 Bit        Muxes := 7     
---------------------------------------------------------------------------------
Finished RTL Component Statistics 
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Start Part Resource Summary
---------------------------------------------------------------------------------
Part Resources:
DSPs: 90 (col length:60)
BRAMs: 100 (col length: RAMB18 60 RAMB36 30)
---------------------------------------------------------------------------------
Finished Part Resource Summary
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Start Cross Boundary and Area Optimization
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Finished Cross Boundary and Area Optimization : Time (s): cpu = 00:00:15 ; elapsed = 00:00:17 . Memory (MB): peak = 1454.020 ; gain = 738.059
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Start ROM, RAM, DSP, Shift Register and Retiming Reporting
---------------------------------------------------------------------------------

ROM: Preliminary Mapping Report
+------------------+------------+---------------+----------------+
|Module Name       | RTL Object | Depth x Width | Implemented As | 
+------------------+------------+---------------+----------------+
|edge_selftest_top | nxt        | 32x5          | LUT            | 
|edge_selftest_top | cfg_we     | 32x1          | LUT            | 
|edge_selftest_top | nxt        | 32x5          | LUT            | 
|edge_selftest_top | cfg_we     | 32x1          | LUT            | 
+------------------+------------+---------------+----------------+


Distributed RAM: Preliminary Mapping Report (see note below)
+------------------+---------------------+-----------+----------------------+---------------+
|Module Name       | RTL Object          | Inference | Size (Depth x Width) | Primitives    | 
+------------------+---------------------+-----------+----------------------+---------------+
|edge_selftest_top | u_dut/u_mem/mem_reg | Implied   | 16 x 8               | RAM16X1S x 8  | 
+------------------+---------------------+-----------+----------------------+---------------+

Note: The table above is a preliminary report that shows the Distributed RAMs at the current stage of the synthesis flow. Some Distributed RAMs may be reimplemented as non Distributed RAM primitives later in the synthesis flow. Multiple instantiated RAMs are reported only once.
---------------------------------------------------------------------------------
Finished ROM, RAM, DSP, Shift Register and Retiming Reporting
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Start Applying XDC Timing Constraints
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Finished Applying XDC Timing Constraints : Time (s): cpu = 00:00:19 ; elapsed = 00:00:21 . Memory (MB): peak = 1581.230 ; gain = 865.270
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Start Timing Optimization
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Finished Timing Optimization : Time (s): cpu = 00:00:20 ; elapsed = 00:00:22 . Memory (MB): peak = 1614.949 ; gain = 898.988
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Start ROM, RAM, DSP, Shift Register and Retiming Reporting
---------------------------------------------------------------------------------

Distributed RAM: Final Mapping Report
+------------------+---------------------+-----------+----------------------+---------------+
|Module Name       | RTL Object          | Inference | Size (Depth x Width) | Primitives    | 
+------------------+---------------------+-----------+----------------------+---------------+
|edge_selftest_top | u_dut/u_mem/mem_reg | Implied   | 16 x 8               | RAM16X1S x 8  | 
+------------------+---------------------+-----------+----------------------+---------------+

---------------------------------------------------------------------------------
Finished ROM, RAM, DSP, Shift Register and Retiming Reporting
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Start Technology Mapping
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Finished Technology Mapping : Time (s): cpu = 00:00:20 ; elapsed = 00:00:22 . Memory (MB): peak = 1614.949 ; gain = 898.988
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Start IO Insertion
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Start Flattening Before IO Insertion
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Finished Flattening Before IO Insertion
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Start Final Netlist Cleanup
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Finished Final Netlist Cleanup
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Finished IO Insertion : Time (s): cpu = 00:00:23 ; elapsed = 00:00:25 . Memory (MB): peak = 1842.379 ; gain = 1126.418
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Start Renaming Generated Instances
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Finished Renaming Generated Instances : Time (s): cpu = 00:00:23 ; elapsed = 00:00:25 . Memory (MB): peak = 1842.379 ; gain = 1126.418
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Start Rebuilding User Hierarchy
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Finished Rebuilding User Hierarchy : Time (s): cpu = 00:00:23 ; elapsed = 00:00:25 . Memory (MB): peak = 1842.379 ; gain = 1126.418
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Start Renaming Generated Ports
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Finished Renaming Generated Ports : Time (s): cpu = 00:00:23 ; elapsed = 00:00:25 . Memory (MB): peak = 1842.379 ; gain = 1126.418
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Start Handling Custom Attributes
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Finished Handling Custom Attributes : Time (s): cpu = 00:00:23 ; elapsed = 00:00:25 . Memory (MB): peak = 1842.379 ; gain = 1126.418
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Start Renaming Generated Nets
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Finished Renaming Generated Nets : Time (s): cpu = 00:00:23 ; elapsed = 00:00:25 . Memory (MB): peak = 1842.379 ; gain = 1126.418
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
Start Writing Synthesis Report
---------------------------------------------------------------------------------

Report BlackBoxes: 
+-+--------------+----------+
| |BlackBox name |Instances |
+-+--------------+----------+
+-+--------------+----------+

Report Cell Usage: 
+------+---------+------+
|      |Cell     |Count |
+------+---------+------+
|1     |BUFG     |     1|
|2     |CARRY4   |     8|
|3     |LUT1     |     1|
|4     |LUT2     |    26|
|5     |LUT3     |    10|
|6     |LUT4     |    12|
|7     |LUT5     |    24|
|8     |LUT6     |    46|
|9     |RAM16X1S |     8|
|10    |FDRE     |   111|
|11    |FDSE     |     3|
|12    |IBUF     |     3|
|13    |OBUF     |     4|
+------+---------+------+
---------------------------------------------------------------------------------
Finished Writing Synthesis Report : Time (s): cpu = 00:00:23 ; elapsed = 00:00:25 . Memory (MB): peak = 1842.379 ; gain = 1126.418
---------------------------------------------------------------------------------
Synthesis finished with 0 errors, 0 critical warnings and 0 warnings.
Synthesis Optimization Runtime : Time (s): cpu = 00:00:15 ; elapsed = 00:00:24 . Memory (MB): peak = 1842.379 ; gain = 1050.203
Synthesis Optimization Complete : Time (s): cpu = 00:00:23 ; elapsed = 00:00:25 . Memory (MB): peak = 1842.379 ; gain = 1126.418
INFO: [Project 1-571] Translating synthesized netlist
Netlist sorting complete. Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.003 . Memory (MB): peak = 1847.094 ; gain = 0.000
INFO: [Netlist 29-17] Analyzing 16 Unisim elements for replacement
INFO: [Netlist 29-28] Unisim Transformation completed in 0 CPU seconds
INFO: [Project 1-570] Preparing netlist for logic optimization
Parsing XDC File [C:/Vivado Projects/P8_MemCtrl/board/edge_artix7.xdc]
Finished Parsing XDC File [C:/Vivado Projects/P8_MemCtrl/board/edge_artix7.xdc]
INFO: [Opt 31-138] Pushed 0 inverter(s) to 0 load pin(s).
Netlist sorting complete. Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.001 . Memory (MB): peak = 1850.594 ; gain = 0.000
INFO: [Project 1-111] Unisim Transformation Summary:
  A total of 8 instances were transformed.
  RAM16X1S => RAM32X1S (RAMS32): 8 instances

Synth Design complete | Checksum: 67cf8b1c
INFO: [Common 17-83] Releasing license: Synthesis
27 Infos, 5 Warnings, 0 Critical Warnings and 0 Errors encountered.
synth_design completed successfully
synth_design: Time (s): cpu = 00:00:26 ; elapsed = 00:00:31 . Memory (MB): peak = 1850.594 ; gain = 1324.367
# opt_design
Command: opt_design
Attempting to get a license for feature 'Implementation' and/or device 'xc7a35t'
INFO: [Common 17-349] Got license for feature 'Implementation' and/or device 'xc7a35t'
Running DRC as a precondition to command opt_design

Starting DRC Task
INFO: [DRC 23-27] Running DRC with 2 threads
INFO: [Project 1-461] DRC finished with 0 Errors
INFO: [Project 1-462] Please refer to the DRC report (report_drc) for more information.

Time (s): cpu = 00:00:01 ; elapsed = 00:00:00.652 . Memory (MB): peak = 1850.594 ; gain = 0.000

Starting Cache Timing Information Task
INFO: [Timing 38-35] Done setting XDC timing constraints.
Ending Cache Timing Information Task | Checksum: 1f09ade68

Time (s): cpu = 00:00:05 ; elapsed = 00:00:05 . Memory (MB): peak = 1850.594 ; gain = 0.000

Starting Logic Optimization Task

Phase 1 Initialization

Phase 1.1 Core Generation And Design Setup
Phase 1.1 Core Generation And Design Setup | Checksum: 1f09ade68

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.003 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 1.2 Setup Constraints And Sort Netlist
Phase 1.2 Setup Constraints And Sort Netlist | Checksum: 1f09ade68

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.004 . Memory (MB): peak = 2006.887 ; gain = 0.000
Phase 1 Initialization | Checksum: 1f09ade68

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.006 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 2 Timer Update And Timing Data Collection

Phase 2.1 Detect if minReqCache needed
Phase 2.1 Detect if minReqCache needed | Checksum: 1f09ade68

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.012 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 2.2 Timer Update
Phase 2.2 Timer Update | Checksum: 1f09ade68

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.021 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 2.3 Timing Data Collection
Phase 2.3 Timing Data Collection | Checksum: 1f09ade68

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.022 . Memory (MB): peak = 2006.887 ; gain = 0.000
Phase 2 Timer Update And Timing Data Collection | Checksum: 1f09ade68

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.023 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 3 Retarget
INFO: [Opt 31-1851] Number of loadless carry chains removed were: 0
INFO: [Opt 31-1834] Total Chains To Be Transformed Were: 0 AND Number of Transformed insts Created are: 0
INFO: [Opt 31-138] Pushed 0 inverter(s) to 0 load pin(s).
INFO: [Opt 31-49] Retargeted 0 cell(s).
Phase 3 Retarget | Checksum: 1f09ade68

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.033 . Memory (MB): peak = 2006.887 ; gain = 0.000
Retarget | Checksum: 1f09ade68
INFO: [Opt 31-389] Phase Retarget created 0 cells and removed 0 cells

Phase 4 Constant propagation
INFO: [Opt 31-138] Pushed 0 inverter(s) to 0 load pin(s).
Phase 4 Constant propagation | Checksum: 1f09ade68

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.036 . Memory (MB): peak = 2006.887 ; gain = 0.000
Constant propagation | Checksum: 1f09ade68
INFO: [Opt 31-389] Phase Constant propagation created 0 cells and removed 0 cells

Phase 5 Sweep
INFO: [Constraints 18-11670] Building netlist checker database with flags, 0x8
Done building netlist checker database: Time (s): cpu = 00:00:00 ; elapsed = 00:00:00 . Memory (MB): peak = 2006.887 ; gain = 0.000
Phase 5 Sweep | Checksum: 233892a5a

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.043 . Memory (MB): peak = 2006.887 ; gain = 0.000
Sweep | Checksum: 233892a5a
INFO: [Opt 31-389] Phase Sweep created 0 cells and removed 0 cells

Phase 6 BUFG optimization
Phase 6 BUFG optimization | Checksum: 233892a5a

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.055 . Memory (MB): peak = 2006.887 ; gain = 0.000
BUFG optimization | Checksum: 233892a5a
INFO: [Opt 31-662] Phase BUFG optimization created 0 cells of which 0 are BUFGs and removed 0 cells.

Phase 7 Shift Register Optimization
INFO: [Opt 31-1064] SRL Remap converted 0 SRLs to 0 registers and converted 0 registers of register chains to 0 SRLs
Phase 7 Shift Register Optimization | Checksum: 233892a5a

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.058 . Memory (MB): peak = 2006.887 ; gain = 0.000
Shift Register Optimization | Checksum: 233892a5a
INFO: [Opt 31-389] Phase Shift Register Optimization created 0 cells and removed 0 cells

Phase 8 Post Processing Netlist
Phase 8 Post Processing Netlist | Checksum: 233892a5a

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.061 . Memory (MB): peak = 2006.887 ; gain = 0.000
Post Processing Netlist | Checksum: 233892a5a
INFO: [Opt 31-389] Phase Post Processing Netlist created 0 cells and removed 0 cells

Phase 9 Finalization

Phase 9.1 Finalizing Design Cores and Updating Shapes
Phase 9.1 Finalizing Design Cores and Updating Shapes | Checksum: 266514580

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.068 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 9.2 Verifying Netlist Connectivity

Starting Connectivity Check Task

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.012 . Memory (MB): peak = 2006.887 ; gain = 0.000
Phase 9.2 Verifying Netlist Connectivity | Checksum: 266514580

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.080 . Memory (MB): peak = 2006.887 ; gain = 0.000
Phase 9 Finalization | Checksum: 266514580

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.081 . Memory (MB): peak = 2006.887 ; gain = 0.000
Opt_design Change Summary
=========================


-------------------------------------------------------------------------------------------------------------------------
|  Phase                        |  #Cells created  |  #Cells Removed  |  #Constrained objects preventing optimizations  |
-------------------------------------------------------------------------------------------------------------------------
|  Retarget                     |               0  |               0  |                                              0  |
|  Constant propagation         |               0  |               0  |                                              0  |
|  Sweep                        |               0  |               0  |                                              0  |
|  BUFG optimization            |               0  |               0  |                                              0  |
|  Shift Register Optimization  |               0  |               0  |                                              0  |
|  Post Processing Netlist      |               0  |               0  |                                              0  |
-------------------------------------------------------------------------------------------------------------------------


Ending Logic Optimization Task | Checksum: 266514580

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.082 . Memory (MB): peak = 2006.887 ; gain = 0.000

Starting Power Optimization Task
INFO: [Pwropt 34-132] Skipping clock gating for clocks with a period < 2.00 ns.
Ending Power Optimization Task | Checksum: 266514580

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.018 . Memory (MB): peak = 2006.887 ; gain = 0.000

Starting Final Cleanup Task
Ending Final Cleanup Task | Checksum: 266514580

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.001 . Memory (MB): peak = 2006.887 ; gain = 0.000
Netlist sorting complete. Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.001 . Memory (MB): peak = 2006.887 ; gain = 0.000
INFO: [Common 17-83] Releasing license: Implementation
20 Infos, 0 Warnings, 0 Critical Warnings and 0 Errors encountered.
opt_design completed successfully
opt_design: Time (s): cpu = 00:00:09 ; elapsed = 00:00:09 . Memory (MB): peak = 2006.887 ; gain = 156.293
# place_design
Command: place_design
Attempting to get a license for feature 'Implementation' and/or device 'xc7a35t'
INFO: [Common 17-349] Got license for feature 'Implementation' and/or device 'xc7a35t'
INFO: [Common 17-83] Releasing license: Implementation
INFO: [DRC 23-27] Running DRC with 2 threads
INFO: [Vivado_Tcl 4-198] DRC finished with 0 Errors
INFO: [Vivado_Tcl 4-199] Please refer to the DRC report (report_drc) for more information.
INFO: [Timing 38-35] Done setting XDC timing constraints.
Running DRC as a precondition to command place_design
INFO: [DRC 23-27] Running DRC with 2 threads
INFO: [Vivado_Tcl 4-198] DRC finished with 0 Errors
INFO: [Vivado_Tcl 4-199] Please refer to the DRC report (report_drc) for more information.
INFO: [Place 30-611] Multithreading enabled for place_design using a maximum of 2 CPUs

Starting Placer Task

Phase 1 Placer Initialization

Phase 1.1 Placer Initialization Netlist Sorting
Netlist sorting complete. Time (s): cpu = 00:00:00 ; elapsed = 00:00:00 . Memory (MB): peak = 2006.887 ; gain = 0.000
Phase 1.1 Placer Initialization Netlist Sorting | Checksum: 1f14f9147

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.004 . Memory (MB): peak = 2006.887 ; gain = 0.000
Netlist sorting complete. Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.001 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 1.2 IO Placement/ Clock Placement/ Build Placer Device
Phase 1.2 IO Placement/ Clock Placement/ Build Placer Device | Checksum: 131dad9c3

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.210 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 1.3 Build Placer Netlist Model
Phase 1.3 Build Placer Netlist Model | Checksum: 1a63242af

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.303 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 1.4 Constrain Clocks/Macros
Phase 1.4 Constrain Clocks/Macros | Checksum: 1a63242af

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.306 . Memory (MB): peak = 2006.887 ; gain = 0.000
Phase 1 Placer Initialization | Checksum: 1a63242af

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.315 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 2 Global Placement

Phase 2.1 Floorplanning
Phase 2.1 Floorplanning | Checksum: 16b814126

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.350 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 2.2 Update Timing before SLR Path Opt
Phase 2.2 Update Timing before SLR Path Opt | Checksum: 20b94f5c9

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.375 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 2.3 Post-Processing in Floorplanning
Phase 2.3 Post-Processing in Floorplanning | Checksum: 20b94f5c9

Time (s): cpu = 00:00:00 ; elapsed = 00:00:00.378 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 2.4 Global Place Phase1
Phase 2.4 Global Place Phase1 | Checksum: 1e0ebc702

Time (s): cpu = 00:00:01 ; elapsed = 00:00:00.680 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 2.5 Global Place Phase2

Phase 2.5.1 UpdateTiming Before Physical Synthesis
Phase 2.5.1 UpdateTiming Before Physical Synthesis | Checksum: 1e0ebc702

Time (s): cpu = 00:00:01 ; elapsed = 00:00:00.704 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 2.5.2 Physical Synthesis In Placer
INFO: [Physopt 32-1035] Found 0 LUTNM shape to break, 3 LUT instances to create LUTNM shape
INFO: [Physopt 32-1044] Break lutnm for timing: one critical 0, two critical 0, total 0, new lutff created 0
INFO: [Physopt 32-1138] End 1 Pass. Optimized 1 net or LUT. Breaked 0 LUT, combined 1 existing LUT and moved 0 existing LUT
INFO: [Physopt 32-65] No nets found for high-fanout optimization.
INFO: [Physopt 32-232] Optimized 0 net. Created 0 new instance.
INFO: [Physopt 32-775] End 1 Pass. Optimized 0 net or cell. Created 0 new cell, deleted 0 existing cell and moved 0 existing cell
INFO: [Physopt 32-670] No setup violation found.  DSP Register Optimization was not performed.
INFO: [Physopt 32-670] No setup violation found.  Shift Register to Pipeline Optimization was not performed.
INFO: [Physopt 32-670] No setup violation found.  Shift Register Optimization was not performed.
INFO: [Physopt 32-670] No setup violation found.  BRAM Register Optimization was not performed.
INFO: [Physopt 32-670] No setup violation found.  URAM Register Optimization was not performed.
INFO: [Physopt 32-949] No candidate nets found for dynamic/static region interface net replication
INFO: [Physopt 32-775] End 1 Pass. Optimized 0 net or cell. Created 0 new cell, deleted 0 existing cell and moved 0 existing cell
Netlist sorting complete. Time (s): cpu = 00:00:00 ; elapsed = 00:00:00 . Memory (MB): peak = 2006.887 ; gain = 0.000

Summary of Physical Synthesis Optimizations
============================================


-----------------------------------------------------------------------------------------------------------------------------------------------------------
|  Optimization                                     |  Added Cells  |  Removed Cells  |  Optimized Cells/Nets  |  Dont Touch  |  Iterations  |  Elapsed   |
-----------------------------------------------------------------------------------------------------------------------------------------------------------
|  LUT Combining                                    |            0  |              1  |                     1  |           0  |           1  |  00:00:00  |
|  Retime                                           |            0  |              0  |                     0  |           0  |           1  |  00:00:00  |
|  Very High Fanout                                 |            0  |              0  |                     0  |           0  |           1  |  00:00:00  |
|  DSP Register                                     |            0  |              0  |                     0  |           0  |           0  |  00:00:00  |
|  Shift Register to Pipeline                       |            0  |              0  |                     0  |           0  |           0  |  00:00:00  |
|  Shift Register                                   |            0  |              0  |                     0  |           0  |           0  |  00:00:00  |
|  BRAM Register                                    |            0  |              0  |                     0  |           0  |           0  |  00:00:00  |
|  URAM Register                                    |            0  |              0  |                     0  |           0  |           0  |  00:00:00  |
|  Dynamic/Static Region Interface Net Replication  |            0  |              0  |                     0  |           0  |           1  |  00:00:00  |
|  Total                                            |            0  |              1  |                     1  |           0  |           4  |  00:00:00  |
-----------------------------------------------------------------------------------------------------------------------------------------------------------


Phase 2.5.2 Physical Synthesis In Placer | Checksum: 22ae8d82f

Time (s): cpu = 00:00:01 ; elapsed = 00:00:00.812 . Memory (MB): peak = 2006.887 ; gain = 0.000
Phase 2.5 Global Place Phase2 | Checksum: 24976e70e

Time (s): cpu = 00:00:01 ; elapsed = 00:00:00.854 . Memory (MB): peak = 2006.887 ; gain = 0.000
Phase 2 Global Placement | Checksum: 24976e70e

Time (s): cpu = 00:00:01 ; elapsed = 00:00:00.856 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 3 Detail Placement

Phase 3.1 Commit Multi Column Macros
Phase 3.1 Commit Multi Column Macros | Checksum: 2553f34b1

Time (s): cpu = 00:00:01 ; elapsed = 00:00:00.883 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 3.2 Commit Most Macros & LUTRAMs
Phase 3.2 Commit Most Macros & LUTRAMs | Checksum: 19e83be9d

Time (s): cpu = 00:00:01 ; elapsed = 00:00:00.930 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 3.3 Area Swap Optimization
Phase 3.3 Area Swap Optimization | Checksum: 14df1b9c2

Time (s): cpu = 00:00:01 ; elapsed = 00:00:00.935 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 3.4 Pipeline Register Optimization
Phase 3.4 Pipeline Register Optimization | Checksum: 1e86f834d

Time (s): cpu = 00:00:01 ; elapsed = 00:00:00.936 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 3.5 Small Shape Detail Placement
Phase 3.5 Small Shape Detail Placement | Checksum: 1cffb2cfc

Time (s): cpu = 00:00:01 ; elapsed = 00:00:01 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 3.6 Re-assign LUT pins
Phase 3.6 Re-assign LUT pins | Checksum: 1f33e345f

Time (s): cpu = 00:00:01 ; elapsed = 00:00:01 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 3.7 Pipeline Register Optimization
Phase 3.7 Pipeline Register Optimization | Checksum: 24bbc6ed4

Time (s): cpu = 00:00:01 ; elapsed = 00:00:01 . Memory (MB): peak = 2006.887 ; gain = 0.000
Phase 3 Detail Placement | Checksum: 24bbc6ed4

Time (s): cpu = 00:00:01 ; elapsed = 00:00:01 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 4 Post Placement Optimization and Clean-Up

Phase 4.1 Post Commit Optimization
INFO: [Timing 38-35] Done setting XDC timing constraints.

Phase 4.1.1 Post Placement Optimization
Post Placement Optimization Initialization | Checksum: 21acfeb07

Phase 4.1.1.1 BUFG Insertion

Starting Physical Synthesis Task

Phase 1 Physical Synthesis Initialization
INFO: [Physopt 32-721] Multithreading enabled for phys_opt_design using a maximum of 2 CPUs
INFO: [Physopt 32-619] Estimated Timing Summary | WNS=15.445 | TNS=0.000 |
Phase 1 Physical Synthesis Initialization | Checksum: 148508c6d

Time (s): cpu = 00:00:01 ; elapsed = 00:00:00.009 . Memory (MB): peak = 2006.887 ; gain = 0.000
INFO: [Place 46-56] BUFG insertion identified 0 candidate nets. Inserted BUFG: 0, Replicated BUFG Driver: 0, Skipped due to Placement/Routing Conflicts: 0, Skipped due to Timing Degradation: 0, Skipped due to netlist editing failed: 0.
Ending Physical Synthesis Task | Checksum: 1fc4dc643

Time (s): cpu = 00:00:01 ; elapsed = 00:00:00.012 . Memory (MB): peak = 2006.887 ; gain = 0.000
Phase 4.1.1.1 BUFG Insertion | Checksum: 21acfeb07

Time (s): cpu = 00:00:02 ; elapsed = 00:00:01 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 4.1.1.2 Post Placement Timing Optimization
INFO: [Place 30-746] Post Placement Timing Summary WNS=15.445. For the most accurate timing information please run report_timing.
Phase 4.1.1.2 Post Placement Timing Optimization | Checksum: 24e01a438

Time (s): cpu = 00:00:02 ; elapsed = 00:00:01 . Memory (MB): peak = 2006.887 ; gain = 0.000

Time (s): cpu = 00:00:02 ; elapsed = 00:00:01 . Memory (MB): peak = 2006.887 ; gain = 0.000
Phase 4.1 Post Commit Optimization | Checksum: 24e01a438

Time (s): cpu = 00:00:02 ; elapsed = 00:00:01 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 4.2 Post Placement Cleanup
Phase 4.2 Post Placement Cleanup | Checksum: 24e01a438

Time (s): cpu = 00:00:02 ; elapsed = 00:00:01 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 4.3 Placer Reporting

Phase 4.3.1 Print Estimated Congestion
INFO: [Place 30-612] Post-Placement Estimated Congestion 
 ____________________________________________________
|           | Global Congestion | Short Congestion  |
| Direction | Region Size       | Region Size       |
|___________|___________________|___________________|
|      North|                1x1|                1x1|
|___________|___________________|___________________|
|      South|                1x1|                1x1|
|___________|___________________|___________________|
|       East|                1x1|                1x1|
|___________|___________________|___________________|
|       West|                1x1|                1x1|
|___________|___________________|___________________|

Phase 4.3.1 Print Estimated Congestion | Checksum: 24e01a438

Time (s): cpu = 00:00:02 ; elapsed = 00:00:01 . Memory (MB): peak = 2006.887 ; gain = 0.000
Phase 4.3 Placer Reporting | Checksum: 24e01a438

Time (s): cpu = 00:00:02 ; elapsed = 00:00:01 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 4.4 Final Placement Cleanup
Netlist sorting complete. Time (s): cpu = 00:00:00 ; elapsed = 00:00:00 . Memory (MB): peak = 2006.887 ; gain = 0.000

Time (s): cpu = 00:00:02 ; elapsed = 00:00:01 . Memory (MB): peak = 2006.887 ; gain = 0.000
Phase 4 Post Placement Optimization and Clean-Up | Checksum: 215b658d9

Time (s): cpu = 00:00:02 ; elapsed = 00:00:01 . Memory (MB): peak = 2006.887 ; gain = 0.000
Ending Placer Task | Checksum: 14f00c6ab

Time (s): cpu = 00:00:02 ; elapsed = 00:00:01 . Memory (MB): peak = 2006.887 ; gain = 0.000
29 Infos, 0 Warnings, 0 Critical Warnings and 0 Errors encountered.
place_design completed successfully
# route_design
Command: route_design
Attempting to get a license for feature 'Implementation' and/or device 'xc7a35t'
INFO: [Common 17-349] Got license for feature 'Implementation' and/or device 'xc7a35t'


Starting Routing Task
INFO: [Route 35-254] Multithreading enabled for route_design using a maximum of 2 CPUs

Phase 1 Build RT Design
Checksum: PlaceDB: a6ffb67c ConstDB: 0 ShapeSum: 77fb3d8 RouteDB: a0815c57
Post Restoration Checksum: NetGraph: e33ab800 | NumContArr: 16f228c6 | Constraints: c2a8fa9d | Timing: c2a8fa9d
Phase 1 Build RT Design | Checksum: 27f7ed600

Time (s): cpu = 00:00:14 ; elapsed = 00:00:13 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 2 Router Initialization

Phase 2.1 Fix Topology Constraints
Phase 2.1 Fix Topology Constraints | Checksum: 27f7ed600

Time (s): cpu = 00:00:14 ; elapsed = 00:00:13 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 2.2 Pre Route Cleanup
Phase 2.2 Pre Route Cleanup | Checksum: 27f7ed600

Time (s): cpu = 00:00:14 ; elapsed = 00:00:14 . Memory (MB): peak = 2006.887 ; gain = 0.000
 Number of Nodes with overlaps = 0

Phase 2.3 Update Timing
Phase 2.3 Update Timing | Checksum: 22e229ad2

Time (s): cpu = 00:00:14 ; elapsed = 00:00:14 . Memory (MB): peak = 2006.887 ; gain = 0.000
INFO: [Route 35-416] Intermediate Timing Summary | WNS=15.394 | TNS=0.000  | WHS=-0.146 | THS=-7.057 |


Phase 2.4 Soft Constraint Pins - Fast Budgeting
Phase 2.4 Soft Constraint Pins - Fast Budgeting | Checksum: 272f69c12

Time (s): cpu = 00:00:14 ; elapsed = 00:00:14 . Memory (MB): peak = 2006.887 ; gain = 0.000

Router Utilization Summary
  Global Vertical Routing Utilization    = 0 %
  Global Horizontal Routing Utilization  = 0 %
  Routable Net Status*
  *Does not include unroutable nets such as driverless and loadless.
  Run report_route_status for detailed report.
  Number of Failed Nets               = 185
    (Failed Nets is the sum of unrouted and partially routed nets)
  Number of Unrouted Nets             = 185
  Number of Partially Routed Nets     = 0
  Number of Node Overlaps             = 0

Phase 2 Router Initialization | Checksum: 272f69c12

Time (s): cpu = 00:00:14 ; elapsed = 00:00:14 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 3 Global Routing
Phase 3 Global Routing | Checksum: 272f69c12

Time (s): cpu = 00:00:14 ; elapsed = 00:00:14 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 4 Initial Routing

Phase 4.1 Initial Net Routing Pass
Phase 4.1 Initial Net Routing Pass | Checksum: 1bdda0451

Time (s): cpu = 00:00:14 ; elapsed = 00:00:14 . Memory (MB): peak = 2006.887 ; gain = 0.000
Phase 4 Initial Routing | Checksum: 1bdda0451

Time (s): cpu = 00:00:14 ; elapsed = 00:00:14 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 5 Rip-up And Reroute

Phase 5.1 Global Iteration 0
 Number of Nodes with overlaps = 16
 Number of Nodes with overlaps = 0
INFO: [Route 35-416] Intermediate Timing Summary | WNS=15.703 | TNS=0.000  | WHS=N/A    | THS=N/A    |

Phase 5.1 Global Iteration 0 | Checksum: 1294a8734

Time (s): cpu = 00:00:15 ; elapsed = 00:00:14 . Memory (MB): peak = 2006.887 ; gain = 0.000
Phase 5 Rip-up And Reroute | Checksum: 1294a8734

Time (s): cpu = 00:00:15 ; elapsed = 00:00:14 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 6 Delay and Skew Optimization

Phase 6.1 Delay CleanUp

Phase 6.1.1 Update Timing
Phase 6.1.1 Update Timing | Checksum: 19f98ee31

Time (s): cpu = 00:00:15 ; elapsed = 00:00:14 . Memory (MB): peak = 2006.887 ; gain = 0.000
INFO: [Route 35-416] Intermediate Timing Summary | WNS=15.324 | TNS=0.000  | WHS=N/A    | THS=N/A    |

Phase 6.1 Delay CleanUp | Checksum: 19f98ee31

Time (s): cpu = 00:00:15 ; elapsed = 00:00:14 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 6.2 Clock Skew Optimization
Phase 6.2 Clock Skew Optimization | Checksum: 19f98ee31

Time (s): cpu = 00:00:15 ; elapsed = 00:00:14 . Memory (MB): peak = 2006.887 ; gain = 0.000
Phase 6 Delay and Skew Optimization | Checksum: 19f98ee31

Time (s): cpu = 00:00:15 ; elapsed = 00:00:14 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 7 Post Hold Fix

Phase 7.1 Hold Fix Iter
INFO: [Route 35-416] Intermediate Timing Summary | WNS=15.324 | TNS=0.000  | WHS=0.079  | THS=0.000  |

Phase 7.1 Hold Fix Iter | Checksum: 1d1b23778

Time (s): cpu = 00:00:15 ; elapsed = 00:00:14 . Memory (MB): peak = 2006.887 ; gain = 0.000
Phase 7 Post Hold Fix | Checksum: 1d1b23778

Time (s): cpu = 00:00:15 ; elapsed = 00:00:14 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 8 Route finalize

Router Utilization Summary
  Global Vertical Routing Utilization    = 0.0255122 %
  Global Horizontal Routing Utilization  = 0.0311036 %
  Routable Net Status*
  *Does not include unroutable nets such as driverless and loadless.
  Run report_route_status for detailed report.
  Number of Failed Nets               = 0
    (Failed Nets is the sum of unrouted and partially routed nets)
  Number of Unrouted Nets             = 0
  Number of Partially Routed Nets     = 0
  Number of Node Overlaps             = 0

Phase 8 Route finalize | Checksum: 1d1b23778

Time (s): cpu = 00:00:15 ; elapsed = 00:00:14 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 9 Verifying routed nets

 Verification completed successfully
Phase 9 Verifying routed nets | Checksum: 1d1b23778

Time (s): cpu = 00:00:15 ; elapsed = 00:00:14 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 10 Depositing Routes
Phase 10 Depositing Routes | Checksum: 204b17676

Time (s): cpu = 00:00:15 ; elapsed = 00:00:14 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 11 Post Process Routing
Phase 11 Post Process Routing | Checksum: 204b17676

Time (s): cpu = 00:00:15 ; elapsed = 00:00:14 . Memory (MB): peak = 2006.887 ; gain = 0.000

Phase 12 Post Router Timing
INFO: [Route 35-57] Estimated Timing Summary | WNS=15.324 | TNS=0.000  | WHS=0.079  | THS=0.000  |

INFO: [Route 35-327] The final timing numbers are based on the router estimated timing analysis. For a complete and accurate timing signoff, please run report_timing_summary.
Phase 12 Post Router Timing | Checksum: 204b17676

Time (s): cpu = 00:00:15 ; elapsed = 00:00:14 . Memory (MB): peak = 2006.887 ; gain = 0.000
Total Elapsed time in route_design: 14.066 secs

Phase 13 Post-Route Event Processing
Phase 13 Post-Route Event Processing | Checksum: efcb8df3

Time (s): cpu = 00:00:15 ; elapsed = 00:00:14 . Memory (MB): peak = 2006.887 ; gain = 0.000
INFO: [Route 35-16] Router Completed Successfully
Ending Routing Task | Checksum: efcb8df3

Time (s): cpu = 00:00:15 ; elapsed = 00:00:14 . Memory (MB): peak = 2006.887 ; gain = 0.000

Routing Is Done.
INFO: [Common 17-83] Releasing license: Implementation
10 Infos, 0 Warnings, 0 Critical Warnings and 0 Errors encountered.
route_design completed successfully
route_design: Time (s): cpu = 00:00:15 ; elapsed = 00:00:14 . Memory (MB): peak = 2006.887 ; gain = 0.000
# report_utilization    -file out/utilization.rpt
# report_timing_summary -file out/timing_summary.rpt
INFO: [Timing 38-91] UpdateTimingParams: Speed grade: -1, Delay Type: min_max.
INFO: [Timing 38-191] Multithreading enabled for timing update using a maximum of 2 CPUs
# report_drc            -file out/drc.rpt
Command: report_drc -file out/drc.rpt
INFO: [IP_Flow 19-234] Refreshing IP repositories
INFO: [IP_Flow 19-1704] No user IP repositories specified
INFO: [IP_Flow 19-2313] Loaded Vivado IP repository 'C:/Xilinx/2025.2/Vivado/data/ip'.
INFO: [DRC 23-27] Running DRC with 2 threads
INFO: [Vivado_Tcl 2-168] The results of DRC are in file C:/Vivado Projects/P8_MemCtrl/board/out/drc.rpt.
report_drc completed successfully
# report_power          -file out/power.rpt
Command: report_power -file out/power.rpt
Running Vector-less Activity Propagation...

Finished Running Vector-less Activity Propagation
0 Infos, 0 Warnings, 0 Critical Warnings and 0 Errors encountered.
report_power completed successfully
# report_timing         -max_paths 5 -file out/critical_paths.rpt
INFO: [Timing 38-91] UpdateTimingParams: Speed grade: -1, Delay Type: max.
INFO: [Timing 38-191] Multithreading enabled for timing update using a maximum of 2 CPUs
INFO: [Timing 38-78] ReportTimingParams: -max_paths 5 -nworst 1 -delay_type max -sort_by slack.
# write_bitstream -force out/edge_selftest.bit
Command: write_bitstream -force out/edge_selftest.bit
Attempting to get a license for feature 'Implementation' and/or device 'xc7a35t'
INFO: [Common 17-349] Got license for feature 'Implementation' and/or device 'xc7a35t'
Running DRC as a precondition to command write_bitstream
INFO: [IP_Flow 19-1839] IP Catalog is up to date.
INFO: [DRC 23-27] Running DRC with 2 threads
INFO: [Vivado 12-3199] DRC finished with 0 Errors
INFO: [Vivado 12-3200] Please refer to the DRC report (report_drc) for more information.
Integrating Hard IP ELF/MEM with the PDI.
INFO: [Designutils 20-2272] Running write_bitstream with 2 threads.
Loading data files...
Loading site data...
Loading route data...
Processing options...
Creating bitmap...
Creating bitstream...
Writing bitstream out/edge_selftest.bit...
INFO: [Vivado 12-1842] Bitgen Completed Successfully.
INFO: [Common 17-83] Releasing license: Implementation
8 Infos, 0 Warnings, 0 Critical Warnings and 0 Errors encountered.
write_bitstream completed successfully
write_bitstream: Time (s): cpu = 00:00:09 ; elapsed = 00:00:08 . Memory (MB): peak = 2196.648 ; gain = 189.762
# puts "Bitstream: [pwd]/out/edge_selftest.bit"
Bitstream: C:/Vivado Projects/P8_MemCtrl/board/out/edge_selftest.bit
INFO: [Common 17-206] Exiting Vivado at Fri Nov 20 12:10:43 2026...
```
