# V2 Dual-Bank 32-bit C Burst Read Experiment

[English](21_dual_bank_c_burst_read_experiment-EN.md) | [简体中文](21_dual_bank_c_burst_read_experiment-zh_CN.md)

## Interface contract

`systolic_axi_dual_bank_burst_read_top` is an experimental extension of `systolic_axi_dual_bank_top`. It retains Lite control/status/C reads, START0/START1, one result buffer, and packed A/B Burst writes. A dedicated C AR/R channel is added; it does not replace or modify the Lite baseline.

The C channel supports one outstanding aligned 32-bit INCR request of 1--16 beats (`ARSIZE=2`, `ARBURST=INCR`). The C window remains at `0x3000`, uses row-major order, and returns one sign-extended signed INT18 result in each 32-bit beat. AR acceptance validates the complete range, the C-window end, the 4 KiB boundary, address overflow, request type, length, and the pre-edge result-available state. Invalid requests return zero data with `SLVERR` for exactly `ARLEN+1` beats and assert `RLAST` only on the requested final beat.

`RVALID` is independent of `RREADY`. While stalled, `RVALID`, `RDATA`, `RRESP`, and `RLAST` remain stable; only an R handshake advances the beat. With no backpressure, beats are continuous within a Burst. The next AR is accepted only after the preceding final R handshake, so this first implementation has a measured one-cycle empty boundary between Bursts.

The single result remains owned from legal AR acceptance through the final R handshake. ACK is rejected during that interval. A legal AR wins over a simultaneous ACK. On a simultaneous final R handshake and ACK, pre-edge outstanding state still rejects ACK; software retries on the next cycle. START remains prohibited until a successful ACK. The independent A/B Burst-write channel may load the inactive bank while C is returned. Lite STATUS traffic cannot insert a bubble into an active C Burst because the channels do not share the C response state.

## Verification and performance

The restricted adapter passed 154 directed checks; the Device ownership integration passed 29 checks. The existing dual-bank Device and Top regressions also passed. Twenty-operation benchmarks used identical packed inputs, STATUS polling, result checking, ACK sequencing, and golden-model arithmetic for Lite and Burst readback.

| N | K | Lite total | C Burst total | Saved | Speedup | Bursts/op | Beats/op |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 64 | 12,914 | 12,009 | 905 | 1.075360x | 16 | 256 |
| 32 | 32 | 43,634 | 24,434 | 19,200 | 1.785790x | 64 | 1,024 |

For N=32/K=32, first-response latency is one cycle and each of the 63 Burst boundaries adds one empty cycle. Across 20 operations, these 1,260 cycles explain the difference from the ideal continuous-response model's 23,174-cycle prediction. For N=16/K=64, faster readback exposes the A/B loading limit: average ACK-to-next-START grows to 201 cycles.

Run:

```bash
bash scripts/run_v2_dual_bank_c_burst_read.sh all
```

Detailed evidence is in [the experiment report](../../reports/v2_dual_bank_c_burst_read/summary.md). This result establishes functional behavior and RTL cycle counts only; it does not establish full AXI4 compliance, mapped area, timing closure, LVS, or post-route equivalence.
