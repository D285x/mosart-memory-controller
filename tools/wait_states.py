#!/usr/bin/env python3
"""Map a memory device access time to the controller wait-state setting.

Timing model (documented assumption): after the memory strobe the device needs
tACC to return data, and the controller gives it N + 1 clock cycles before the
transaction completes, so  N = ceil(tACC / Tclk) - 1,  limited to 0..7 by the
3-bit WAIT register. An accepted access completes 2 + N cycles after the
request; back-to-back accesses are spaced 3 + N cycles apart.

  python3 tools/wait_states.py                       # table, writes results/timing_model.md
  python3 tools/wait_states.py --tacc 12 --clock 100 # one point
"""
import argparse, math, os

def wait_states(tacc_ns, clk_mhz):
    t = 1000.0 / clk_mhz
    n = max(0, math.ceil(tacc_ns / t - 1e-9) - 1)
    return n, n <= 7

def metrics(tacc_ns, clk_mhz, data_w):
    n, ok = wait_states(tacc_ns, clk_mhz)
    lat_ns = (2 + n) * 1000.0 / clk_mhz
    mbps = clk_mhz * (data_w / 8.0) / (3 + n)
    return n, ok, lat_ns, mbps

def fmax_for(tacc_ns):
    """Highest clock at which the 3-bit register can still cover tACC (N = 7)."""
    return 8 * 1000.0 / tacc_ns

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--tacc', type=float)
    ap.add_argument('--clock', type=float)
    ap.add_argument('--data-w', type=int, default=8)
    a = ap.parse_args()
    if a.tacc and a.clock:
        n, ok, lat, mb = metrics(a.tacc, a.clock, a.data_w)
        print('N = %d (%s), latency %.1f ns, throughput %.2f MB/s' % (n, 'ok' if ok else 'exceeds 7', lat, mb))
        raise SystemExit
    taccs = [10, 15, 25, 55, 70]
    clocks = [25, 50, 100, 125, 200]
    out = ['# Wait-state mapping and throughput model', '',
           'Model: N = ceil(tACC / Tclk) - 1, valid for N <= 7. Latency = (2 + N) cycles. Throughput = f x (DATA_W / 8) / (3 + N) for back-to-back accesses, DATA_W = 8.',
           'The access times are illustrative device classes, not data-sheet values.', '',
           '| tACC (ns) | Clock (MHz) | N | Valid | Latency (ns) | Throughput (MB/s) |', '|---|---|---|---|---|---|']
    for ta in taccs:
        for c in clocks:
            n, ok, lat, mb = metrics(ta, c, 8)
            out.append('| %d | %d | %d | %s | %.1f | %.2f |' % (ta, c, n, 'yes' if ok else 'no', lat, mb))
    out += ['', 'Highest clock at which N = 7 still covers the access time:', '',
            '| tACC (ns) | Max clock (MHz) |', '|---|---|']
    for ta in taccs:
        out.append('| %d | %.0f |' % (ta, fmax_for(ta)))
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    os.makedirs(os.path.join(root, 'results'), exist_ok=True)
    open(os.path.join(root, 'results', 'timing_model.md'), 'w').write('\n'.join(out) + '\n')
    print('\n'.join(out[:12]))
