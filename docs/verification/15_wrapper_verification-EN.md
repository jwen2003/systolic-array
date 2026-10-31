# V2 Verification Matrix and Evidence Boundaries

[English](15_wrapper_verification-EN.md) | [简体中文](15_wrapper_verification-zh_CN.md)


## 1. Verification Layers

| Layer | Main evidence |
|---|---|
| Lite Slave unit TB | Arbitrary AW/W order, WSTRB, errors, B/R backpressure, response hold/reset |
| Device unit TB | Decode/permissions, maps, two tasks, error OR/W1C, result lifetime |
| Lite Top integration TB | Complete Slave→Device→Core path |
| C++ Lite Runtime | Shape rejection, load/invoke/readback, timing-phase sum |
| Dual-port Burst driver | Ownership, partial AW/W reservation, descriptor errors, held responses, two operations |
| Packed driver | Lane enables, cross-row alias readback, tails, incomplete maps, INT18 wrap and timing model |

Historical Lite Slave 84 and Burst Slave 132 unit checks are stage records, not added to the table below: tests overlap. V1's 872 operations are not V2 protocol coverage.

## 2. Reproducible Recorded Results

| Runner/configuration | Checks | Evidence |
|---|---:|---|
| run_burst_comparison, PACKED_ENABLE=0 | 1531 | build/wrapper/burst_comparison/simulation.log |
| Packed N2/K17 | 772 | reports/wrapper/packed/n2k17_simulation.log |
| Packed N2/K16 | 725 | reports/wrapper/packed/n2k16_simulation.log |
| Packed N3/K5 | 480 | reports/wrapper/packed/n3k5_simulation.log |
| Packed N1/K5 | 264 | reports/wrapper/packed/n1k5_simulation.log |

Total 3772 checks PASS under --assert -Wall without warning/error. These include shared helpers and repeated assertions, not 3772 independent scenarios. Four packed shapes cover 1/2/3/4 valid tail bytes. The independent Python model checks 24 packed RTL rows.

Old Burst driver measures 32 operations: 2 Lite, and 5 lengths×3 gaps×2=30 Burst. Each packed configuration measures 8 operations: 2 old L16 plus 2 for each of three packed lengths. Untimed readback replays and directed tests are not additional performance samples.

## 3. Packing Correctness

Write through packed aliases and compare every A/B element through old windows. Distinguishable neighboring values and signed bytes expose cross-row and sign-extension errors. Sparse WSTRB allows high lanes with lane0=0, preserving masked valid lanes. One missing final input keeps INPUTS_READY low and rejects START; filling it permits execution.

Out-of-range enabled tail bytes reject the whole beat without corrupting valid old data. Slave drains an out-of-range descriptor without Device attempts. Input writes are forbidden in RUN/DONE and C remains stable in DONE. C is compared against independent mathematical dot products with modulo 2^18. Performance is not accepted if correctness fails.

## 4. Limits

No formal AXI proof, exhaustive shapes, CDC, synchronous RAM adapter, randomized memory-system traffic or real CPU/DDR workload has been established. Packed continuous W acceptance is intentional; it is not artificially stalled. Held B, dual-writer arbitration and default-path regression do not exhaust all packed backpressure combinations.

V1 formal/physical gaps remain, see [V1 verification](04_verification_plan-EN.md). PASS counts above refer to retained reports; this documentation-only task does not claim to rerun RTL.
