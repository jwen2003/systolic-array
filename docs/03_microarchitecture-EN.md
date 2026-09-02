# Systolic Array MVP: Microarchitecture

[English](03_microarchitecture-EN.md) | [简体中文](03_microarchitecture-zh_CN.md)

## 1. Document Status

- Status: third revision; the baseline microarchitecture is frozen, implemented, and passes the complete parameter regression matrix.
- Corresponding RTL: `rtl/systolic_pe.sv`, `rtl/systolic_array.sv`, `rtl/input_feeder.sv`, `rtl/systolic_controller.sv`, and `rtl/systolic_array_top.sv`.
- Purpose: record baseline state semantics, spatial topology, temporal scheduling, combinational paths, control protocol, and parameter constraints.

## 2. Baseline System Decomposition

| Module | Responsibility | Status |
|---|---|---|
| `systolic_pe` | Signed MAC, A/B forwarding, valid forwarding, local accumulator | Frozen and implemented |
| `input_feeder` | Matrix boundary supply and skew | Frozen and implemented |
| `systolic_array` | PE generation, neighbor interconnect, and result exposure | Frozen and implemented |
| `systolic_controller` | Operation start, clear, cycle count, and completion decision | Frozen and implemented |
| `systolic_array_top` | Integrates feeder, array, and controller | Frozen and implemented |

The top level receives complete matrices, which remain stable throughout an operation's `busy` interval. The baseline does not include a matrix-loading protocol, SRAM, DMA, or backpressure.

## 3. PE Responsibilities

The PE performs two independent jobs:

1. Data transport: forward A right and B downward.
2. Local computation: when both valid signals are asserted, accumulate $A \times B$ into the local partial sum.

The PE does not perform matrix-coordinate interpretation, $k$ tracking, one-sided operand waiting, global completion detection, saturation, rounding, or output quantization.

## 4. PE Interface

```systemverilog
module systolic_pe #(
    parameter int DATA_W = 8,
    parameter int ACC_W  = 18
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     acc_clear,

    input  logic signed [DATA_W-1:0] a_in,
    input  logic                     a_valid_in,
    input  logic signed [DATA_W-1:0] b_in,
    input  logic                     b_valid_in,

    output logic signed [DATA_W-1:0] a_out,
    output logic                     a_valid_out,
    output logic signed [DATA_W-1:0] b_out,
    output logic                     b_valid_out,

    output logic signed [ACC_W-1:0]  psum_out
);
```

### 4.1 Interface Semantics

| Signal | Semantics |
|---|---|
| `clk` | Rising-edge clock for all registered PE state |
| `rst_n` | Synchronous active-low reset |
| `acc_clear` | Begins a new local accumulation; does not block A/B forwarding |
| `a_in` | A data arriving from the left or row boundary in the current cycle |
| `a_valid_in` | Qualifies `a_in` for computation and propagation in the current cycle |
| `b_in` | B data arriving from above or the column boundary in the current cycle |
| `b_valid_in` | Qualifies `b_in` for computation and propagation in the current cycle |
| `a_out` | Registered A data sampled by the right PE on the next cycle |
| `a_valid_out` | Valid aligned with `a_out` |
| `b_out` | Registered B data sampled by the lower PE on the next cycle |
| `b_valid_out` | Valid aligned with `b_out` |
| `psum_out` | Output-stationary accumulator owned by this PE |

The current PE has no `ready`, `stall`, or `psum_valid_out`. The system Controller determines completion from the fixed computation window.

## 5. Internal PE State

The PE stores five registered values: `a_out`, `a_valid_out`, `b_out`, `b_valid_out`, and `psum_out`.

`a_in` and `b_in` are module inputs, not internal PE state. `product` and `product_ext` are current-cycle combinational results and are not stored across cycles.

## 6. Datapath

The baseline combinational path is:

```text
a_in, b_in
    │
    ▼
signed multiplier
    │ product
    ▼
sign extension
    │ product_ext
    ▼
adder with old psum
    │
    ▼
psum_out register
```

A/B forwarding is independent of the MAC:

```text
a_in ──► a_out register ──► right PE
b_in ──► b_out register ──► lower PE
```

The expected critical path in the baseline PE is therefore multiplier → adder → accumulator register. A future product pipeline register would change PE latency, valid alignment, array completion timing, and PPA, and must be reverified as a separate microarchitecture variant.

## 7. Width and Signed Semantics

### 7.1 Product Width

The full product of two signed `DATA_W`-bit inputs has width:

$$
PROD\_W=2\times DATA\_W
$$

With default `DATA_W = 8`, `PROD_W = 16`. The 8-bit signed range is $[-128,127]$, and the maximum positive product is:

$$
(-128)\times(-128)=16384
$$

A signed 15-bit value can represent at most 16383, so the full product requires a signed 16-bit representation.

### 7.2 Accumulator Width

The default MVP accumulates at most four products. The maximum positive sum is:

$$
4\times16384=65536
$$

A signed 17-bit value has a maximum positive value of 65535, so the default is `ACC_W = 18`.

This conclusion guarantees extreme-value accumulation only for $K\le4$. Larger future $K$ values require a new `ACC_W` derivation rather than relying on the default.

### 7.3 Explicit Sign Extension

Before the 16-bit `product` enters the 18-bit accumulator addition, its sign bit is replicated through `ACC_W`. Positive values receive leading zeros and negative values leading ones, preserving their numerical value.

The current RTL parameter constraint is:

$$
ACC\_W \ge 2\times DATA\_W
$$

This only guarantees that the accumulator can hold one full product; it does not guarantee overflow-free accumulation for arbitrary $K$.

## 8. Per-Cycle Forwarding

After reset release, every rising edge performs:

```text
a_out       <- a_in
a_valid_out <- a_valid_in
b_out       <- b_in
b_valid_out <- b_valid_in
```

| A valid | B valid | Forward A | Forward B | Perform MAC |
|---:|---:|---:|---:|---:|
| 0 | 0 | no | no | no |
| 1 | 0 | yes | no | no |
| 0 | 1 | no | yes | no |
| 1 | 1 | yes | yes | yes |

When valid is 0, the corresponding data register may still sample the port value, but that value has no meaning and downstream logic must ignore it through valid.

## 9. Accumulator Update Semantics

Define:

`mac_valid = a_valid_in && b_valid_in`

Update priority is:

1. `!rst_n`.
2. `acc_clear`.
3. `mac_valid`.
4. Hold the previous value.

| `rst_n` | `acc_clear` | `mac_valid` | `psum_out_next` |
|---:|---:|---:|---|
| 0 | X | X | 0 |
| 1 | 1 | 0 | 0 |
| 1 | 1 | 1 | `product_ext` |
| 1 | 0 | 1 | `psum_out + product_ext` |
| 1 | 0 | 0 | hold `psum_out` |

When `acc_clear` coincides with a valid MAC, the old accumulator is discarded before the current product begins the new accumulation. The new value is `product_ext`, not 0 and not the old value plus the product.

## 10. Reset Semantics

`rst_n` is a synchronous active-low reset sampled only on `posedge clk`. Reset clears the A/B forwarding data registers, A/B valid registers, and accumulator.

Reset has priority over forwarding, clear, and MAC. If `rst_n = 0`, current inputs are neither forwarded nor computed. Every registered baseline module uses synchronous active-low reset; the combinational feeder stores no reset state.

## 11. Mapping to Current RTL

`rtl/systolic_pe.sv` implements:

- `PROD_W = 2 * DATA_W`.
- Signed combinational multiplication.
- Explicit product sign extension.
- Parameter checks for `DATA_W > 0` and `ACC_W >= PROD_W`.
- Independent A/B data and valid forwarding.
- First-MAC acceptance in the same cycle as clear.
- Accumulator hold without both valid signals.

Code comments are fixed to English; design and verification documentation uses Chinese.

## 12. PE Verification Status and Future Assertions

The directed PE testbench passes 17 checks covering:

1. Synchronous reset clearing all state.
2. Multiplication by 0.
3. Positive times positive.
4. Positive times negative.
5. Negative times negative.
6. The `-128 * -128` extreme.
7. Multiple consecutive valid MACs.
8. A-only valid.
9. B-only valid.
10. Accumulator hold when both inputs are invalid.
11. Clear with both inputs invalid.
12. Clear coincident with a valid MAC.
13. Exactly one-cycle valid/data forwarding latency.
14. Reset priority over clear and MAC.

Future key assertions should still freeze these properties:

- Without clear or both valid signals, the accumulator does not change.
- A/B outputs and their valid signals equal the corresponding previous-cycle inputs.
- After clear coincides with both valid signals, the accumulator equals the previous-cycle input product.
- After reset is sampled, all registered output state is 0.

## 13. Bare-Array Microarchitecture

`systolic_array` is a parameterized $N \times N$ PE fabric expressing only spatial topology. It does not store complete matrices, generate skew, or interpret operation start/end.

### 13.1 Boundary Interface

| Port | Semantics |
|---|---|
| `a_left[i]` | A data entering row $i$ from the left boundary |
| `a_valid_left[i]` | Valid aligned with `a_left[i]` |
| `b_top[j]` | B data entering column $j$ from the top boundary |
| `b_valid_top[j]` | Valid aligned with `b_top[j]` |
| `psum[i][j]` | Local accumulator of $\mathrm{PE}(i,j)$ |
| `acc_clear` | Accumulator clear broadcast to every PE in the same cycle |

Boundary inputs must already contain the correct cycle-level skew. The bare array does not repair incorrect pairing.

### 13.2 A Neighbor Rule

For $\mathrm{PE}(i,j)$, A comes from `a_left[i]` when $j=0$, and from `a_out` of $\mathrm{PE}(i,j-1)$ when $j>0$. A valid always propagates along exactly the same path.

### 13.3 B Neighbor Rule

For $\mathrm{PE}(i,j)$, B comes from `b_top[j]` when $i=0$, and from `b_out` of $\mathrm{PE}(i-1,j)$ when $i>0$. B valid always propagates along exactly the same path.

### 13.4 Internal Wiring

The array uses four two-dimensional pipe arrays that include both boundary positions:

```systemverilog
logic signed [DATA_W-1:0] a_pipe       [N-1:0][N:0];
logic                     a_valid_pipe [N-1:0][N:0];
logic signed [DATA_W-1:0] b_pipe       [N:0][N-1:0];
logic                     b_valid_pipe [N:0][N-1:0];
```

For A, `a_pipe[i][0]` receives `a_left[i]`; $\mathrm{PE}(i,j)$ reads `a_pipe[i][j]` and writes `a_pipe[i][j+1]`. For B, `b_pipe[0][j]` receives `b_top[j]`; $\mathrm{PE}(i,j)$ reads `b_pipe[i][j]` and writes `b_pipe[i+1][j]`. Valid uses identical indexing.

For $N=1$, this representation still retains the complete input boundary → PE → output boundary path, rather than creating link arrays used only by neighbors and completely unused in a single-PE configuration. The terminal A position on the right and B position at the bottom are not exposed as ports and do not participate in result computation. Matrix results are exposed directly through `psum[i][j]`.

### 13.5 Global Control Signals

All PEs share `clk`, `rst_n`, and `acc_clear`. `acc_clear` is broadcast directly without array-internal delay. The Controller guarantees that this broadcast and Cycle 0 boundary inputs obey the frozen same-cycle clear/MAC semantics.

## 14. Feeder, Controller, and System Top

The baseline feeder is a combinational indexed scheduler and does not store matrices. In cycle $t$, row $i$ injects `A[i][t-i]` when $i\le t<i+K$; column $j$ injects `B[t-j][j]` when $j\le t<j+K$. With `enable=0`, all boundary valid signals and invalid-lane data are 0.

After sampling `start=1` on an IDLE rising edge, the Controller enters RUN with `cycle_idx=0` after the edge. Cycle 0 both broadcasts `acc_clear=1` and permits the first MACs. The total computation window is:

$$
TOTAL\_CYCLES=K+2N-2
$$

After the rising edge that commits `LAST_CYCLE=K+2N-3`, `done=1`, `busy=0`, and every result is valid. `done` is a one-cycle pulse; `start` during RUN is ignored.

The system top uses `busy` as feeder `enable`, broadcasts Controller `acc_clear` to the bare array, and directly exposes every `result[i][j]`. Overlapped consecutive wavefronts, a matrix-write protocol, indexed result reads, and ready/valid backpressure remain unsupported extensions outside the baseline.

## 15. Current Implementation and Verification Checkpoint

All five baseline RTL modules compile and pass directed regression under Verilator 5.032 `--Wall`. Parameterized random top-level regression covers eight configurations—$N/K=1/1,2/1,1/2,2/2,4/2,2/3,2/4,4/4$. Each runs 9 deterministic corner cases and 100 fixed-seed random operations, for 872 parameterized operations.

A hierarchical monitor directly observes `a_valid_pe_in && b_valid_pe_in` for each PE and checks after completion that each PE's MAC count equals $K$. The monitor does not modify the synthesizable datapath.

The cycle-by-cycle pairing monitor computes $k=t-i-j$ for global Cycle $t$. When $0\le k<K$, it checks $\mathrm{PE}(i,j)$ inputs against `A[i][k]` and `B[k][j]`; without a legal $k$, it rejects coincident valid signals. The monitor passes eight configurations and 872 operations without modifying the synthesizable datapath.

The parameterized end-to-end TB includes system protocol monitors covering Controller count/completion transitions, the one-cycle `done`, `done`/`busy` mutual exclusion, the `acc_clear` definition, idle feeder valid, all PE state after synchronous reset, and input-matrix stability during RUN. These checks and nine deterministic corner-case classes pass across eight configurations under the unified regression script.

The baseline has completed generic synthesis and Nangate45 N2/K2 RTL-to-GDS and remains the default implementation. The independent Registered Boundary variant adds one stage of A/B data/valid registers between the Feeder and Array and uses a separate Controller and Top; it does not alter baseline RTL and is retained as a timing-closure and implementation-cost tradeoff experiment. AXI, DMA, a runtime, streaming, and backpressure remain outside the current MVP. The logical minimal software contract is frozen, but no CPU-accessible interface has been implemented.
