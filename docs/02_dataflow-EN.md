# Systolic Array MVP: Dataflow

[English](02_dataflow-EN.md) | [简体中文](02_dataflow-zh_CN.md)

## 1. Document Status

- Status: third revision; baseline dataflow and boundary scheduling are frozen and pass directed, random, and MAC-count structural regression.
- Frozen and implemented: output-stationary mapping, A/B propagation directions, indexed skew, PE meeting times, fill/drain, and ideal utilization.
- Current input protocol: complete matrices remain stable throughout an operation; the feeder is driven by `busy` and `cycle_idx`.
- Current evidence boundary: eight $N/K$ configurations each complete 9 deterministic corner cases and 100 reproducible random operations, for 872 parameterized operations; results, completion cycles, per-PE MAC counts, and cycle-by-cycle operand identities are correct.

## 2. Mathematical Mapping

Matrix multiplication is defined as:

$$
C[i][j] = \sum_{k=0}^{K-1} A[i][k] \times B[k][j]
$$

The current design statically maps each output element to one processing element (PE):

- PE$(i,j)$ owns $C[i][j]$.
- $A[i][k]$ propagates from left to right along row $i$.
- $B[k][j]$ propagates from top to bottom along column $j$.
- PE$(i,j)$ performs a MAC when A and B with the same $k$ arrive in the same cycle.
- The partial sum remains inside PE$(i,j)$ until the operation completes.

This is output-stationary: the output partial sum, rather than A or B, remains stationary.

## 3. Local PE Dataflow Rules

Each PE is unaware of global matrix coordinates and follows only these rules:

```text
if A is valid:
    forward A to the right

if B is valid:
    forward B downward

if A and B are both valid in the same cycle:
    psum = psum + A * B
```

A and B forwarding are independent, while a MAC requires both valid signals. If only one side is valid, that operand continues to propagate; the PE does not cache it while waiting for the other side.

Therefore:

> The PE performs local computation and transport; the Input Feeder guarantees global temporal pairing.

## 4. Why Skew Is Required

For PE$(i,j)$:

- A enters at the left boundary of row $i$ and requires $j$ cycles to propagate right.
- B enters at the top boundary of column $j$ and requires $i$ cycles to propagate downward.

If every row and column injects item $k$ in the same cycle, unequal propagation distances cause off-diagonal PEs to receive the wrong $k$ pairing.

The current boundary-injection rules are:

- Inject $A[i][k]$ into row $i$ in cycle $i+k$.
- Inject $B[k][j]$ into column $j$ in cycle $j+k$.

At PE$(i,j)$:

- A arrives at $(i+k)+j$.
- B arrives at $(j+k)+i$.

Both are equal to:

$$
t(i,j,k)=i+j+k
$$

Thus $A[i][k]$ and $B[k][j]$ with the same $k$ meet at PE$(i,j)$ in the same cycle.

This delay compensates for different spatial propagation distances; it does not wait for a preceding PE to finish computing.

## 5. Indexed Scheduling in the Input Feeder

The baseline feeder has no internal sequential state and does not use a physical delay chain. It receives complete matrices, `enable`, and `cycle_idx=t`, then generates array boundary inputs through combinational indexing.

For A row $i$:

- When $i\le t<i+K$, output `a_matrix[i][t-i]` with valid equal to 1.
- In all other cycles, output 0 with valid equal to 0.

For B column $j$:

- When $j\le t<j+K$, output `b_matrix[t-j][j]` with valid equal to 1.
- In all other cycles, output 0 with valid equal to 0.

`enable` is driven by Controller `busy`. When `busy=0`, every boundary valid must be 0 even if `cycle_idx=0`, preventing accumulation outside an operation.

This implementation directly represents the $i+k$ and $j+k$ injection formulas and is well suited to verifying scheduling semantics. It may synthesize into large matrix-selection muxes; a future PPA comparison can evaluate a delay-register-chain feeder.

## 6. 2×2 Example

Let:

```text
A = [a b]    B = [e f]
    [c d]        [g h]
```

The correct result is:

- $C[0][0]=ae+bg$.
- $C[0][1]=af+bh$.
- $C[1][0]=ce+dg$.
- $C[1][1]=cf+dh$.

### 6.1 Boundary-Injection Timing

| Cycle | A row 0 | A row 1 | B column 0 | B column 1 |
|---:|---|---|---|---|
| 0 | a | invalid | e | invalid |
| 1 | b | c | g | f |
| 2 | invalid | d | invalid | h |
| 3 | invalid | invalid | invalid | invalid |

A row 1 is delayed by one cycle, as is B column 1. Valid must undergo the same delay as its data.

### 6.2 PE Computation Wavefront

| Cycle | PE00 | PE01 | PE10 | PE11 |
|---:|---|---|---|---|
| 0 | ae | idle | idle | idle |
| 1 | bg | af | ce | idle |
| 2 | idle | bh | dg | cf |
| 3 | idle | idle | idle | dh |

Compute activity propagates from the upper left toward the lower right as a wavefront:

- Cycles 0–1 are primarily fill.
- Cycles 2–3 are primarily drain.
- For larger $K$, each PE performs more consecutive MACs after the wavefront arrives, amortizing the fixed fill/drain cost.

## 7. Failure Mode Without Skew

If every row and column injects simultaneously:

| Cycle | A row 0 | A row 1 | B column 0 | B column 1 |
|---:|---|---|---|---|
| 0 | a | c | e | f |
| 1 | b | d | g | h |

The resulting computations are:

| PE | Actual accumulator | Correct result | Verdict |
|---|---|---|---|
| PE00 | $ae+bg$ | $ae+bg$ | correct |
| PE01 | $ah$ | $af+bh$ | incorrect |
| PE10 | $de$ | $ce+dg$ | incorrect |
| PE11 | $cf+dh$ | $cf+dh$ | correct |

PE00 and PE11 lie on the main diagonal, where A and B propagation distances match, so their pairing is correct by coincidence. PE01 and PE10 have unequal path lengths, causing operands from different $k$ values to arrive in the same cycle.

This example proves:

> The incorrect result is not a faulty MAC; boundary scheduling failed to compensate for spatial propagation delay.

## 8. First and Last Valid MAC

PE$(i,j)$ performs the MAC for item $k$ in cycle:

$$
t(i,j,k)=i+j+k
$$

Therefore:

- First valid MAC: $i+j$.
- Last valid MAC: $i+j+K-1$.
- PE$(0,0)$ starts first.
- PE$(N-1,N-1)$ finishes last.

From the first MAC in Cycle 0 through the final MAC, there are:

$$
T=K+2N-2
$$

cycles.

This document numbers the first MAC-capable cycle as Cycle 0. Future testbenches and performance accounting must use the same convention to avoid off-by-one errors.

In the top-level operation protocol, the rising edge that samples `start` only enters RUN and establishes `cycle_idx=0`. The following clock interval is Cycle 0, during which the feeder produces the first combinational outputs; the next rising edge commits the Cycle 0 MAC. The startup protocol therefore includes an additional `start`-acceptance edge, but this does not alter the computation-window definition above.

## 9. Ideal Array Utilization

During one operation, an $N \times N$ array has:

- $N^2$ PEs.
- $N^2K$ total valid MACs.
- A statistical window of $K+2N-2$ cycles.
- $N^2(K+2N-2)$ total PE-cycles.

Array-window utilization is therefore:

$$
U=\frac{N^2K}{N^2(K+2N-2)}=\frac{K}{K+2N-2}
$$

For $N=2$ and $K=2$:

$$
U=\frac{2}{2+4-2}=50\%
$$

This utilization reflects only fill/drain and spatial scheduling. It excludes practical effects such as:

- A feeder unable to sustain data delivery.
- Insufficient memory bandwidth.
- Backpressure or stalls.
- Idle cycles between operations.
- Clock-frequency changes with array size.

## 10. Dataflow Invariants

RTL and verification must preserve:

1. A advances right by exactly one cycle through each PE.
2. B advances downward by exactly one cycle through each PE.
3. Valid experiences exactly the same delay as its associated data.
4. One-sided valid A/B may still propagate independently.
5. The accumulator updates only when both valid signals are asserted.
6. PE$(i,j)$ accumulates only products belonging to $C[i][j]$.
7. Every PE performs exactly $K$ MACs in each operation.
8. In the stall-free baseline, MAC item $k$ occurs in cycle $i+j+k$.

Current verification status:

- Items 1–5 have cycle-by-cycle coverage in directed PE, bare-array, and feeder tests.
- Item 6 is covered by the end-to-end reference model across eight parameter configurations and 872 corner/random operations.
- Item 7 is checked directly by the hierarchical MAC-count monitor.
- Item 8, and the concrete $k$ identity in Item 6, are checked directly by the cycle-by-cycle pairing monitor. Inside the legal $k$ window it checks both valid signals and A/B values; outside the window it rejects coincident valid signals.

## 11. Frozen Boundary and Future Variants

The current baseline fixes:

- The feeder directly reads complete stable matrices supplied by the top level.
- Skew uses combinational indexing by `cycle_idx`.
- $K$ is independent of $N$.
- Wavefronts from consecutive operations cannot overlap.
- There is no stall or backpressure.

The baseline has completed regression for selected combinations of $N=1$, $N=2$, $N=4$ and $K=1$, $K=2$, $K=3$, $K=4$. This evidence covers the current parameter matrix; it is not a formal proof for arbitrary $N/K$ combinations.

Future questions not included in the baseline are:

- Whether a delay-register-chain feeder can reduce selection-mux cost.
- Whether consecutive operations can overlap as a pipeline.
- Whether adding stalls should freeze the entire array or add handshake and buffering to local links.
- How memory bandwidth changes the ideal utilization derived here.
