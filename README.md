# Programmable Memory Controller (MOSART Project 8)

Shaun Praneeth Raj, Anurag University

A synchronous controller for a 16 x 8 on-chip memory, written in Verilog-2005.
A six-state Moore FSM (IDLE, READ, WRITE, WAIT, DONE, ERROR) handles one
request at a time, inserts 0 to 7 programmable wait states and reports
`busy`, `ready` and `error`. A small register bank sets enable, write
protect, wait states and an address limit, and keeps sticky error flags
(collision, out of range, write-protect violation, request while busy).

## Layout

| Path | Contents |
|---|---|
| `rtl/` | `mem_ctrl_top`, `mem_ctrl_fsm`, `cfg_regs`, `sync_mem` |
| `tb/` | Self-checking testbench with a behavioural reference model |
| `vivado/` | `mem_ctrl.xdc` (100 MHz), `run_sim.tcl`, `run_synth.tcl` |
| `sim/` | Icarus Verilog log |
| `synth/` | Yosys `synth_xilinx` script and cell report |
| `report/` | Project report (LaTeX source and PDF) |

## Register map

| Addr | Name | Bits | Access | Reset |
|---|---|---|---|---|
| 0x0 | CTRL | [0] EN, [1] WP | RW | EN = 1 |
| 0x1 | WAIT | [2:0] wait states | RW | 0 |
| 0x2 | LIMIT | [4:0] valid words | RW | 16 |
| 0x3 | STATUS | [3:0] COLL, RANGE, WPV, OVR (W1C), [4] BUSY (RO) | | 0 |

## Simulation

```
iverilog -g2005 -o tb.vvp rtl/*.v tb/tb_mem_ctrl.v && vvp tb.vvp
```

Ten test groups, including a 500-access constrained-random regression:
3356 checks, 0 errors (`sim/sim_log.txt`).

In Vivado: add `rtl/` as design sources, `tb/tb_mem_ctrl.v` as the
simulation source (top `tb_mem_ctrl`), and `vivado/mem_ctrl.xdc`, then
Run Behavioral Simulation. Batch flow:

```
cd vivado
vivado -mode batch -source run_sim.tcl
vivado -mode batch -source run_synth.tcl
```

## Synthesis

Yosys 0.33, `synth_xilinx -family xc7` (target xc7a35tcpg236-1):
59 LUTs, 1 RAM32M (the 16 x 8 array as distributed RAM), 44 flip-flops,
7 MUXF7, 3 MUXF8, 1 CARRY4. The deepest register-to-register path is six
logic levels (address-limit compare into the IDLE next-state decision).
