# C++ Runtime, BFM and Reproduction

[English](14_runtime_bfm-EN.md) | [简体中文](14_runtime_bfm-zh_CN.md)


## 1. Layers and Actual Capability

`sim/wrapper/matmul_runtime.*` validates full hardware shape, loads A/B, starts, polls DONE, reads C and ACKs. `axi_lite_bfm.*` is the lower-layer Master driving handshakes and simulation time. This is Host Runtime plus BFM, not a Linux kernel driver.

Construction caches N/K/widths outside invocation timing. Inputs are row-major int8 vectors, outputs int32 containers for INT18 results. Invalid shape throws before any transaction. No automatic padding, tiling, overflow-risk rejection or retry exists.

Operational errors do not automatically reset, clear errors or ACK; state remains available for diagnosis. Do not blindly retry. A normal error response is consumed before throwing; a bus timeout requires reset recovery.

## 2. Shared Clock and Sampling

`sim/burst/axi_burst_bfm.*` drives both ports with one DUT/context/clock. step evaluates low, samples edge handshakes/responses, advances the rising edge, then returns low. Never use two independent ticking BFMs on one DUT.

`burst_write(addr, words, master_gap, response_hold, strobes)` supports optional per-beat byte masks, defaulting to 1 for old callers. Stalled VALID keeps payload, strobe and WLAST stable. last_transfer_cycle is the absolute final-W-handshake cycle, not B completion.

`sim/burst/main.cpp` and `sim/packed/main.cpp` are separate experimental drivers rather than extensions of the original Runtime. Packed main reuses old test helpers and is compiled instead of linking the old main. Software preparation is outside cycle timing.

## 3. Timing

Lite Runtime records preflight, load, start_poll, readback, ack, total and poll_reads. load includes INPUTS_READY read; start_poll includes the START bus transaction plus polling, not pure Core latency. total sums the phases. Reset, capability reads and Host preparation are excluded.

This is not an instruction-level Host CPU model. Measure real packing cost separately; simulation-host Python/C++ runtime is not a DUT cycle count.

## 4. Reproduction

With Verilator, make and C++17 installed, run from the repository:

```bash
bash scripts/run_wrapper_integration.sh
bash scripts/run_burst_comparison.sh
bash scripts/run_packed_comparison.sh
bash scripts/run_packed_comparison.sh 2 16
bash scripts/run_packed_comparison.sh 3 5
bash scripts/run_packed_comparison.sh 1 5
python3 models/wrapper/burst_load_model.py --self-test --non-load-cycles 38
python3 models/wrapper/packed_load_model.py --check-csv \
  build/wrapper/packed_comparison_n2k17/packed_comparison.csv
```

wrapper_integration runs an SV integration TB; burst/packed scripts run C++ drivers. Original Lite Runtime sources remain in sim/wrapper; historical local build artifacts are not portable entry points. V1 regression/synthesis/physical commands remain in the stage documents and require the full original repository and pinned tools; this documentation update does not rerun them.

Generated output goes to ignored build/wrapper/. reports/wrapper/ holds saved evidence snapshots. Moving docs does not change RTL build filelists.
