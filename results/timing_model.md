# Wait-state mapping and throughput model

Model: N = ceil(tACC / Tclk) - 1, valid for N <= 7. Latency = (2 + N) cycles. Throughput = f x (DATA_W / 8) / (3 + N) for back-to-back accesses, DATA_W = 8.
The access times are illustrative device classes, not data-sheet values.

| tACC (ns) | Clock (MHz) | N | Valid | Latency (ns) | Throughput (MB/s) |
|---|---|---|---|---|---|
| 10 | 25 | 0 | yes | 80.0 | 8.33 |
| 10 | 50 | 0 | yes | 40.0 | 16.67 |
| 10 | 100 | 0 | yes | 20.0 | 33.33 |
| 10 | 125 | 1 | yes | 24.0 | 31.25 |
| 10 | 200 | 1 | yes | 15.0 | 50.00 |
| 15 | 25 | 0 | yes | 80.0 | 8.33 |
| 15 | 50 | 0 | yes | 40.0 | 16.67 |
| 15 | 100 | 1 | yes | 30.0 | 25.00 |
| 15 | 125 | 1 | yes | 24.0 | 31.25 |
| 15 | 200 | 2 | yes | 20.0 | 40.00 |
| 25 | 25 | 0 | yes | 80.0 | 8.33 |
| 25 | 50 | 1 | yes | 60.0 | 12.50 |
| 25 | 100 | 2 | yes | 40.0 | 20.00 |
| 25 | 125 | 3 | yes | 40.0 | 20.83 |
| 25 | 200 | 4 | yes | 30.0 | 28.57 |
| 55 | 25 | 1 | yes | 120.0 | 6.25 |
| 55 | 50 | 2 | yes | 80.0 | 10.00 |
| 55 | 100 | 5 | yes | 70.0 | 12.50 |
| 55 | 125 | 6 | yes | 64.0 | 13.89 |
| 55 | 200 | 10 | no | 60.0 | 15.38 |
| 70 | 25 | 1 | yes | 120.0 | 6.25 |
| 70 | 50 | 3 | yes | 100.0 | 8.33 |
| 70 | 100 | 6 | yes | 80.0 | 11.11 |
| 70 | 125 | 8 | no | 80.0 | 11.36 |
| 70 | 200 | 13 | no | 75.0 | 12.50 |

Highest clock at which N = 7 still covers the access time:

| tACC (ns) | Max clock (MHz) |
|---|---|
| 10 | 800 |
| 15 | 533 |
| 25 | 320 |
| 55 | 145 |
| 70 | 114 |
