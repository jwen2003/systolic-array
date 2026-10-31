# Systolic Array: Compute Core and Software-Accessible Accelerator

[English](README.md) | [简体中文](README-zh_CN.md)

An RTL/microarchitecture project progressing from cycle-level output-stationary scheduling to AXI, on-chip input storage, command/status and C++ invocation, with models, verification and performance/physical evidence guiding tradeoffs.

## Current Version (2026-10-30)

- **Frozen V1 Core**: A[N][K]×B[K][N], N² PEs, signed INT8/INT18 wrap, independent N/K, skew pairing and K+2N-2 compute cycles.
- **Implemented/simulated V2 Wrapper**: Lite control/read/write, buffers/maps, LOAD/RUN/DONE, sticky errors/ACK, restricted AXI4 Burst writes and transaction ownership.
- **RTL-validated packing experiment**: optional aliases, up to four INT8 lane writes per clock; unchanged Core.
- C++ provides Host Runtime/BFM and experimental drivers, not a Linux kernel driver. Burst is not DMA.

Start with [docs index](docs/README.md), this current-status summary, [architecture](docs/wrapper/11_system_architecture-EN.md) and [register contract](docs/wrapper/12_register_contract-EN.md).

## Host-to-Core Invocation

Prepare A/B → Lite/Burst load → complete written maps → START → deterministic Core computation → persistent Device DONE → Lite read C → ACK/release/invalidate maps. Bus backpressure stops at Wrapper; no Core wavefront stall. C directly indexes Core psum without another result copy.

Responsibilities/ownership: [11](docs/wrapper/11_system_architecture-EN.md); AXI subset: [13](docs/wrapper/13_axi_protocol-EN.md). Original Runtime accepts only full hardware shape, with no automatic padding; the more general API in V1 document 10 remains an upstream abstraction.

## Established Performance Evidence

N2/K17, continuous supply and same assumed clock, software-confirmed-ready load boundary:

| Scheme | Load cycles | Invocation cycles including ACK |
|---|---:|---:|
| Lite on dual Top | 206 | 244 |
| Unpacked Burst L16 | 82 | 120 |
| Parallel-packed Burst L16 | 24 | 62 |

Packed final commit/response/confirmation occur at 21/22/24. Use matching end points. Old/new drivers use different numerical patterns; current control latency is value-independent and each result has golden checks. Exact paired inputs and real preparation cost remain follow-ups. See [Burst](docs/performance/16_burst_analysis-EN.md) and [packing](docs/performance/17_packed_analysis-EN.md).

Four packed shapes plus old Burst regression total 3772 checks; the independent model matches 24 packed RTL rows. Repeated helper checks are not independent scenarios. V1's 872 operations and 843/843 frontend equivalence are separate evidence.

## Retained V1 Physical Tradeoffs

Nangate45 N2/K2 Core completed a 400–667 MHz sweep. At 400 MHz final functional area is 3522.64 µm², setup WNS +0.720010 ns, hold +0.065023 ns. 666.667 MHz is the highest passing tested target, not silicon Fmax.

Registered Boundary at 667 MHz reduces area by 3.97% and timing-repair buffers by 62.5%, but increases RUN from 4 to 5 cycles and reduces same-frequency non-overlap throughput 20%; baseline remains default. See [physical implementation](docs/implementation/07_physical_implementation_plan-EN.md) and [variant](docs/implementation/09_registered_boundary_ppa_analysis-EN.md). These are not V2 Wrapper numbers.

## Reproduction and Layout

```bash
bash scripts/run_wrapper_integration.sh
bash scripts/run_burst_comparison.sh
bash scripts/run_packed_comparison.sh
python3 scripts/check_docs.py
```

rtl/core holds frozen Core; rtl/wrapper the surrounding hardware; tb/core, tb/wrapper/unit and tb/integration separate Core, wrapper-unit and integration tests; sim/wrapper, burst and packed hold software/experiments; models/wrapper holds analytical models; reports/wrapper holds measurements. docs separates core, wrapper, software, verification, performance and implementation. build is generated output.

V1 regression/synthesis/physical commands and pinned tools/constraints remain in their stage documents and require the full original repository. This task updates documentation, not historical physical runs.

## Open Work

V2 has no backend area/clock, real CPU/DDR/PCIe timing, trustworthy power or final Pareto result. Post-synthesis inconclusive equivalence, Kepler CPU SIGILL and unproven post-route equivalence remain explicit; no commercial signoff is claimed.

Reproduce and understand contracts/models, then use preparation cost and physical feedback to select candidates. DMA/double buffering are bottleneck-triggered; WS/OS and 2D→1D are future independent microarchitecture experiments. See [roadmap](docs/performance/18_codesign_roadmap-EN.md).

## License

MIT; retain the original repository LICENSE file.
