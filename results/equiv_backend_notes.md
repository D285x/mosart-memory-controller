# Equivalence check for the extension designs

The memory controller study classifies surviving mutants with a Yosys SAT miter (`mutation/mutate.py`, stage `equiv`: `miter -equiv`, then `sat -seq 24`, reset in the first cycle, all-zero initial state).

That construction could not be reused unchanged for the two extension designs:

1. **Run time.** The built-in `sat` command grows exponentially with depth on the FIFO (5 s at depth 12, 75 s at 16, over 300 s at 20). The UART needs depth 80, because two received frames at prescale 1 take more than 64 cycles.
2. **UART sub-modules not compared.** On the UART top level, the miter built by `chparam`, `proc` and `flatten` without `hierarchy -check` reported mutants inside `uart_tx` as equivalent. These included U05 and U03, which a direct side-by-side comparison distinguishes within 1 and 32 cycles. Adding `hierarchy -check` fixed U03 but not U05.

## Replacement

`mutation/flow.py` now uses an explicit miter for each design (`designs/<name>/equiv/port_miter.sv`). The miter instantiates the original and the mutant side by side and drives them with the same free inputs. It forces reset in the first cycle and asserts that every output is equal in every later cycle. SymbiYosys checks it in bounded mode with yices. The conventions match `mutate.py`:

- reset is applied in the first cycle;
- registers without an initial value start at zero (`setundef -undriven -init -zero`);
- outputs are not compared in the first cycle;
- later resets are free.

## Cross-check on the memory controller

The same SymbiYosys route was run on the 18 memory controller mutants that survived simulation v1, with a port miter for `mem_ctrl_top` (`designs/memctrl_xcheck/`, depth 24, DATA_W 2, ADDR_W 3). Run it with `python3 mutation/xcheck_memctrl.py`; the results are in `results/equiv_backend_crosscheck.json`.

| Original classification (mutate.py) | Mutants | SymbiYosys miter |
|---|---|---|
| EQUIVALENT_24 | 13 | 13 equivalent |
| DISTINGUISHABLE | 2 | 2 distinguishable |
| INITIAL_STATE (power-up value of the memory array) | 3 | 3 distinguishable |

The 15 mutants that the original miter could judge get the same verdict. The memory controller results in the paper therefore stand. The three power-up mutants, which the original miter could not judge, come out distinguishable because the new miter honours initial values. This agrees with simulation v2 killing them through test D1b.

## Specification miter

A port-level difference is not always a specification violation. Examples are the FIFO's `o_data` while the FIFO is empty, or the UART's `m_axis_tdata` while `m_axis_tvalid` is low. For every survivor that the port miter distinguishes, `equiv/spec_miter.sv` compares only the specified behaviour, and `equiv/spec_miter_powerup.sv` does the same from power-up for mutants that change an initial value. Mutants that differ only in unspecified behaviour are counted as equivalent (class SPEC or PU in the results). Two UART mutants that both miters distinguish, but that still meet the specification, are listed with the argument in `designs/uart/design.py` (`ARGUED`). They are reported separately, and the scores are also given with them counted as non-equivalent.
