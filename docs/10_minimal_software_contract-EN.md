# Systolic Array MVP: Minimal Software Contract

[English](10_minimal_software_contract-EN.md) | [简体中文](10_minimal_software_contract-zh_CN.md)

## 1. Purpose and Status

[Established RTL fact] The MVP defines Matmul dataflow, fixed-point arithmetic, `start/busy/done`, and parameterized hardware shape. Its parallel unpacked-array Top is not a CPU-accessible device interface.

[Frozen software abstraction] This logical software contract works backward from a reasonable Matmul call to freeze shape, dtype, layout, overflow, command, and status semantics, mapping one workload to one hardware operation.

[Future work] This is not an implemented C ABI, driver, runtime, or memory-mapped interface, and does not expand the MVP into a full accelerator software stack.

## 2. Logical API and Configuration

```text
status = systolic_matmul_execute(config, A, B, C)
```

This describes behavior, not an existing symbol or ABI:

```text
config:
    hardware_n
    hardware_k
    logical_m
    logical_n
    logical_k
    input_dtype
    accumulator_dtype
    layout
    overflow_policy
```

The array is square `hardware_n × hardware_n`. `hardware_n`, `hardware_k`, `DATA_W`, and `ACC_W` are elaboration-time parameters and cannot change at runtime. Logical dimensions describe only the workload mapped onto the instance. To avoid ambiguity, later equations use $P=logical_n$ for output columns. The MVP is not arbitrary-shape dynamic hardware.

## 3. Data and Shape Contract

$$
A\in\mathbb{Z}^{M\times K_{logical}},\qquad
B\in\mathbb{Z}^{K_{logical}\times P},\qquad
C\in\mathbb{Z}^{M\times P}
$$

$$
1\le M\le hardware\_n,\qquad
1\le P\le hardware\_n,\qquad
1\le K_{logical}\le hardware\_k
$$

Software constructs hardware A of `hardware_n × hardware_k`, B of `hardware_k × hardware_n`, and C of `hardware_n × hardware_n`; zero-pads unused A/B entries; and returns only the leading `M × P` region. Larger workloads return `UNSUPPORTED_SHAPE`; tiling is not part of this contract. Zero padding is mathematically valid because the Controller still executes exactly `hardware_k` MACs and padded products are zero.

## 4. Layout and Dtype

A, B, and C host buffers are row-major. A/B are signed two's-complement `int8`; hardware accumulator/result is signed two's-complement `int18`; software receives sign-extended results in an `int32` C container. RTL unpacked-array ports do not define a memory layout or bus protocol. There is no scale, zero point, rounding, requantization, or saturation; this is not a quantized-neural-network API. A future AXI/DMA path must preserve logical order or explicitly transform layout.

## 5. Arithmetic and Overflow

Hardware computes the full signed $8\times8$ product into a fixed 18-bit accumulator. Values outside $[-131072,131071]$ follow fixed-width two's-complement wraparound; there is no overflow flag, saturation, or exception.

Two software policies are frozen:

1. `RAW_WRAP` exposes exact RTL wraparound.
2. `REJECT_OVERFLOW_RISK` is a future wrapper check performed before start; inability to guarantee an 18-bit result returns `ACCUMULATOR_OVERFLOW_RISK`. This is not implemented in RTL.

```text
sum_abs_bound(i,j) =
    sum over k of abs(A[i][k]) * abs(B[k][j])
```

The wrapper rejects if any bound exceeds 131071. This symmetric conservative rule may reject a legal result that relies on sign cancellation. A future runtime may use a more exact check but cannot change `RAW_WRAP` hardware semantics.

## 6. Command and Status Contract

```text
IDLE
RUN
DONE_EVENT
```

One operation proceeds as follows:

1. Confirm `busy == 0`.
2. Establish complete A/B hardware views.
3. Pulse `start` for one cycle.
4. Accept start on an idle sampling edge.
5. Keep A/B stable while `busy == 1`.
6. Wait for one-cycle `done`.
7. Observe final `psum` with `done`.
8. Read C.
9. Retain results until the next accepted operation clears accumulators.

Hardware ignores another start during RUN. A proper wrapper must detect busy and return `BUSY`, not report an ignored request as accepted. There is no queue, ready/valid command channel, operation ID, or overlap. `done` is an event, not persistent state; a real register interface may need sticky completion status.

## 7. Cycle Contract

Baseline default:

```text
TOTAL_RUN_CYCLES = hardware_k + 2*hardware_n - 2
```

Registered Boundary experiment:

```text
TOTAL_RUN_CYCLES = hardware_k + 2*hardware_n - 1
```

RUN counting begins after accepted start. Baseline implements the default contract; Registered Boundary adds one latency cycle. These formulas cover only the device RUN window—not buffer preparation, copies, polling, interrupts, or result movement—so MVP numbers are not complete-system throughput.

## 8. Abstract Status Codes

These are software abstractions, not existing RTL pins or registers:

| Status | Condition |
|---|---|
| `OK` | Accepted and completed; valid C region can be returned |
| `BUSY` | Hardware is running; wrapper does not issue start |
| `INVALID_SHAPE` | Missing, nonpositive, or mutually incompatible dimensions |
| `UNSUPPORTED_SHAPE` | Valid logical shape exceeds hardware N or K |
| `INVALID_DTYPE` | Dtype violates int8/int18 contract |
| `INVALID_LAYOUT` | Buffer is not row-major and no conversion is provided |
| `ACCUMULATOR_OVERFLOW_RISK` | Conservative policy cannot guarantee int18 safety |
| `NOT_READY` | Device uninitialized/in reset or result incomplete |
| `UNSUPPORTED_OPERATION` | Request is not supported Matmul behavior |

## 9. Mapping Examples

### 9.1 Exact N2/K2

A and B are both $2\times2$, no padding is needed, and all of C is returned. Baseline RUN cycles are $2+2\times2-2=4$.

### 9.2 N2/K2 Executes $1\times2$ by $2\times1$

Set `logical_m=1`, `logical_n=1`, and `logical_k=2`; zero-pad A's second row and B's second column; return only `C[0][0]`.

### 9.3 Rejected Shape

N2/K2 receiving `logical_m=3` or `logical_k=3` returns `UNSUPPORTED_SHAPE`; no automatic tiling occurs.

### 9.4 Overflow Policies

Two terms of `127 × 127` have bound $2\times16129=32258$, so both policies execute. For a larger future `hardware_k` whose bound exceeds 131071, `RAW_WRAP` executes with int18 wraparound, while `REJECT_OVERFLOW_RISK` returns before start. The latter is software policy, not hardware protection.

## 10. Codesign Conclusions

1. The array-port Top supports RTL verification and physical implementation, not direct software access.
2. Software must check busy, but hardware has no ready or explicit rejection response.
3. One-cycle done suggests sticky status in a future register interface.
4. Result hold aids reads, but the next operation overwrites old results.
5. Elaboration-time N/K requires padding, multiple instances, or future tiling for arbitrary shapes.
6. The int18 accumulator has no overflow status, requiring an explicit software safety policy.
7. These are future design inputs and do not require changes to frozen baseline RTL.

## 11. Out of Scope and Future Stages

This contract does not define AXI, DMA, NoC, a register map, interrupts, cache coherency, ready/valid streaming, backpressure, double buffering, operation overlap, arbitrary-size tiling, compiler integration, a complete runtime, end-to-end movement performance, or a power model.

- S3: streaming boundary and backpressure.
- S4: minimal runtime and tiling/scheduling.
- S5: end-to-end performance and data-movement analysis.

## 12. MVP Freeze Decision

The software-visible mathematical semantics, shape/dtype/layout, overflow, command/status, and cycle contract are frozen. No software stack or CPU-accessible interface is claimed implemented. This logical contract is sufficient upstream input for a future runtime or device interface, and the MVP can proceed to release audit.
