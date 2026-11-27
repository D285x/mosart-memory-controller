#!/bin/sh
# Runs all formal tasks. Needs yosys, sby and z3 (Linux, macOS or WSL).
#   sudo apt install yosys z3      and SymbiYosys from https://github.com/YosysHQ/sby
# Expected: every task finishes with PASS.
#   fsm   bmc      : all FSM properties hold for every input sequence up to 30 cycles
#   fsm   prove    : the same properties proven for all time by k-induction
#   fsm   latency  : exact access latency 2 + N proven for a constant configuration
#   fsm   cover    : every interesting behaviour is reachable (the properties are not vacuous)
#   cfg   bmc      : configuration registers match the register-map specification (25 cycles)
#   cfg   cover    : saturation, write-one-to-clear and event-with-clear are reachable
#   top   cover    : the end-to-end consistency check is reachable
#   top   bmc      : write-then-read returns the written data through the whole controller
#                    (small and full-size variants; these are slow, minutes to tens of minutes)
set -e
cd "$(dirname "$0")"
sby -f fsm.sby bmc prove latency cover
sby -f cfg.sby bmc cover
sby -f top.sby cover
sby -f top_small.sby bmc
sby -f top.sby bmc
