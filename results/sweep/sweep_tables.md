# Sweep results (xc7a35tftg256-1, Vivado out-of-context, internal register-to-register timing)

## Configuration sweep, 4.0 ns clock target, post-route

| DATA_W | ADDR_W | Words | Memory bits | LUTs | of which LUT as memory | FFs | BRAM | WNS (ns) | Estimated Fmax (MHz) | Power total (W) |
|---|---|---|---|---|---|---|---|---|---|---|
| 8 | 3 | 8 | 64 | 45 | 8 | 45 | 0 | 0.698 | 302.8 | 0.070 |
| 8 | 4 | 16 | 128 | 47 | 8 | 47 | 0 | 0.937 | 326.5 | 0.070 |
| 8 | 5 | 32 | 256 | 45 | 8 | 49 | 0 | 0.938 | 326.6 | 0.070 |
| 8 | 6 | 64 | 512 | 49 | 8 | 51 | 0 | 0.532 | 288.4 | 0.070 |
| 16 | 3 | 8 | 128 | 53 | 16 | 61 | 0 | 1.260 | 365.0 | 0.071 |
| 16 | 4 | 16 | 256 | 53 | 16 | 63 | 0 | 1.083 | 342.8 | 0.071 |
| 16 | 5 | 32 | 512 | 53 | 16 | 65 | 0 | 0.961 | 329.1 | 0.071 |
| 16 | 6 | 64 | 1024 | 40 | 0 | 51 | 0.5 | 0.707 | 303.7 | 0.071 |
| 32 | 3 | 8 | 256 | 69 | 32 | 93 | 0 | 1.017 | 335.2 | 0.071 |
| 32 | 4 | 16 | 512 | 71 | 32 | 95 | 0 | 0.837 | 316.2 | 0.070 |
| 32 | 5 | 32 | 1024 | 38 | 0 | 65 | 0.5 | 0.775 | 310.1 | 0.071 |
| 32 | 6 | 64 | 2048 | 42 | 0 | 67 | 0.5 | 0.573 | 291.8 | 0.071 |

## Clock sweep, DATA_W = 8, ADDR_W = 4, post-route, spread over placer directives

| Target period (ns) | Target (MHz) | Runs | WNS mean (ns) | WNS min (ns) | WNS max (ns) | Runs meeting timing | Est. Fmax mean (MHz) | Est. Fmax spread (MHz) | LUTs | FFs | Power mean (W) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 10 | 100 | 5 | 5.502 | 5.350 | 5.737 | 5 of 5 | 222.7 | 215.1 to 234.6 | 45 | 47 | 0.069 |
| 8 | 125 | 5 | 3.434 | 3.254 | 3.722 | 5 of 5 | 219.5 | 210.7 to 233.8 | 45 | 47 | 0.069 |
| 6 | 167 | 5 | 1.556 | 1.405 | 1.909 | 5 of 5 | 225.5 | 217.6 to 244.4 | 45 | 47 | 0.070 |
| 5 | 200 | 5 | 1.538 | 0.963 | 1.819 | 5 of 5 | 290.8 | 247.7 to 314.4 | 45 | 47 | 0.070 |
| 4 | 250 | 5 | 0.917 | 0.843 | 0.937 | 5 of 5 | 324.4 | 316.8 to 326.5 | 47 | 47 | 0.070 |
| 3.5 | 286 | 5 | 0.626 | 0.562 | 0.718 | 5 of 5 | 348.2 | 340.4 to 359.5 | 46 | 47 | 0.070 |
| 3 | 333 | 5 | 0.422 | 0.375 | 0.465 | 5 of 5 | 388.0 | 381.0 to 394.5 | 48 | 47 | 0.071 |
| 2.5 | 400 | 5 | -0.110 | -0.309 | -0.013 | 0 of 5 | 383.7 | 356.0 to 397.9 | 47 | 47 | 0.071 |

Highest clock target met in every directive run: 333 MHz.

Notes: the spread comes from the placer directive (Default, Explore, ExtraTimingOpt, ExtraNetDelay_high, SpreadLogic_high), not from random seeds. Timing is register to register inside the controller (the design is synthesised out of context and I/O paths are excluded). Estimated Fmax = 1000 / (period - WNS). Power figures are vectorless Vivado estimates for the out-of-context design.
