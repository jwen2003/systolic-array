# Systolic Array MVP: Verification Plan

[English](04_verification_plan-EN.md) | [简体中文](04_verification_plan-zh_CN.md)

## 1. Document Status

- Status: final MVP verification state; baseline directed regression, the complete parameter matrix, MAC-count, pairing, and protocol monitors pass.
- Scope: baseline PE, bare array, Input Feeder, Controller, system Top, and the independent Registered Boundary experimental variant.
- Tool: Verilator 5.032 with `--binary --timing --Wall`.
- Baseline evidence: 5 directed testbenches; 8 parameter configurations, each with 9 deterministic corner cases and 100 reproducible random operations, for $8\times109=872$ parameterized operations; 0 errors and 0 warnings.

This document defines what the MVP must prove, the evidence used, and the distinct conclusions established by dynamic verification, formal checks, and physical implementation.

## 2. Verification Objectives

The evidence chain is:

> Correct local PE semantics → correct array interconnect → correct boundary skew → correct control timing → correct end-to-end matrix result → preserved contracts under parameter scaling

The checks cover signed multiplication, sign extension, accumulation, independent A/B data and valid propagation, dual-valid accumulator updates, `acc_clear`, correct $k$ pairing, `start/busy/cycle_idx/done`, exactly $K$ MACs per PE, reference-model results, parameterized completion timing, and unresolved width/signedness/latch/interface warnings.

## 3. Reference Model

For $A:N\times K$, $B:K\times N$, and $C:N\times N$:

$$
C[i][j]=\sum_{k=0}^{K-1}A[i][k]\times B[k][j]
$$

The testbench interprets A and B as signed `DATA_W`, computes with sufficiently wide temporaries, and explicitly converts to `ACC_W` before comparison. Baseline random regression limits $K\le4$, so full-range `DATA_W=8` inputs do not overflow `ACC_W=18`. Configurations that exceed the accumulator range are excluded until saturation, wraparound, or hardware overflow-reporting semantics are defined.

## 4. Cycle Models

### 4.1 Baseline

$$
TOTAL\_RUN\_CYCLES=K+2N-2
$$

$$
LAST\_CYCLE=K+2N-3
$$

An IDLE rising edge accepts `start` and enters RUN with `busy=1` and `cycle_idx=0`. Cycle 0 feeder data and `acc_clear=1` commit on the next edge, allowing clear and the first MAC together. After the edge that commits `LAST_CYCLE`, `done=1`, `busy=0`, and the final result is visible. `done` clears on the next cycle.

### 4.2 Registered Boundary

The added register stage gives:

$$
TOTAL\_RUN\_CYCLES=K+2N-1
$$

$$
LAST\_CYCLE=K+2N-2
$$

RUN 0 only loads the Boundary; no PE may see dual valid. $\mathrm{PE}(i,j)$ executes item $k$ in cycle $i+j+k+1$. The final MAC and `done` become visible after the same `LAST_CYCLE` commit edge. Each PE still performs $K$ MACs and the final matrix is unchanged.

## 5. Directed Verification

### 5.1 Five Baseline Testbenches

| Testbench | Main coverage |
|---|---|
| `tb/tb_systolic_pe.sv` | Synchronous reset, signed extremes, clear/MAC/hold priority, independent one-cycle A/B data/valid forwarding |
| `tb/tb_systolic_array.sv` | Hand-skewed $2\times2$ wavefront, signed matrix, drain, result hold, broadcast `acc_clear` |
| `tb/tb_input_feeder.sv` | $N=2,K=2$ and $N=2,K=3$ injection, out-of-range invalid, zero invalid data, `enable=0` |
| `tb/tb_systolic_controller.sv` | Start acceptance, Cycle 0 clear, counting, ignored RUN start, one-cycle done, second operation, $N=1,K=1$ |
| `tb/tb_systolic_array_top.sv` | Two signed operations, inter-operation clear, exact RUN length, synchronized done and result |

### 5.2 Registered Boundary Testbenches

- `tb/tb_systolic_boundary_pipe.sv`: synchronous reset, clear priority, independent A/B valid, one-cycle delay, and bubble-free capture.
- `tb/tb_systolic_pipelined_controller.sv`: extended RUN window, `cycle_idx`, `acc_clear`, ignored RUN start, one-cycle done, and a second parameter configuration.
- `tb/tb_systolic_array_pipelined_top.sv`: N2/K2 zero MAC in RUN 0, first MAC in RUN 1, final MAC aligned with done, and a clean second operation.

These tests cover variant-specific timing and do not replace the five baseline tests.

## 6. Baseline Parameterized End-to-End Verification

`tb/tb_systolic_array_random.sv` is run by `scripts/run_regression.sh` for:

| $N$ | $K$ | Main boundary |
|---:|---:|---|
| 1 | 1 | Minimum counter, one PE, coincident clear/MAC |
| 2 | 1 | One MAC per PE |
| 1 | 2 | One PE, multi-item dot product |
| 2 | 2 | Primary functional and physical baseline |
| 4 | 2 | Larger array, shorter inner dimension |
| 2 | 3 | $K\ne N$ and counter scheduling |
| 2 | 4 | Longer inner dimension and counter width |
| 4 | 4 | Sixteen results and full drain |

Each configuration runs 9 deterministic corners followed by 100 fixed-seed random operations:

$$
8\times(9+100)=872
$$

The corners are all zero, identity, one nonzero element, all one, alternating signs, 127, -128, mixed 127/-128, and simultaneous zero row/column. Every operation checks the signed reference result, exact completion cycle, protocol transitions, matrix stability, all $N^2$ outputs at `done`, exactly $K$ MACs per PE, cycle-level A/B/$k$ pairing, reset, idle feeder valid, result hold, and absence of residue between operations. Seed `32'h5a17_c3e9` and detailed failure context make failures reproducible.

## 7. Registered Boundary Parameterized Scope

`tb/tb_systolic_array_pipelined_random.sv` retains the signed reference model, 9 corners, default 100 random operations, final comparison, MAC count, pairing, and protocol monitors. It additionally enforces zero MACs in RUN 0, uses $k=t-1-i-j$, keeps `acc_clear == busy && cycle_idx == 0`, extends the matrix-stability window by one cycle, samples the final MAC at the `LAST_CYCLE` edge, aligns `done` with final `psum`, and requires idle Boundary valid to be zero.

The tracked repository proves that this parameterized TB and these monitors are committed. The unified runner does not list an eight-configuration Registered Boundary execution matrix, and neither the README nor docs/09 provides an independently traceable operation total. This document therefore does not reuse the baseline total of 872 or invent a Registered total. The established execution evidence is limited to the three variant directed testbenches, the committed parameterized TB, and the structural and physical gates recorded in docs/09.

## 8. Protocol and Structural Monitors

Baseline monitors require idle feeder valid to be zero; `acc_clear` to equal `busy && cycle_idx == 0`; one-cycle `done` mutually exclusive with `busy`; correct `cycle_idx` progression; reset clearing Controller and PE state; stable matrices throughout `busy`; $\mathrm{PE}(i,j)$ pairing with item $k$ in cycle $i+j+k$; no dual valid outside the legal $k$ window; exactly $K$ MACs per PE and $N^2K$ total MACs; and synchronized final accumulator update and `done`. These hierarchical monitors observe state without changing the synthesizable datapath.

## 9. Formal and Physical-Flow Status

1. Baseline source-to-derived frontend equivalence: 843/843 `$equiv` cells proven.
2. Registered Boundary source-to-derived frontend equivalence: 860/860 `$equiv` cells proven.
3. Post-synthesis equivalence: `inconclusive_tool_scalability`; no counterexample was found, but solving did not complete, so this is neither failed nor proven.
4. Kepler stage LEC: `disabled_due_to_cpu_sigill`. The Kepler Formal binary raises `SIGILL` at startup because of CPU instruction incompatibility; official Nangate45/GCD reproduces it. This is not a design-equivalence failure.
5. Post-route equivalence: not proven.
6. Passing STA, routing, extraction, GDS, detailed-route DRC, and KLayout DRC is not formal-equivalence proof.

These layers must not be summarized as “all formal passed.”

## 10. Coverage and Out of Scope

Covered behavior assumes no stalls or backpressure, complete matrices stable during an operation, signed integer output-stationary computation, a fixed $N\times N$ array, parameterized $K$, and parallel result readout.

Not covered: changing matrices during RUN; ready/valid backpressure, streaming, or stalls; SRAM, DMA, AXI, bandwidth, or runtime; saturation, rounding, floating point, or an overflow flag; overlapping wavefronts; CDC; multi-corner timing signoff; and post-route formal equivalence.

## 11. Failure Classification

| Symptom | First checks |
|---|---|
| PE directed failure | Signedness, width, clear/hold priority |
| Bare-array cycle failure | Neighbor wiring, valid delay, boundary direction |
| Feeder failure | `t-i/t-j` indexing, enable, range checks |
| Controller failure | Start acceptance, counter, `LAST_CYCLE`, done |
| Top-only failure | Cross-module timing contract, busy/enable, clear alignment |
| Random/corner-only failure | Reference width, residue, captured failing input |
| Larger-parameter-only failure | Generate dimensions, `CYCLE_W`, completion cycle |
| Registered MAC in RUN 0 | Boundary clear/valid and Controller alignment |
| Missing final MAC | Monitor terminating early at done |

## 12. Exit Decision

The baseline functional exit criteria are met: 5 directed testbenches, 8 configurations, 872 parameterized operations, results, completion timing, per-PE MAC count, A/B/$k$ pairing, and protocol monitors pass; Verilator 5.032 `--Wall` reports 0 errors and 0 warnings. The baseline subsequently completed generic synthesis and Nangate45 N2/K2 physical implementation.

Registered Boundary remains an independent experimental variant and does not replace the default baseline. Its directed tests, parameterized TB, frontend equivalence, generic structure, and 500/667 MHz physical comparisons establish their respective evidence, without an unsupported claim about an eight-configuration operation total.

The evidence is not a formal proof for arbitrary parameters, post-route equivalence, commercial-process signoff, trustworthy power analysis, or complete-system verification.
