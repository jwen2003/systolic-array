# INT8 Packing, Parallel Writes and Cycle Comparison

[English](17_packed_analysis-EN.md) | [简体中文](17_packed_analysis-zh_CN.md)

## Scope and hypothesis

Frozen V1 Core. Compare the old one-INT8-per-word Burst path against dense
four-INT8-per-word writes, using the same input values, shape, maximum Burst
length (in beats), continuous preprepared Master payloads, control/poll/readback
flow and one clock. No DMA, FIFO, overlap, result packing or software preparation
cost is included. This is an RTL cycle comparison, not CPU/DDR performance.

Hypothesis: reducing transfer beats AND committing four enabled lanes per clock
reduces load latency. Physical area/frequency and real Host packing cost remain
unmeasured; no Pareto or wall-time conclusion is established.

## Compatible address aliases

`PACKED_ENABLE` defaults to 0 on Device, Burst Slave and Burst Top. The new
runner enables all through Top. Old software and old windows retain their meaning.

| Window | Meaning |
|---|---|
| 0x1000 + 4*p | Original single A element, only WSTRB[0] writes |
| 0x2000 + 4*p | Original single B element, only WSTRB[0] writes |
| 0x4000 + 4*q | Packed A elements 4*q through 4*q+3 |
| 0x5000 + 4*q | Packed B elements 4*q through 4*q+3 |

Packed aliases are write-only, accessible through Lite or Burst. Read individual
inputs using the original windows in LOAD. Both aliases share storage and written
maps; there is no second matrix copy. No new enable register or capability CSR
is added: the experiment host knows the elaborated PACKED_ENABLE setting.

Each WDATA byte lane l writes element p=(address-packed_base)+l iff WSTRB[l].
A maps p -> [p/K][p%K]; B maps p -> [p/N][p%N]. Packing crosses rows without
padding. Lane 0 is WDATA[7:0]. Byte values are interpreted as signed INT8 only
when stored/used; sign extension must not contaminate adjacent bytes in C++.

Packed window capacity is rounded up to `4*ceil(N*K/4)` bytes for AXI word
transactions. An asserted lane whose element index is >=N*K rejects the entire
beat with SLVERR and sticky INVALID_ADDRESS. Masked padding is permitted and
has no storage/map bit. Sparse strobes and zero strobes follow ordinary lane
semantics. An invalid beat cannot partially update its in-range lanes.

Alignment and LOAD ownership checks remain enforced even with zero strobes.
Out-of-range AW descriptors are drained without Device attempts. Successful
previous beats remain committed after a later error; no transaction rollback.
A final Device error is included in BRESP. Reset/ACK clear maps as before.

## Physical implementation intent

The current Buffer is the Device's register arrays. Four nonoverlapping enabled
bytes update at the same edge, with four corresponding written-map bits. This
is not a claim of four-port SRAM inference. A future SRAM/FPGA RAM mapping must
revisit width, banking and the Core's full-matrix read interface. Extra address
and write decoding can affect area/timing.

## Analytical model and counting boundaries

Let W=ceil(N*K/4), D=2*W, and B=2*ceil(W/L). Under continuous data and no
contention, each Burst takes one AW cycle, its data cycles, then one B cycle.

- Last data commit: D+2*B-1 cycles from load start.
- All write responses consumed: D+2*B cycles.
- Host confirms INPUTS_READY by a 2-cycle Lite read: D+2*B+2 cycles.

The prior discussion's 22-cycle prediction refers to write-transaction completion,
not the exact INPUTS_READY assertion edge. N2/K17/L16 predicts 21/22/24 for these
three boundaries. The older load CSV includes the final status read: compare 24
with 82, not 22 with 82. The unpacked corresponding commit/response boundaries
are 79/80 cycles. BFM last-W timestamps identify commits because this Device
commits every valid granted beat immediately, with no pending write FIFO.

Full invocation includes preflight status, load including final ready check,
START, polling, C readback and ACK. Reset, readback validation replays, correctness
checks after timing, and C++ preparation are outside that window. No arbitrary
nanosecond scale is inferred from the BFM's simulation time increments.

## Reproduction and checks

Run from any working directory:

```bash
bash scripts/run_packed_comparison.sh         # N2 K17
bash scripts/run_packed_comparison.sh 2 16    # four valid tail lanes
bash scripts/run_packed_comparison.sh 3 5     # three valid tail lanes, cross-row
bash scripts/run_packed_comparison.sh 1 5     # one valid tail lane
bash scripts/run_burst_comparison.sh         # PACKED_ENABLE=0 full old benchmark
```

Requires Verilator, make, C++17 compiler; --assert -Wall with fatal warnings.
Outputs go to build/wrapper/packed_comparison_nNkK/. Each packed run covers old
arbitration/error tests, two old L16 operations, six measured packed operations
(L=1,4,16, two datasets), and six untimed readback replay operations. There is no
reset between the two measured operations of a setting. Replay uses START/DONE/
ACK to clear written maps after checking every A/B element through old windows.

Public-pin tests cover independent lane enables (including lane0 disabled),
negative values, masked-byte preservation, aliases, missing input rejection,
invalid tail atomicity, invalid descriptors, alignment, shared reset, DONE snapshot,
LOAD ownership, held responses, independent INT18 wrap matmul golden, and legacy
arbitration. Packed W backpressure is not artificially injected: the immediate
register write path is expected to accept continuously while it owns the port.

The experimental main reuses old test/golden helpers via the existing benchmark
source with its entry renamed; it is compiled instead of the old main, never
alongside it. A future test-library extraction can remove that source inclusion.
BFM gained optional per-beat strobes; existing callers retain default strobe 1.

Compare analytical predictions independently:

```bash
python3 models/wrapper/packed_load_model.py --check-csv \
  build/wrapper/packed_comparison_n2k17/packed_comparison.csv
```

Reports under reports/wrapper/packed/ are measurement snapshots, not model-only
projections. See the evidence links below for observed values and verification counts.

## Observed Results and Evidence

N2/K17, continuous supply, L16:

| Boundary | Unpacked | Packed |
|---|---:|---:|
| Final data commit | 79 | 21 |
| Write responses consumed | 80 | 22 |
| Software-confirmed ready | 82 | 24 |
| Full invocation including ACK | 120 | 62 |

Packed final-W timestamps and response/confirmation cycles are observed in BFM.
Unpacked commit/response values 79/80 follow its verified immediate write path
and H=2; its original CSV directly records 82/120. At matching confirmed-load
boundaries, reduction is 70.73%; full invocation reduction is 48.33%, in cycles
at the same assumed clock, excluding packing preparation. No physical speedup
or energy conclusion is established.

[Packed measurement CSV](../../reports/wrapper/packed/n2k17_packed_comparison.csv),
[unpacked reference CSV](../../reports/wrapper/packed/n2k17_unpacked_reference.csv),
[recorded results and checks](../../reports/wrapper/packed/results.md).

Model/implementation correspondence confirms the predicted mechanism for this
register-buffer architecture. Serial unpacking/FIFO is not an RTL-measured
competitor. Real software preparation and physical feedback remain next steps.


**Current comparison limitation:** identical inputs are the intended control, but existing old/new driver paths use different numerical patterns. Shape, precision, supply and invocation policy match. Latency control is value-independent and golden checks validate each path; exact shared-A/B paired replay remains a follow-up, particularly before activity-power comparisons.
