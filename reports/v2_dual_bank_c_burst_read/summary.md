# V2 Dual-Bank 32-bit C Burst Read Experiment

## Scope

The experiment adds a dedicated, restricted AXI read channel to an independent experimental top while preserving the existing dual-bank Lite top. Both variants use the same Core, START0/START1 input-bank ownership, packed A/B Burst writes, STATUS polling, one result buffer, and ACK protocol. The test performs 20 operations from reset with identical signed INT8 inputs and checks every signed INT18 result against an independent golden model.

The implemented C read subset is single-outstanding, aligned 32-bit INCR, 1--16 beats, with one sign-extended INT18 result per beat. Illegal requests return zero data and SLVERR for exactly `ARLEN+1` beats. `RVALID` does not depend on `RREADY`; payload and control remain stable while stalled.

## Measured results

| N | K | Readback | Total cycles | Average START interval | Average first-to-last result span |
|---:|---:|---|---:|---:|---:|
| 16 | 64 | Lite | 12,914 | 617.000 | 510.000 |
| 16 | 64 | C Burst | 12,009 | 582.000 | 270.000 |
| 32 | 32 | Lite | 43,634 | 2,153.000 | 2,046.000 |
| 32 | 32 | C Burst | 24,434 | 1,193.000 | 1,086.000 |

Cycles are inclusive from the first packed-input AW handshake through operation 20 ACK acceptance. N=32/K=32 improves by 19,200 cycles, or 1.785790x. Each operation issues 64 16-beat reads. AR-to-first-R latency is one cycle; every one of the 63 transaction boundaries contains one empty cycle. Therefore the measured result span is `1023 + 63 = 1086` cycles. Across 20 operations, the 1,260 boundary cycles explain exactly the difference between the earlier ideal continuous-response prediction (23,174) and the measured 24,434 cycles.

N=16/K=64 issues 16 16-beat reads per operation. Its measured result span is `255 + 15 = 270` cycles. Faster result return exposes the input schedule: average ACK-to-next-START increases from 4 to 201 cycles, so most of the raw readback reduction is hidden by waiting for the next A/B bank to become complete. The measured total improves by 905 cycles (1.075360x), not by the full isolated readback reduction.

## Verification evidence

- Adapter directed test: 154 checks; 1/16 beats, final legal word, not-DONE, alignment, size, burst type, range, maximum length, backpressure stability, RLAST, SLVERR draining, and reset.
- Device/adapter ownership test: 29 checks; legal AR wins over same-cycle ACK, ACK on the final R handshake is rejected, ACK succeeds on the following cycle, inactive-bank loading overlaps readback, and reset aborts ownership.
- Existing dual-bank regression: 13 Device tail checks and 46 Top integration checks, including four measured load/compute overlap cycles.
- Performance runs: 40/40 operations per readback mode across N=16/K=64 and N=32/K=32; all C elements match the independent fixed-width INT18 golden model.

This is RTL cycle simulation, not CPU, memory-system, synthesis, or physical timing evidence. It does not prove full AXI4 compliance. Source-to-derived equivalence and post-route equivalence were not run for this new experimental top.

## Reproduction and raw output

```bash
bash scripts/run_v2_dual_bank_c_burst_read.sh all
```

Machine-readable summaries are written to `build/v2_dual_bank_c_burst_read/comparison.csv`. Per-operation timing is in each `tasks.csv`; Lite events are in `events.csv`; C channel AR/R events are in `c_burst_events.csv`. Compile and simulation logs are kept beside those files.
