# Systolic Array MVP: Synthesis Scaling Analysis

[English](06_synthesis_scaling_analysis-EN.md) | [简体中文](06_synthesis_scaling_analysis-zh_CN.md)

## 1. Objective

With frozen RTL and verification semantics, Yosys generic synthesis isolates how array dimension $N$ and inner dimension $K$ affect logical structure. This experiment has no Liberty mapping, STA, or physical implementation.

## 2. Established Facts

- OSS CAD Suite `20260830`, Yosys `0.68+136`, and `read_slang` are fixed.
- Eight configurations complete hierarchy, proc, opt, check, memory, techmap, opt, and stat; Slang reports 0 errors/0 warnings and all four checks report 0 problems.
- Pre-tech and techmap cell sets are nonempty; signed multiplier width, attributes, and sign extension pass.
- `pe_result_markers` counts hierarchical `psum_out` netnames, not flattened PE module cells. Together with $N^2$ multipliers, $N^2$ accumulator adders, and nonempty checks, it shows PE structure remains.
- Generic cells are Yosys techmap primitives, not target-process standard cells.

## 3. Variables and Counter Formula

All configurations fix `DATA_W=8`, `ACC_W=18`, the Git worktree, Tcl, Yosys, and pass sequence. The RTL counter-width formula is:

$$
W_{cycle}=\max\left(1,\left\lceil\log_2(K+2N-2)\right\rceil\right)
$$

`synth/synth_configs.tsv` is the single configuration source; `n2_k2` is synthesized once and belongs to baseline, N sweep, and K sweep.

## 4. Matrix

| Configuration | $N$ | $K$ | Group |
|---|---:|---:|---|
| n1_k1 | 1 | 1 | baseline |
| n2_k1 | 2 | 1 | k_sweep |
| n1_k2 | 1 | 2 | n_sweep |
| n2_k2 | 2 | 2 | baseline, n_sweep, k_sweep |
| n4_k2 | 4 | 2 | n_sweep |
| n2_k3 | 2 | 3 | k_sweep |
| n2_k4 | 2 | 4 | k_sweep |
| n4_k4 | 4 | 4 | baseline |

## 5. N Sweep at Fixed $K=2$

| Configuration | $N$/$N^2$ | Markers / mul / acc add | Cycle bits | Reg cells / bits | Pre-tech | Generic | Generic/$N^2$ | Reg bits/$N^2$ |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| n1_k2 | 1 / 1 | 1 / 1 / 1 | 1 | 4 / 21 | 30 | 834 | 834.000 | 21.000 |
| n2_k2 | 2 / 4 | 4 / 4 / 4 | 2 | 13 / 110 | 75 | 3337 | 834.250 | 27.500 |
| n4_k2 | 4 / 16 | 16 / 16 / 16 | 3 | 55 / 497 | 215 | 13155 | 822.188 | 31.063 |

PE markers, multipliers, and accumulator adders scale exactly with $N^2$. Generic cells scale by $4.001\times$ and $15.773\times$ relative to n1_k2; generic/$N^2$ stays near 834, showing approximate rather than exact $N^2$ scaling. Fixed Controller/Feeder overhead and word-level granularity prevent strict pre-tech scaling. Increasing register bits per PE is structurally consistent with more retained internal forwarding edges, but flattened JSON does not prove module ownership.

| Configuration | AND | MUX | NOT | OR | SDFFE | SDFF | XOR | Generic total |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| n1_k2 | 342 | 88 | 2 | 117 | 19 | 2 | 264 | 834 |
| n2_k2 | 1373 | 310 | 12 | 474 | 74 | 36 | 1058 | 3337 |
| n4_k2 | 5483 | 1032 | 32 | 1881 | 291 | 206 | 4230 | 13155 |

## 6. K Sweep at Fixed $N=2$

| Configuration | $K$ | Cycle bits | Markers / mul / acc add | Other add | Reg cells / bits | Pre-tech | Generic |
|---|---:|---:|---:|---:|---:|---:|---:|
| n2_k1 | 1 | 2 | 4 / 4 / 4 | 1 | 13 / 110 | 71 | 3306 |
| n2_k2 | 2 | 2 | 4 / 4 / 4 | 1 | 13 / 110 | 75 | 3337 |
| n2_k3 | 3 | 3 | 4 / 4 / 4 | 1 | 13 / 111 | 83 | 3413 |
| n2_k4 | 4 | 3 | 4 / 4 / 4 | 1 | 13 / 111 | 83 | 3413 |

Changing $K$ does not replicate MAC hardware: markers, multipliers, and accumulator adders remain 4. Counter width grows from 2 to 3 bits at $K=3$, register cells remain 13, and register bits grow from 110 to 111. Relative to n2_k1, generic totals change by 0, 31, 107, and 107 cells. Additional logic is consistent with Feeder selection and Controller range, but flattened JSON cannot assign every primitive. Identical n2_k3/n2_k4 statistics are an observation of this pinned elaboration and optimization flow, not a universal rule.

| Configuration | AND | MUX | NOT | OR | SDFFE | SDFF | XOR | Total delta |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| n2_k1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| n2_k2 | 0 | +32 | 0 | -1 | 0 | 0 | 0 | +31 |
| n2_k3 | +3 | +98 | +1 | +2 | +1 | 0 | +2 | +107 |
| n2_k4 | +3 | +98 | +1 | +2 | +1 | 0 | +2 | +107 |

## 7. Architectural Invariants

For every configuration, PE result markers, signed multipliers, and accumulator adders equal $N^2$; changing $K$ does not change those counts. Accumulator adders are classified by `psum_out` A-side connection and `ACC_W`. `N=1` retains complete A/B pipe-width checks.

## 8. Tool-Dependent Observations

Every configuration has one non-accumulator adder. Total adder count $N^2+1$ remains a regression baseline for this Yosys version, not an architectural requirement. Primitive counts are generated from JSON. Pre-tech, MUX, Boolean, and total primitive counts depend on elaboration, constant propagation, pass order, and tool version.

## 9. Conclusions Not Supported

Generic cell count is only a logic-size proxy and cannot be converted to process area. Without Liberty, SDC, delay models, placement, routing, CTS, or parasitics, the experiment cannot establish Fmax, power, routed timing, or a physical critical path. Flattened increments cannot be assigned rigorously to one RTL module.

## 10. Physical Hypotheses

Candidate internal path: registered A/B → multiplier → accumulator adder → accumulator register. Candidate boundary path: `cycle_idx` register → Feeder selection/mux → boundary PE multiplier → accumulator adder → accumulator register. Increasing $N$ grows load and scale but not one PE's logic depth; increasing $K$ may affect the boundary path through Feeder mux complexity; `acc_clear` fanout may require physical buffering. Testing these hypotheses requires a target Liberty, clock/I/O SDC, STA, placement, CTS, routing, and extraction.

Machine-readable results are under `build/synth/structure_summary.json`, `structure_summary.tsv`, and each ignored configuration directory.
