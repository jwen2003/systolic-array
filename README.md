# Systolic Array MVP

[English](README.md) | [简体中文](README-zh_CN.md)

A parameterized matrix multiply-accumulate project aimed at RTL/Digital Design, Hardware Performance, and Validation roles. The project derives synthesizable RTL from cycle-accurate dataflow, establishes directed, random, structural, and protocol verification, and completes generic synthesis scaling experiments plus a reproducible Nangate45 RTL-to-GDS baseline.

## Project goals and scope

The design computes signed integer matrix multiplication:

$$
C[i][j] = \sum_{k=0}^{K-1} A[i][k] \times B[k][j]
$$

The baseline parameters are:

| Parameter | Definition |
|---|---|
| `N` | Number of rows and columns in the square PE array, also the dimension of output matrix $C$ |
| `K` | Inner-product length for each output element; independent of `N` |
| `DATA_W` | Signed operand width for A/B |
| `ACC_W` | Width of the output-stationary accumulator/result in each PE |

The RTL baseline provides full-matrix parallel inputs and parallel result outputs. It does not include SRAM, DMA, a matrix-loading protocol, ready/valid backpressure, or overlapping operations. The caller must prepare the input matrices before starting an operation and keep them stable throughout the operation.

## Dataflow and cycle model

### Output-stationary

Each $\mathrm{PE}(i,j)$ retains a local `psum_out` and accumulates $K$ products. A propagates to the right across each row, B propagates downward through each column, and the partial sum remains in the PE. The PE consumes $A[i][k]$ and $B[k][j]$ in compute cycle $i+j+k$.

### A/B skew

PEs have different distances from the array boundaries. The combinational Input Feeder uses `cycle_idx` to generate boundary skew:

- Row $i$ injects `A[i][t-i]` in cycle $t$.
- Column $j$ injects `B[t-j][j]` in cycle $t$.
- A lane is invalid outside its legal $k$ window.

Operands with the same $k$ therefore meet at the target PE in the same cycle, without buffering a one-sided operand inside the PE while waiting for its pair.

### `start` / `busy` / `done`

1. The Controller samples `start=1` on an IDLE rising edge, then enters RUN with `busy=1` and `cycle_idx=0`.
2. The combinational interval after that edge is Cycle 0. The next rising edge commits the first MAC while clearing the accumulator and accumulating the first term.
3. A new `start` during RUN is ignored.
4. The compute window contains $K+2N-2$ cycles; the final cycle index is $K+2N-3$.
5. After the last MAC commits, `busy=0`, `done=1`, and all $N^2$ results are valid.
6. `done` is a one-cycle pulse and clears automatically on the next cycle.

`rst_n` is a synchronous active-low reset. The 400 MHz active-operation STA assumes reset is released before an operation begins and remains stable while it runs; the STA does not verify external reset assertion/deassertion interface timing.

## RTL modules

| Module | Responsibility |
|---|---|
| `systolic_pe` | Signed multiplication, sign extension, accumulation, and one-cycle forwarding of A/B/valid |
| `systolic_array` | Instantiates $N\times N$ PEs and connects the horizontal A pipe, vertical B pipe, and parallel `psum` results |
| `input_feeder` | Combinationally indexes the complete input matrices from `cycle_idx` to generate boundary A/B skew and valid signals |
| `systolic_controller` | Accepts `start` and generates `busy`, `cycle_idx`, `acc_clear`, and a one-cycle `done` pulse |
| `systolic_array_top` | Connects the Controller, Feeder, and Array and defines the complete operation protocol |

## Repository structure

```text
rtl/       Five frozen SystemVerilog baseline modules
tb/        Five directed TBs and a parameterized end-to-end random/corner TB
synth/     Yosys generic synthesis Tcl and the controlled configuration matrix
physical/  Nangate45 constraints plus frontend, equivalence, and final-audit Tcl
scripts/   Regression, synthesis, structure-check, and physical-audit entry points
docs/      Design intent, dataflow, microarchitecture, verification, synthesis scaling, and physical implementation evidence
build/     Generated artifacts; not committed to Git
```

Detailed design and evidence documents:

- [01 Design intent](docs/01_design_intent-EN.md)
- [02 Dataflow](docs/02_dataflow-EN.md)
- [03 Microarchitecture](docs/03_microarchitecture-EN.md)
- [04 Verification plan](docs/04_verification_plan-EN.md)
- [05 Synthesis and PPA plan](docs/05_synthesis_and_ppa_plan-EN.md)
- [06 Synthesis scaling analysis](docs/06_synthesis_scaling_analysis-EN.md)
- [07 Physical implementation and PPA analysis](docs/07_physical_implementation_plan-EN.md)
- [08 Clock-frequency scaling analysis](docs/08_clock_sweep_analysis-EN.md)
- [09 Registered Boundary PPA analysis](docs/09_registered_boundary_ppa_analysis-EN.md)
- [10 Minimal software contract](docs/10_minimal_software_contract-EN.md)

## Verification method and results

Verification progresses from local semantics to the system protocol: PE → Array → Feeder → Controller → Top. The same signed reference model checks the final matrix results.

- 5 directed testbenches: PE, Array, Feeder, Controller, and Top.
- 8 parameter configurations: `N/K=1/1, 2/1, 1/2, 2/2, 4/2, 2/3, 2/4, 4/4`.
- Each configuration runs 9 deterministic corner cases and 100 fixed-seed random operations.
- Each configuration therefore runs 109 corner/random operations, for 872 parameterized end-to-end operations in total.
- Verilator `--Wall`, result values, and exact completion-cycle checks all pass.
- The structural monitor, per-PE MAC-count monitor, cycle-by-cycle A/B/k pairing monitor, and controller/feeder/reset/input-stability protocol monitor all pass.
- read_slang frontend equivalence: 843/843 `$equiv` cells proven.

The cycle-by-cycle pairing monitor directly checks that $\mathrm{PE}(i,j)$ receives $A[i][k]$ and $B[k][j]$ in cycle $i+j+k$. The MAC-count monitor requires every PE to commit exactly $K$ MAC operations per operation.

## Generic synthesis and N/K scaling

The Yosys generic flow uses read_slang elaboration, saves pre-tech and techmap JSON/netlists, and automatically checks signed multiplier width/sign extension, $N^2$ multipliers, $N^2$ accumulator adders, register width, and non-empty structure.

The controlled experiments hold `DATA_W=8` and `ACC_W=18` constant:

- With `K=2` and `N=1,2,4`, multipliers, accumulators, and result markers scale with $N^2$; the generic cell total scales approximately with $N^2$. Fixed Controller/Feeder overhead prevents the smallest configurations from following an exact ratio.
- With `N=2` and `K=1,2,3,4`, the four PE datapaths remain unchanged. Changes primarily come from Controller/Feeder selection logic and the cycle counter. `K=3/4` crosses a counter-width boundary, increasing register bits from 110 to 111.
- Generic cells are tool-version-dependent logic-size proxies, not target-technology standard cells, area, Fmax, or power.

See [Synthesis scaling analysis](docs/06_synthesis_scaling_analysis-EN.md) for complete statistics and definitions.

## Nangate45 N2/K2 RTL-to-GDS baseline

The physical baseline fixes `N=2`, `K=2`, `DATA_W=8`, and `ACC_W=18`, with ORFS commit `6101364b2d7909dd797e1e3e7f80695401cfa4e4` and image `openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0`.

The following results reuse the Butterfly 400 MHz active-operation evaluation convention: a 2.500 ns clock period and 0.050 ns uncertainty, with reset released before the operation and held stable while it runs.

| Metric | Result |
|---|---:|
| Final setup WNS | **+0.72001 ns** |
| Final hold WNS | **+0.0650233 ns** |
| Final functional standard-cell area | **3,522.64 µm²** |
| Functional standard cells | **2,068** |
| Global-route overflow | **0** |
| Detailed-route DRC | **0** |
| KLayout DRC | **0** |
| Final GDS | Generated |

Global-route and detailed-route wirelength use different stages and statistical definitions. The project retains both original results but does not compare them directly or calculate an improvement ratio.

## Baseline 400–667 MHz clock sweep

| Target | Setup WNS | Final cells | Final area |
|---:|---:|---:|---:|
| 400.000 MHz | +0.720010 ns | 2,068 | 3,522.64 µm² |
| 444.444 MHz | +0.475454 ns | 2,067 | 3,521.84 µm² |
| 500.000 MHz | +0.219901 ns | 2,068 | 3,523.17 µm² |
| 571.429 MHz | +0.085547 ns | 2,080 | 3,529.82 µm² |
| 666.667 MHz | +0.024937 ns | 2,372 | 3,896.63 µm² |

All five targets complete fresh RTL-to-GDS flows with setup and hold met, zero unconstrained endpoints, zero global overflow, zero detailed-route DRC, and zero KLayout DRC. Implementation cost begins to rise at 571.429 MHz; 666.667 MHz shows a clear jump in cell/area and timing-repair cost. Because the highest tested target still passes, the experiment does not identify the first failing point, and 666.667 MHz must not be described as silicon Fmax. See [Clock-frequency scaling analysis](docs/08_clock_sweep_analysis-EN.md) for the complete flow and metrics.

## Critical-path analysis

The post-route extracted critical path is:

```text
cycle_idx → feeder/control → boundary PE accumulator
```

- Data delay: `1.69648 ns`.
- Cell-delay share: approximately `99.63%`.
- Net-delay share: approximately `0.37%`.

The path begins at the Controller counter, passes through Feeder/control selection, and ends at the boundary PE `psum_out[17]` accumulator register. For the current small N2/K2 core, combinational arithmetic cell delay dominates the critical path rather than long interconnect or the clock path. This observation cannot be extrapolated directly to larger N/K configurations.

## Registered Boundary experiment

The independent Registered Boundary variant adds one stage of A/B data/valid registers between the Feeder and Array while retaining 4 signed multipliers and 4 accumulator datapaths. At 500 MHz, post-route setup WNS improves from the baseline `+0.219901 ns` to `+0.475003 ns`. At the same 667 MHz target, final cells decrease by 11.38%, final area decreases by 3.97%, and timing-repair buffers decrease by 62.5%. The cost is an increase in the RUN window from 4 cycles to 5 cycles, reducing same-frequency operation throughput by 20% under the non-overlap protocol.

The baseline therefore remains the default implementation. Registered Boundary is retained as an experimental timing-closure and implementation-cost tradeoff. See [Registered Boundary PPA analysis](docs/09_registered_boundary_ppa_analysis-EN.md) for complete structural, post-route, and throughput analysis.

## Minimal software contract

The project freezes a logical software contract: workloads map onto a fixed hardware shape; A/B use signed `int8`; the accumulator/result uses signed `int18`; and host buffers are row-major. Smaller shapes execute through zero padding. Commands follow `busy`, a one-cycle `start`, and a one-cycle `done`; overflow policy may expose hardware wrap or allow a future wrapper to reject risk conservatively. This contract does not mean that a runtime, AXI, or DMA interface has been implemented. See [Minimal software contract](docs/10_minimal_software_contract-EN.md).

## Reproduction

Run the following commands from the repository root. Linux/WSL requires the corresponding Verilator installation, pinned OSS CAD Suite, Docker, and matching ORFS checkout.

```bash
# 5 directed TBs + 8 parameter configurations, 872 end-to-end operations
scripts/run_regression.sh

# 8 controlled N/K generic-synthesis configurations with automated structural checks
scripts/run_synth.sh

# Rerun the non-destructive post-route STA audit on existing N2/K2 final ODB/SDC/SPEF
ORFS_ROOT=/path/to/OpenROAD-flow-scripts scripts/run_openroad_final_audit.sh

# Validate an existing complete physical result and its machine-readable metrics
python3 scripts/check_openroad_results.py \
  build/openroad/lec_disabled/systolic_n2_k2_full
```

`run_openroad_final_audit.sh` does not rerun the complete RTL-to-GDS flow. It requires the matching fixed ORFS commit, fixed Docker image, and existing non-empty final ODB/SDC/SPEF files.

## Conclusion boundaries and unfinished work

- Nangate45/FreePDK45 is an open reference platform; these results are not commercial-process signoff.
- The project has no trustworthy power result based on real activity, multi-corner libraries, and silicon correlation, and does not claim complete PPA.
- Multi-corner/multi-mode signoff, OCV/AOCV/POCV, and foundry-qualified extraction have not been completed.
- Baseline RTL to read_slang derived frontend equivalence is proven.
- Post-synthesis equivalence is `inconclusive_tool_scalability`: no counterexample was found, but solving did not complete, so this is not a pass.
- Kepler stage LEC is disabled through the formal configuration `LEC_CHECK=0` because of a reproducible host-CPU `SIGILL`; CTS, STA, routing, extraction, GDS, and DRC were not skipped.
- Post-route equivalence is not proven.
- N/K physical scaling and activity-based power analysis have not been performed. The completed clock sweep covers only the N2/K2 baseline and must not be extrapolated to larger arrays, other corners, or silicon Fmax.

Auditable technical details, tool versions, warning classifications, and statistical definitions are retained in `docs/` and the reproducible scripts. This README summarizes only established conclusions.

## License

This project is licensed under the [MIT License](LICENSE).
