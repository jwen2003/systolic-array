# Systolic Array: Compute Core and Software-Accessible Accelerator

[English](README.md) | [简体中文](README-zh_CN.md)

An RTL/microarchitecture project progressing from cycle-level output-stationary scheduling to AXI, on-chip input storage, command/status and C++ invocation, with models, verification and performance/physical evidence guiding tradeoffs.

## Current Version (2026-11-09)

- **Frozen V1 Core**: A[N][K]×B[K][N], N² PEs, signed INT8/INT18 wrap, independent N/K, skew pairing and K+2N-2 compute cycles.
- **Implemented/simulated V2 Wrapper**: Lite control/read/write, buffers/maps, LOAD/RUN/DONE, sticky errors/ACK, restricted AXI4 Burst writes and transaction ownership.
- **Measured V2 implementation**: constant-address decode for normal and packed windows, controlled Burst-length and packed/unpacked cycle comparisons, and Nangate45 packed0/packed1 RTL-to-GDS at 2.500 ns; the Core remains unchanged.
- C++ provides Host Runtime/BFM and experimental drivers, not a Linux kernel driver. Burst is not DMA.

Start with [docs index](docs/README.md), this current-status summary, [architecture](docs/wrapper/11_system_architecture-EN.md) and [register contract](docs/wrapper/12_register_contract-EN.md).

## Host-to-Core Invocation

Prepare A/B → Lite/Burst load → complete written maps → START → deterministic Core computation → persistent Device DONE → Lite read C → ACK/release/invalidate maps. Bus backpressure stops at Wrapper; no Core wavefront stall. C directly indexes Core psum without another result copy.

Responsibilities/ownership: [11](docs/wrapper/11_system_architecture-EN.md); AXI subset: [13](docs/wrapper/13_axi_protocol-EN.md). Original Runtime accepts only full hardware shape, with no automatic padding; the more general API in V1 document 10 remains an upstream abstraction.

## Established V2 Evidence

For N2/K17, unpacked Burst maximum lengths 1/2/4/8/16 measure 239/171/139/123/115 end-to-end cycles. Their pure A/B write costs are 204/136/104/88/80 cycles and follow `W beats + 2 × A/B write transactions` under the current continuously supplied BFM.

The controlled packed comparison uses the same `PACKED_ENABLE=1` Burst Top and maximum length 16 for both modes. Unpacked uses 6 transactions/68 W beats; packed uses 2 transactions/18 W beats. Pure writes fall 80→22 cycles, READY-confirmed load 82→24, end-to-end 115→57 (2.0175×), and the repeatable task including ACK 118→60. START-to-DONE remains 20 cycles.

| Physical comparison | Final functional area | Setup WNS | Hold WNS |
|---|---:|---:|---:|
| Same-batch Lite | 11,041.972 µm² | +0.161062 ns | +0.0128362 ns |
| Same-batch unpacked Burst | 12,159.914 µm² (+10.12%) | +0.172356 ns | +0.0123354 ns |
| Current Burst, `PACKED_ENABLE=0` | 12,002.412 µm² | +0.115657 ns | +0.004894 ns |
| Current Burst, `PACKED_ENABLE=1` | 12,924.984 µm² (+7.687%) | +0.149201 ns | +0.008039 ns |

The areas exclude filler/tap cells. Both packed runs use extracted parasitics and propagated clocks at Nangate45 typical, 2.500 ns. The repaired packed1 run has zero electrical violations, overflow, detailed-route DRC, OpenROAD antenna, and KLayout DRC items. See the consolidated [V2 results and reproduction chapter](docs/performance/19_v2_axi_burst_packed_results-EN.md); [Burst](docs/performance/16_burst_analysis-EN.md) and [packing](docs/performance/17_packed_analysis-EN.md) retain the earlier model and experiment history.

Functional regression, source-to-derived equivalence, and physical checks have distinct scopes. LVS and post-route formal equivalence remain unproven.

## Retained V1 Physical Tradeoffs

Nangate45 N2/K2 Core completed a 400–667 MHz sweep. At 400 MHz final functional area is 3522.64 µm², setup WNS +0.720010 ns, hold +0.065023 ns. 666.667 MHz is the highest passing tested target, not silicon Fmax.

Registered Boundary at 667 MHz reduces area by 3.97% and timing-repair buffers by 62.5%, but increases RUN from 4 to 5 cycles and reduces same-frequency non-overlap throughput 20%; baseline remains default. See [physical implementation](docs/implementation/07_physical_implementation_plan-EN.md) and [variant](docs/implementation/09_registered_boundary_ppa_analysis-EN.md). These are not V2 Wrapper numbers.

## Reproduction and Layout

```bash
bash scripts/run_wrapper_integration.sh
bash scripts/run_burst_comparison.sh
bash scripts/run_packed_comparison.sh
bash scripts/run_v2_packed_performance.sh
python3 scripts/check_docs.py
```

rtl/core holds frozen Core; rtl/wrapper the surrounding hardware; tb/core, tb/wrapper/unit and tb/integration separate Core, wrapper-unit and integration tests; sim/wrapper, burst and packed hold software/experiments; models/wrapper holds analytical models; reports/wrapper holds measurements. docs separates core, wrapper, software, verification, performance and implementation. build is generated output.

V1 regression/synthesis/physical commands and pinned tools/constraints remain in their stage documents and require the full original repository. This task updates documentation, not historical physical runs.

## Open Work

V2 now has single-corner mapped and routed evidence, but no real CPU/DDR/PCIe timing, trustworthy power, multi-corner signoff, LVS, post-route formal proof, or final Pareto result. Kepler CPU SIGILL and unproven post-route equivalence remain explicit; no commercial signoff is claimed.

The current sequence is sticky-DONE polling intervals, double buffering, and DMA, followed by independent OS-versus-WS and 2D→1D microarchitecture comparisons. See the [roadmap](docs/performance/18_codesign_roadmap-EN.md).

## License

MIT; retain the original repository LICENSE file.
