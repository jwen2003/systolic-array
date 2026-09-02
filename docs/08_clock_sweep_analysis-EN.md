# Systolic Array MVP: Clock-Frequency Scaling Analysis

[English](08_clock_sweep_analysis-EN.md) | [简体中文](08_clock_sweep_analysis-zh_CN.md)

## 1. Scope and Traceability

This experiment fixes $N=2$, $K=2$, `DATA_W=8`, and `ACC_W=18`. Each of five points independently runs from read_slang through mapping, floorplan, placement, CTS, global/detailed routing, extraction, final STA, GDS, and KLayout DRC, without reusing another point's netlist, ODB, SPEF, or placement.

- ORFS commit `6101364b2d7909dd797e1e3e7f80695401cfa4e4`;
- image `openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0`;
- OpenROAD `26Q3-1305-gf552262465`, container Yosys `0.68+post`, OpenSTA `3.1.0`;
- Nangate45 typical; `LEC_CHECK=0`.

`LEC_CHECK=0` only disables Kepler stage LEC because its binary raises CPU `SIGILL`; it does not disable physical stages. Every baseline source-to-derived check proves 843/843 `$equiv`; post-synthesis is `inconclusive_tool_scalability`; post-route equivalence is not proven.

Except period, every run reuses the Butterfly 400 MHz active-operation methodology: 0.050 ns uncertainty, 0.050 ns clock/input transition, 0.250 ns I/O delay, 0.010 output load, 50% core utilization, 1:1 aspect ratio, and 0.10 placement-density addon. Synchronous active-low `rst_n` is released before operation and stable during STA; external reset timing is not checked.

## 2. Completion and Timing

| Configuration | Period | Nominal target | Status | Setup WNS / TNS | Hold WNS / TNS |
|---|---:|---:|---|---|---|
| `clk_2500ps` | 2.500 ns | 400.000 MHz | `flow_completed_timing_met` | +0.720010 ns / 0 | +0.065023 ns / 0 |
| `clk_2250ps` | 2.250 ns | 444.444 MHz | `flow_completed_timing_met` | +0.475454 ns / 0 | +0.064492 ns / 0 |
| `clk_2000ps` | 2.000 ns | 500.000 MHz | `flow_completed_timing_met` | +0.219901 ns / 0 | +0.064352 ns / 0 |
| `clk_1750ps` | 1.750 ns | 571.429 MHz | `flow_completed_timing_met` | +0.085547 ns / 0 | +0.064006 ns / 0 |
| `clk_1500ps` | 1.500 ns | 666.667 MHz | `flow_completed_timing_met` | +0.024937 ns / 0 | +0.065251 ns / 0 |

All five complete extracted STA, GDS, and KLayout DRC with setup/hold met and 0 unconstrained endpoints. No first failing point was measured. The 400 MHz run exactly reproduces the committed baseline timing, 2068 functional cells, and 3522.64 µm² final functional area.

## 3. Mapping, Placement, and Implementation Cost

| Target | Mapped cells / area | Placement cells / area | Final cells / area | Timing-repair buffers | Clock buffers |
|---:|---|---|---|---:|---:|
| 400.000 MHz | 1902 / 3442.57 µm² | 2052 / 3502.95 µm² | 2068 / 3522.64 µm² | 152 | 9 |
| 444.444 MHz | 1902 / 3442.57 µm² | 2051 / 3501.09 µm² | 2067 / 3521.84 µm² | 151 | 9 |
| 500.000 MHz | 1902 / 3442.57 µm² | 2052 / 3502.16 µm² | 2068 / 3523.17 µm² | 152 | 9 |
| 571.429 MHz | 1902 / 3442.57 µm² | 2064 / 3512.00 µm² | 2080 / 3529.82 µm² | 164 | 11 |
| 666.667 MHz | 1902 / 3442.57 µm² | 2354 / 3869.50 µm² | 2372 / 3896.63 µm² | 456 | 9 |

Each frontend has 4 signed multipliers, 4 18-bit accumulator adders, and 110 register bits. Mapping is unchanged; frequency-dependent cost appears in physical optimization. Core/die area remains 6711.18/7220.75 µm²; placement utilization rises from 52.20% to 57.66%. Cost is nearly flat through 500 MHz, begins growing at 571.429 MHz, and jumps at 666.667 MHz through resizing and buffer insertion.

## 4. CTS and Routing

| Target | CTS cells / area | Setup / hold skew | Placement WL | Global WL / overflow | Detailed WL / vias | DRC |
|---:|---|---|---:|---|---|---|
| 400.000 MHz | 2068 / 3522.64 µm² | 0.053577 / 0.055555 ns | 17466.6 µm | 31367 µm / 0 | 18551 µm / 13035 | 0 / 0 |
| 444.444 MHz | 2067 / 3521.84 µm² | 0.054091 / 0.054445 ns | 17503.7 µm | 31441 µm / 0 | 18592 µm / 13052 | 0 / 0 |
| 500.000 MHz | 2068 / 3523.17 µm² | 0.051908 / 0.054703 ns | 17450.0 µm | 31230 µm / 0 | 18691 µm / 13134 | 0 / 0 |
| 571.429 MHz | 2080 / 3529.82 µm² | 0.053622 / 0.055000 ns | 17377.8 µm | 30802 µm / 0 | 18440 µm / 13031 | 0 / 0 |
| 666.667 MHz | 2370 / 3891.31 µm² | 0.055670 / 0.055941 ns | 17928.9 µm | 31136 µm / 0 | 18383 µm / 13861 | 0 / 0 |

DRC is detailed-route/KLayout; all are 0. Antenna violations are 0 and every GDS exists. Global-route wirelength is an estimated routing tree; detailed-route wirelength measures final shapes. Their definitions differ, so they are recorded separately without an improvement percentage.

## 5. Critical-Path Migration

| Target | Startpoint → endpoint | Data delay | Cell / net |
|---:|---|---:|---|
| 400.000 MHz | `cycle_idx[0]/Q` → PE(1,0) `psum_out[17]/D` | 1.69648 ns | 99.635% / 0.365% |
| 444.444 MHz | same class | 1.69160 ns | 99.622% / 0.378% |
| 500.000 MHz | same class | 1.69741 ns | 99.806% / 0.194% |
| 571.429 MHz | same class | 1.58314 ns | 99.526% / 0.474% |
| 666.667 MHz | `b_matrix[11]` → PE(0,1) `psum_out[17]/D` | 1.23900 ns; arrival 1.48900 ns | 99.911% / 0.089% |

The first four points remain `cycle_idx → Feeder/control → boundary PE accumulator`. At 666.667 MHz the worst path moves to matrix input → Feeder/control → boundary PE accumulator; arrival includes the 0.250 ns input delay. Cell delay dominates throughout.

## 6. Warnings

No point has a tool error or unclassified warning. Classified items cover floorplan snapping, early wire-load estimation, empty macro PDN grid, audited unused one-pin outputs, no antenna diode, deprecated extractor parameters, and headless GUI environment. At 666.667 MHz `RSZ-0062` records an early unresolved setup violation; later optimization closes it to +0.024937 ns, so the warning remains convergence evidence.

## 7. Conclusion Boundary

All five tested points complete and meet final timing and DRC under fixed Nangate45 typical active-operation conditions. Cost begins to increase at 571.429 MHz and jumps at 666.667 MHz, with a critical-path migration. However, 666.667 MHz is only the highest passing tested nominal target—not silicon Fmax—and no failing point was measured. Nangate45 is a reference platform, not commercial signoff. There is no trustworthy activity-based power, multi-corner/OCV, or silicon correlation; post-synthesis and post-route equivalence gaps remain; and results apply only to the N2/K2 baseline.

Machine-readable ignored results are under `build/openroad/clock_sweep/`. See [Registered Boundary PPA Analysis](09_registered_boundary_ppa_analysis-EN.md) for the experimental variant.
