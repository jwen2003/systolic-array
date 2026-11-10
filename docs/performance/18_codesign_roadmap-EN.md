# Co-design Decisions and Follow-up Experiments

[English](18_codesign_roadmap-EN.md) | [简体中文](18_codesign_roadmap-zh_CN.md)


## 1. Current Decision

[Established] Lite→Burst→parallel packing now has controlled cycle, synthesis, and physical feedback. Under the unified packed/unpacked timing boundary, N2/K17 end-to-end time falls 115→57 cycles; the old packed regression's 62 cycles include a two-cycle preflight and ACK. The input-supply-gap experiment is also complete: at the tested g=3/7 points, waiting for data fully hides the L1/L16 transaction-overhead difference. Current packed1 passes the executed physical checks at Nangate45 typical, 2.500 ns, single corner, but no complete Pareto frontier is established.

The input-supply-gap experiment is complete. Sticky-DONE polling intervals are next, followed by double buffering and DMA. Only after these interface/scheduling experiments and a shared workload/counting convention are frozen does the project move to an independent OS-versus-WS dataflow comparison. Parallel packing is an implemented candidate, not a universal winner.

## 2. Fair Comparison and Pareto

Fix workload, numerical semantics, platform, I/O constraints and timing boundaries. First hold maximum Burst beats constant to isolate packing; later tune each implementation's L separately before comparing best candidates. Retain correctness, source/configuration and tool provenance.

Use models to prune clearly unfavorable points and RTL to calibrate survivors. Implement a few candidates under common physical constraints. Record cycles, area, achievable clock, critical path, buffering/congestion and verification status. A timing-violating point is not feasible at that target frequency.

$$T_{device}=C_{invocation}/f_{implemented}$$

Real Host elapsed time also includes preparation/submission/synchronization; overlapping phases are not simply additive. Pareto candidates are feasible points not dominated simultaneously in the chosen area/latency objectives. Do not invent energy without activity. Decode or mux critical paths can feed back into RTL and renewed verification; the frontier is iterative.

## 3. Conditional Mechanisms

| Mechanism | Trigger | Question |
|---|---|---|
| Sticky-DONE polling interval | Polling overlaps Core computation and policy changes visible control cost | How do fixed/increasing intervals trade response latency, read transactions, and full-task cycles? |
| Double buffering | Continuous tasks can overlap load and compute profitably | How much steady-state throughput justifies ownership/storage cost? |
| DMA | Host transfers/CPU occupancy limit the goal | Can autonomous movement reduce CPU involvement/overhead? It cannot create external bandwidth |
| Tiling | A selected workload exceeds shape/capacity | How to organize partial sums, scheduling, edges and reuse? |
| FPGA | Resource mapping or a real Host path needs verification | DSP/BRAM/timing differences; separate mapping from full board bring-up |

## 4. WS/OS and 2D→1D Dependencies

WS/OS starts after the current sticky-DONE polling-interval, double-buffering, and DMA experiments. At that point the comparison must fix shared numerical semantics, a reproducible OS baseline, selected workloads, and agreed movement/Buffer counters. Compare feeder, weight loading, partial-sum paths, and reuse, not just PE names or MAC count.

Time-space experiments require explicit PE/area budgets, the same task and correct temporal reuse/partial-sum storage. Predict before implementing a few points and compare latency, area, clock and bandwidth. 2D→1D mapping does not establish physical 3D stacking or an implemented 3D array.

The current sequence finishes the sticky-DONE polling, double-buffering, and DMA interface/scheduling experiments before independent dataflow comparisons, avoiding simultaneous interface/dataflow/resource changes that prevent attribution.

## 5. Network Mapping and Stop Conditions

Network mapping splits layers into tasks and chooses placement, reuse, partial sums, quantization and inter-layer dependencies. Begin with static software scheduling/analysis, adding RTL when a concrete bottleneck justifies it. Host INT32 accumulation cannot recover high bits already lost in an overflowing INT18 tile.

WS/OS and time-space work can complete a substantial microarchitecture study without requiring the full-NPU label. Before implementation the user proposes hypotheses/controls, models predict, RTL verifies/measures, and software/physical feedback revises the choice. Documents distinguish data, interpretations and hypotheses rather than precommitting every feature.
