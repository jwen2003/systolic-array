# Systolic Array MVP: Registered Boundary PPA Analysis

[English](09_registered_boundary_ppa_analysis-EN.md) | [简体中文](09_registered_boundary_ppa_analysis-zh_CN.md)

## 1. Objective

This experiment inserts one Registered Boundary stage between `input_feeder` and `systolic_array` to cut the long baseline Feeder/control-to-boundary-PE-accumulator path and quantify cycle, area, and physical convergence costs. It fixes $N=2$, $K=2$, `DATA_W=8`, `ACC_W=18`, Nangate45, active-operation constraints, ORFS commit `6101364b2d7909dd797e1e3e7f80695401cfa4e4`, image `openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0`, and a non-overlap operation protocol.

## 2. Structural Difference

Both versions retain 4 PEs, 4 signed $8\times8$ multipliers, and 4 18-bit accumulator adders. The variant adds registers for A/B boundary data and valid without modifying baseline RTL, using a separate Top, Controller, Boundary module, filelist, and physical configuration.

| Metric | Baseline | Registered Boundary |
|---|---:|---:|
| PE / multiplier / accumulator adder | 4 / 4 / 4 | 4 / 4 / 4 |
| Generic register bits | 110 | 145 |
| RUN cycles | 4 | 5 |

Logical Boundary state is $2\times N\times(DATA_W+1)=36$ bits. Yosys retains 34 independent Boundary bits after merging equivalent valid state, while the pipelined Controller adds one counter bit: $110+34+1=145$. This packing is tool-version-specific.

## 3. Functional Timing

$$
TOTAL\_RUN\_CYCLES=K+2N-1
$$

The last cycle is $K+2N-2$. For N2/K2, RUN cycles are 0–4: RUN 0 loads the Boundary and clears accumulators, first MAC is RUN 1, and final MAC is RUN 4. Pairing uses `k = cycle_idx - 1 - i - j`. Every PE still performs $K$ MACs, pairing and results remain unchanged, and `done` appears after the same edge as the final MAC. Latency increases by one cycle.

## 4. Generic Structural Comparison

Both variants pass read_slang elaboration, nonempty-top, multiplier/accumulator width, and structural gates under the same Yosys sequence. Boundary registers sit between Feeder selection and Array input, with no observed combinational bypass from `cycle_idx` or matrix input to a multiplier. Boundary clear controls only Boundary state; PE accumulator clear still comes from the pipelined Controller. This proves the register boundary and unchanged MAC count, not post-route timing improvement.

## 5. 500 MHz Post-Route Comparison

| Metric | Baseline | Registered Boundary |
|---|---:|---:|
| Period / RUN cycles | 2.000 ns / 4 | 2.000 ns / 5 |
| Setup / hold WNS | +0.219901 / +0.064352 ns | +0.475003 / +0.052253 ns |
| Final cells / area | 2,068 / 3,523.17 µm² | 2,084 / 3,723.47 µm² |
| Timing-repair / clock buffers | 152 / 9 | 152 / 17 |
| Detailed-route vias | 13,134 | 13,081 |

Setup WNS improves by 0.255102 ns, while cells increase 0.77% and area 5.69%. Hold remains positive. Non-overlap latency grows from 8 to 10 ns, reducing same-frequency operation and useful-MAC throughput by 20%.

## 6. 667 MHz Post-Route Comparison

| Metric | Baseline | Registered Boundary |
|---|---:|---:|
| Period / RUN cycles | 1.500 ns / 4 | 1.500 ns / 5 |
| ns/operation | 6.000 | 7.500 |
| Operations/s | 166.667 Mops/s | 133.333 Mops/s |
| Useful MAC/s | 1.333 GMAC/s | 1.067 GMAC/s |
| Setup WNS | +0.024937 ns | +0.031136 ns |
| Hold WNS | — | +0.063782 ns |
| Final cells / area | 2,372 / 3,896.63 µm² | 2,102 / 3,742.09 µm² |
| Area / throughput | 23.380 | 28.066 µm²/(Mop/s) |
| Timing-repair / clock buffers | 456 / 9 | 171 / 17 |
| Detailed-route vias | 13,861 | 13,194 |

Registered Boundary has 0 global overflow, detailed/KLayout DRC, antenna violation, and unconstrained endpoints. Frontend equivalence is 860/860 proven; Kepler stage LEC remains disabled due to CPU `SIGILL`; post-route equivalence is not proven. At the same target, cells fall 11.38%, area 3.97%, and timing-repair buffers 62.5%, but one extra RUN cycle reduces throughput 20% and worsens area/throughput by about 20%.

## 7. Critical-Path Migration

Baseline 500 MHz is `cycle_idx → Feeder/control → boundary PE accumulator`; Registered 500 MHz becomes Boundary register → multiplier/accumulator. At 667 MHz the variant path is `boundary_b[11]/Q → PE(0,1) multiplier/accumulator`, with 1.3773 ns data delay: 1.3755 ns cell (99.869%) and 0.0018 ns net (0.131%). This matches the intended split, while cell delay remains dominant.

## 8. Throughput and Area Efficiency

| Cross-frequency comparison | Baseline 500 MHz | Registered 667 MHz |
|---|---:|---:|
| Operations/s | 125.000 Mops/s | 133.333 Mops/s |
| Final area | 3,523.17 µm² | 3,742.09 µm² |
| Area / throughput | 28.185 | 28.066 µm²/(Mop/s) |

Registered 667 MHz gains 6.67% operation throughput for 6.21% area, giving about 0.42% better area efficiency than baseline 500 MHz. Because baseline itself closes at 667 MHz, this does not establish overall superiority.

## 9. Architecture Decision

The baseline remains default; Registered Boundary remains an independent experiment. It cuts the Feeder critical path and reduces high-frequency convergence cost, but adds one RUN cycle: latency +25%, same-frequency throughput -20%, and same-frequency 667 MHz area-throughput efficiency roughly -20%. About 833.3 MHz would be required for a 5-cycle operation to match baseline 667 MHz throughput, but that point is not tested or claimed achievable. Overlap, double buffering, and deeper pipelines are out of scope.

## 10. Boundaries

Results apply only to Nangate45, N2/K2, int8/int18, current active-operation constraints, pinned tools, and non-overlap protocol. They do not establish commercial signoff, silicon Fmax, multi-corner signoff, trustworthy activity-based power, post-route equivalence, or superiority for all frequencies and parameters. Source-to-derived equivalence is proven; Kepler and post-route gaps remain.
