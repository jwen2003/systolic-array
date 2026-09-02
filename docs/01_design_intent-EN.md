# Systolic Array MVP: Design Intent

[English](01_design_intent-EN.md) | [简体中文](01_design_intent-zh_CN.md)

## 1. Document Status

- Status: fourth revision; baseline RTL, directed/random regression, and structural and protocol monitors are complete.
- Current scope: MVP objectives, system boundary, core design principles, external operation protocol, and acceptance criteria.
- Current verification evidence: five baseline directed testbenches pass; eight parameter configurations each complete 9 deterministic corner cases and 100 reproducible random operations, for 872 parameterized operations; the per-PE MAC-count, cycle-by-cycle A/B/$k$ pairing, and system protocol monitors all pass.
- Current implementation evidence: baseline generic synthesis and Nangate45 N2/K2 RTL-to-GDS are complete; Registered Boundary is retained as an independent experimental variant; the minimal software contract is frozen.

This document explains why the project exists, what the MVP must prove, and which features are explicitly excluded. It does not describe cycle-by-cycle data positions or concrete RTL structure; those subjects are covered by “02 Dataflow” and “03 Microarchitecture,” respectively.

## 2. Project Objectives

The project implements a synthesizable output-stationary systolic array and uses cycle-by-cycle derivation, automated verification, performance accounting, and synthesis results to answer the following questions:

1. How matrix multiplication maps onto spatially distributed PE computation.
2. Why A and B require skew, and how operands with the same $k$ meet at the target PE in the same cycle.
3. How fill, useful computation, and drain determine total latency and hardware utilization.
4. How array size, workload size, and actual throughput relate.
5. Why performance does not necessarily scale linearly with PE count.
6. How RTL structure maps to multipliers, adders, registers, interconnect, and critical paths.

The goal is not merely to obtain the correct matrix product, but to establish the complete evidence chain:

> Mathematical mapping → space-time schedule → microarchitecture → RTL → verification → performance and PPA

## 3. MVP Scope

### 3.1 Frozen Scope

- Dataflow: output-stationary.
- Array organization: parameterized $N \times N$ two-dimensional PE array.
- Initial target sizes: verify $2 \times 2$ first, then extend to $4 \times 4$.
- Operation: signed integer matrix multiplication.
- Default input width: `DATA_W = 8`.
- Default accumulator width: `ACC_W = 18`, sufficient for the sum of four extreme 8-bit signed products.
- A propagates from left to right.
- B propagates from top to bottom.
- Each PE accumulator permanently owns one output element $C[i][j]$.
- A PE performs a MAC only when A and B are both valid in the same cycle.
- A, B, and their valid signals propagate independently; a PE does not wait to pair them.
- The baseline PE has no intermediate pipeline register between multiplication and addition.
- Reset clears forwarding state and the accumulator in every PE.
- `acc_clear` begins a new local accumulation and may coincide with that operation's first valid MAC.
- Input shapes are $A:N\times K$ and $B:K\times N$; output shape is $C:N\times N$.
- $N$ and $K$ are independently parameterized; $K=N$ is not required.
- The Input Feeder combinationally indexes the complete matrices from `cycle_idx` and generates skew at the array boundary.
- The Controller uses `busy` to represent the two states `IDLE/RUN` and completes after a fixed cycle count.
- `start` is sampled on an idle rising edge, followed by the Cycle 0 preparation interval; the next rising edge commits the first MAC.
- `done` is a one-cycle pulse produced after the final MAC commits.
- The baseline top exposes the complete parallel `result[N][N]`.

### 3.2 Explicitly Out of Scope

- AXI, DMA, NoC, or a complex on-chip bus.
- SRAM scratchpad, cache, or a multilevel memory hierarchy.
- Ready/valid backpressure.
- Operand waiting, replay, or dynamic pairing inside a PE.
- Floating-point arithmetic.
- Fixed-point rounding, saturation, or complex quantization.
- Sparse computation, zero skipping, or structured pruning.
- Multi-tenancy, preemption, or runtime scheduling.
- A complete neural-network operator stack.
- Modules unrelated to the core questions added merely to increase code volume.

These items are not excluded forever; they are outside the proof objectives of the current MVP.

## 4. Core Design Principles

### 4.1 Local Rules Must Remain Simple

Each PE performs only two local actions:

1. Forward valid A to the right and valid B downward.
2. When A and B are valid in the same cycle, accumulate their product into the local accumulator.

A PE does not know matrix coordinates, the $k$ index, or overall operation progress. Correct pairing is guaranteed by the space-time schedule at the array boundary.

### 4.2 Scheduling Complexity Belongs at the Array Boundary

PEs have different propagation distances from the boundaries. Through skew, the Input Feeder must make $A[i][k]$ and $B[k][j]$ reach PE$(i,j)$ in the same cycle, rather than requiring a PE to store a one-sided operand while waiting for the other.

### 4.3 Correctness Includes Cycle Accuracy

Every case below is a design error:

- Incorrect numerical results.
- Incorrect $k$ pairing between A and B.
- Misalignment between valid and data.
- Accumulator changes without a valid MAC.
- Correct results produced on a completion cycle inconsistent with the definition.
- Performance counts inconsistent with actual PE activity.

### 4.4 Parameterization Must Not Hide Undefined Semantics

Parameterization first supports structural and performance comparisons among $N=1$, $N=2$, and $N=4$; it does not claim that every arbitrary parameter combination is automatically meaningful. Every parameter requires an explicit constraint—for example, `ACC_W` must not be narrower than one full product.

## 5. Definition of Correctness

For matrices $A$ and $B$, the output must satisfy:

$$
C[i][j] = \sum_{k=0}^{K-1} A[i][k] \times B[k][j]
$$

Under the output-stationary mapping:

- PE$(i,j)$ is solely responsible for $C[i][j]$.
- During each operation, PE$(i,j)$ performs exactly $K$ valid MACs.
- MAC $k$ uses $A[i][k]$ and $B[k][j]$.
- At completion, the PE accumulator holds the final $C[i][j]$.

## 6. Performance Questions

The project distinguishes three quantities:

- Theoretical peak: every PE performs one MAC every cycle.
- Schedule utilization: valid MACs as a fraction of available PE-cycles.
- Actual implementation performance: the result after clock frequency, interface supply capability, and control overhead.

For one $N \times N$ output with inner-product length $K$ under ideal skew scheduling:

- Useful MAC count is $N^2K$.
- The window from the first MAC through the final MAC is $K + 2N - 2$ cycles.
- Array-window utilization is $K/(K+2N-2)$.

This formula describes only the current stall-free baseline with sufficient data supply; it is not the actual utilization after adding a future memory system.

## 7. Acceptance Criteria

The MVP must at minimum satisfy:

- All directed PE tests pass.
- Signedness, width, clear, hold, and forwarding behavior are verified.
- Cycle-by-cycle behavior of the $2 \times 2$ array matches the hand-derived space-time table.
- Random matrix results match the reference model.
- Every PE performs exactly $K$ MACs per operation.
- Completion timing matches the analytical model.
- Parameterized regression covers at least $N=1$, $N=2$, and $N=4$.
- Lint reports no critical latch, width, or signedness warnings.
- Synthesis reports can explain the sources of multipliers, registers, area, and the critical path.
- The effect of fill/drain and data-supply constraints on scaling can be explained.

The main functional baseline criteria above pass: five directed testbenches continue to pass; the eight configurations $N/K=1/1,2/1,1/2,2/2,4/2,2/3,2/4,4/4$ each complete 9 deterministic corner cases and 100 fixed-seed random operations; completion cycles, every result, per-PE MAC counts, A/B/$k$ pairing, and system protocols match the model; and Verilator 5.032 `--Wall` reports 0 errors and 0 warnings.

The cycle-by-cycle pairing monitor passes across those eight configurations and 872 parameterized operations. It directly checks that each MAC in cycle $i+j+k$ uses `A[i][k]` and `B[k][j]`, and checks that both valid signals never coincide outside the legal window.

## 8. Current Interface and Operation Constraints

The baseline uses complete-matrix parallel inputs rather than cycle-by-cycle streaming loads:

- The caller prepares A and B before `start` is sampled.
- A and B remain stable from accepted `start` through `done`.
- A new `start` is ignored while `busy=1`.
- The feeder emits valid boundary data only while `busy=1`.
- Bubble-free handoff or wavefront overlap between operations is not supported.
- When `done=1`, the complete result is already stored on the parallel `result[N][N]` port.

The interface deliberately avoids matrix loading, SRAM, and bandwidth questions so that the space-time schedule can first be isolated and proven.

## 9. Current Milestone and Follow-up Questions

Completed work:

1. Five synthesizable RTL modules and top-level integration.
2. Five directed verification groups for the PE, bare array, Input Feeder, Controller, and system top.
3. A parameterized random end-to-end testbench and signed reference model.
4. Eight $N/K$ configurations and 872 reproducible corner/random operations in total.
5. A hierarchical monitor requiring exactly $K$ MACs from every PE per operation.
6. Array interconnect refactored for $N=1$ into pipes containing input/output boundary positions, with bare-array, $N=2,K=2$, and $N=4,K=4$ regression complete.
7. A cycle-by-cycle A/B/$k$ pairing monitor passing across eight configurations and 872 operations.
8. Baseline generic synthesis, Nangate45 N2/K2 RTL-to-GDS, and the 400–667 MHz clock sweep.
9. Structural verification and 500/667 MHz physical comparisons for the independent Registered Boundary experimental variant.
10. A frozen minimal software contract.

The functional, generic-synthesis, and current physical-implementation exit criteria are met. The baseline remains the default implementation; Registered Boundary does not replace it. Open follow-up questions are:

1. Extend physical evidence to other $N/K$ values, corners, or technologies.
2. Derive `ACC_W` and define overflow policy for larger $K$.
3. Later evaluate matrix-loading storage, result-read interfaces, and PPA differences between indexed and delay-chain feeders.
