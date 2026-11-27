# MOSART P8 Programmable Memory Controller

An 8-bit programmable memory controller written in Verilog, with an AXI4-Lite wrapper, a verification suite (simulation, functional coverage, mutation analysis, formal proofs), an on-board self-test and latency measurement for the EDGE Artix-7 board (xc7a35tftg256-1, 50 MHz), and a parameter sweep flow for Fmax, area and power.

## Architecture

| Module | Function |
|---|---|
| `rtl/mem_ctrl_top.v` | Top level; parameters `DATA_W` and `ADDR_W` |
| `rtl/cfg_regs.v` | Configuration registers: enable, write protect, wait states (0 to 7), address limit, sticky status flags |
| `rtl/mem_ctrl_fsm.v` | Six-state Moore FSM that sequences accesses and validates requests |
| `rtl/sync_mem.v` | Synchronous memory model (16 x 8 by default) |
| `rtl/axil_mem_ctrl.v` | AXI4-Lite slave wrapper (OKAY, SLVERR, DECERR responses) |

Timing: an accepted access completes in 2 + N cycles from request to ready, where N is the configured wait-state count. Back-to-back accesses take 3 + N cycles each. A rejected request (collision, out of range, write protected) takes 1 cycle. Through the AXI4-Lite wrapper the response latency is 5 + N cycles.

## Layout

| Folder | Content |
|---|---|
| `rtl/` | Design sources |
| `tb/` | Core testbench, parameterised testbench, coverage monitor, AXI4-Lite testbench |
| `mutation/` | Mutation flow: generator, driver, report (172 mutants); `flow.py`, `oplib.py` and `flow_report.py` run the same flow on `designs/` |
| `formal/` | SymbiYosys property files and run script |
| `board/` | Self-test and latency designs, constraints, build and programming scripts (`legacy/` holds the scripts of the first board run) |
| `sweep/` | Out-of-context synthesis sweep over data width, address width, clock period and placer directive |
| `tools/` | Wait-state and throughput model |
| `results/` | Hardware results, verification logs, mutation, formal and timing-model summaries |
| `designs/` | Extension study: third-party FIFO (`sfifo`) and UART (`uart`), each with RTL, testbenches, formal properties, miters and `design.py` |
| `paper/` | Working draft |
| `run_all.bat` | Single entry point on Windows |

## How to run

Windows with Vivado 2025.2 (`C:\Xilinx\2025.2\Vivado\bin`):

| Command | Action |
|---|---|
| `run_all.bat sim` | xsim runs of the testbenches |
| `run_all.bat build` | Builds both bitstreams and extracts statistics |
| `run_all.bat program self` | Programs the self-test design |
| `run_all.bat program lat` | Programs the latency measurement design |
| `run_all.bat` | Simulation, build and statistics |
| `sweep\run_sweep.bat quick` | Reduced sweep (3 configurations, 4 periods, 2 placer directives) |
| `sweep\run_sweep.bat` | Full sweep: 12 configurations at 4.0 ns, and 8 clock periods times 5 placer directives for the 8 x 4 configuration |

Linux (needs `iverilog`, `yosys`, `sby`, `z3`):

| Command | Action |
|---|---|
| `bash formal/run_formal.sh` | Formal tasks (the top-level bounded check takes minutes to tens of minutes) |
| `python3 mutation/run_mutation.py` | Full mutation flow, about 40 minutes on two cores |
| `python3 tools/wait_states.py` | Wait-state and throughput table |
| `python3 mutation/flow.py sfifo all` | Mutation flow on the FIFO, about 2 minutes on two cores (needs yices as well) |
| `python3 mutation/flow.py uart all` | Mutation flow on the UART, about 3 hours on two cores (the 70-cycle formal task dominates) |

Icarus example for the AXI4-Lite wrapper:
`iverilog -g2012 -P tb_axil_mem_ctrl.DATA_W=16 -P tb_axil_mem_ctrl.ADDR_W=5 -o axil tb/tb_axil_mem_ctrl.v rtl/*.v && vvp axil`

## Latency design controls

Push button `pb[4]` (centre) restarts the measurement. `sw[2:0]` selects N. `sw[4:3]` selects the quantity: 0 single read latency, 1 single write latency, 2 total time for 16 reads, 3 average per read. The value is shown on the seven-segment display and on `led[15:8]`. `led[0]` is PASS, `led[1]` FAIL, `led[2]` DONE, `led[3]` heartbeat.

## Results so far

| Item | Status |
|---|---|
| Self-test on the EDGE board (both MODE settings) | Passed, `results/Hardware Results.md` (103 LUTs, 114 FFs, WNS +15.3 ns at 50 MHz) |
| Core and parameterised testbenches | 0 errors, 47 of 47 coverage bins in 8 configurations |
| AXI4-Lite wrapper | 0 errors in 8 configurations |
| Mutation analysis | 172 mutants; 159 of 159 non-equivalent killed by simulation, 153 of 159 by formal checks |
| Formal, FSM | Proven by k-induction; exact latency; cover |
| Formal, configuration registers and top level | Bounded checks (25 and 24 cycles) passed |

Details: `results/verification_summary.md`.

Extension to two third-party designs (same flow): `results/extension_summary.md`, with per-design results in `results/sfifo/` and `results/uart/`.

## Status of items not yet run

The following were written and checked at script or simulator level only, and need execution on the Windows machine with Vivado: xsim runs of the new testbenches, the build of the latency bitstream and its operation on the board, `board\build.tcl`, `run_all.bat` end to end, the parameter sweep with placer directives, and implementation of the AXI4-Lite wrapper. Their results are not part of this repository yet.
