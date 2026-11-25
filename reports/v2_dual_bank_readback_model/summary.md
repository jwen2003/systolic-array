# V2 dual-bank result-readback cycle model

## Evidence and validation

The transaction-level model is calibrated against the existing 20-operation RTL benchmark in `build/v2_double_buffer_performance/`. The local `comparison.csv`, `summary.csv`, all eight `tasks.csv` files, and all eight `events.csv` files were checked independently.

| N | K | RTL single cycles | RTL dual cycles | RTL single/dual mean START interval | Dual writes during Core busy | Dual writes during DEVICE_DONE | Burst writes concurrent with C responses |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 2 | 2 | 559 | 464 | 28 / 23 | 19 | 0 | 0 |
| 8 | 8 | 3,919 | 3,254 | 196 / 161 | 361 | 228 | 76 |
| 16 | 64 | 23,839 | 12,914 | 1,192 / 617 | 1,577 | 8,132 | 4,028 |
| 32 | 32 | 54,559 | 43,634 | 2,728 / 2,153 | 1,577 | 8,132 | 4,028 |

Each configuration contains 20 task records. The inclusive first-AW-to-final-ACK interval reconstructed from `tasks.csv` equals `summary.csv`; the three overlap counters equal the per-task sums. All eight RTL/model baseline rows match, so there is no first divergent event to report. These matches validate the model only for the existing Lite-readback baseline schedule, not the hypothetical accelerated read interfaces.

## Model assumptions

- Twenty operations begin with the first input Burst AW at edge 0.
- Packed A/B input uses the existing maximum-16-beat Burst schedule. Each Burst occupies one AW cycle, its W-beat cycles, and one B-response cycle.
- Core RUN is $K+2N-2$ cycles. Device completion is modeled two cycles after START plus the Core RUN window.
- The first result response occurs five cycles after `DEVICE_DONE` in every modeled mode.
- The current `lite` baseline returns one C element every two cycles. Hypothetical modes return 1, 2, or 4 C elements per cycle with no bubbles after the first response.
- There is one result buffer. A new START remains blocked until ACK releases the current result.
- ACK requests the next free write slot. A Burst that already owns the write port retains ownership through its B handshake.
- Loading the inactive bank may overlap Core execution, DEVICE_DONE, and C readback under the same arbitration assumptions as the measured benchmark.
- The model does not include AXI read-burst address splitting, per-Burst first-response latency, read backpressure, additional outstanding transactions, or physical timing effects.

## Predictions

The complete machine-readable output is `build/v2_dual_bank_readback_model/predictions.csv`.

| N/K | Readback mode | Dual total cycles | Steady START interval | Speedup vs current dual Lite | ACK wait / operation | Input wait after ACK / operation |
|---:|---|---:|---:|---:|---:|---:|
| 2/2 | Lite RTL baseline | 464 | 23 | 1.0000× | 0 | 0 |
| 2/2 | 1 C/cycle | 404 | 20 | 1.1485× | 0 | 0 |
| 2/2 | 2 C/cycle | 364 | 18 | 1.2747× | 0 | 0 |
| 2/2 | 4 C/cycle | 344 | 17 | 1.3488× | 0 | 0 |
| 8/8 | Lite RTL baseline | 3,254 | 161 | 1.0000× | 0 | 0 |
| 8/8 | 1 C/cycle | 1,994 | 98 | 1.6319× | 0 | 0 |
| 8/8 | 2 C/cycle | 1,354 | 66 | 2.4032× | 0 | 0 |
| 8/8 | 4 C/cycle | 1,034 | 50 | 3.1470× | 0 | 0 |
| 16/64 | Lite RTL baseline | 12,914 | 617 | 1.0000× | 0 | 0 |
| 16/64 | 1 C/cycle | 11,994 | 582 | 1.0767× | 5 | 215 |
| 16/64 | 2 C/cycle | 11,866 | 582 | 1.0883× | 7 | 341 |
| 16/64 | 4 C/cycle | 11,802 | 582 | 1.0942× | 17 | 395 |
| 32/32 | Lite RTL baseline | 43,634 | 2,153 | 1.0000× | 0 | 0 |
| 32/32 | 1 C/cycle | 23,174 | 1,130 | 1.8829× | 0 | 0 |
| 32/32 | 2 C/cycle | 12,934 | 618 | 3.3736× | 0 | 0 |
| 32/32 | 4 C/cycle | 11,994 | 582 | 3.6380× | 5 | 215 |

`ACK wait` is the additional delay beyond the earliest modeled ACK commit. `Input wait after ACK` is the delay beyond the earliest control-only next START caused by the inactive bank still being loaded. Both are averages over the 19 inter-operation transitions.

## Answers to the analysis questions

### When does N=16, K=64 become input-load limited?

It becomes input-load limited starting with the **1 C/cycle** scenario. The Lite baseline has a 617-cycle mean START interval and no input wait. At 1 C/cycle the interval reaches the 582-cycle input-schedule floor, while average input wait after ACK becomes 215 cycles. Increasing read width to 2 or 4 C elements per cycle leaves the START interval fixed at 582 cycles and improves total time by only another 128 and 64 cycles respectively. Under these assumptions, faster readback primarily moves idle time from result readback to waiting for the next bank to finish loading.

### How much does one-C-per-cycle save for N=32, K=32, and what remains?

One C element per cycle changes the predicted dual total from 43,634 to **23,174 cycles**, saving **20,460 cycles** and giving 1.8829× speedup over current dual Lite readback. Moving from 1 to 2 C elements per cycle saves another **10,240 cycles**; moving from 2 to 4 saves only **940 cycles**. At 4 C elements per cycle the 582-cycle input schedule becomes limiting, with 215 average input-wait cycles after ACK. Thus the model predicts substantial benefit through 2 C/cycle, followed by sharply diminishing returns.

### What does the 23,174-cycle prediction depend on?

The value assumes 20 tasks, the measured packed-input schedule, one result buffer, START blocked until ACK, the existing ACK/write-port priority, `DEVICE_DONE` followed by a fixed five-cycle first response, and then an uninterrupted stream of one C result every cycle. It is a hypothetical transaction-level prediction, not an RTL measurement.

A future 32-bit C read-burst implementation would carry one signed 18-bit result in each 32-bit beat. With a 16-beat maximum, a 32×32 result requires 64 read Bursts. The current 1-C/cycle model does **not** include those 64 AR transactions, per-Burst first-beat latency, gaps between Bursts, R-channel backpressure, or restrictions on outstanding reads. Any non-overlapped AR/first-response gap will increase the 23,174-cycle prediction; the exact delta depends on actual Burst splitting and whether the next AR can overlap the current R stream. RTL validation must therefore compare the first divergent AR/R event against the ideal continuous-response timeline rather than treating 23,174 as a guaranteed implementation result.

## Reproduction

```bash
mkdir -p build/v2_dual_bank_readback_model
python3 sim/modeling/dual_bank_readback_model.py --tasks 20 \
  > build/v2_dual_bank_readback_model/predictions.csv
```

This work is cycle modeling only. No C Burst-read RTL, product RTL, synthesis, or physical implementation is included.
