# V2 Burst Input-Supply Interval Experiment

## Scope and method

This experiment uses the same `systolic_axi_burst_top` instance with `N=2`,
`K=17`, and `PACKED_ENABLE=0`. L1 and L16 use identical matrix data, one
outstanding write transaction, immediate response READY, and the same
READY/START/DONE-poll/read-C/ACK flow. Only the maximum burst length changes.

The 68 A-then-B elements share one absolute readiness schedule. Element $i$
becomes available at $t_0+i(g+1)$ for $g \in \{0,1,3,7\}$ and remains
available until its W handshake. AW may be issued before a burst's data is
ready. Once WVALID is asserted, data, strobe, and WLAST remain stable until
the handshake. The implementation does not sleep after W handshakes.

The timing model and its pre-simulation predictions are frozen in
[`model.md`](model.md). Pure-write timing starts immediately before the first
AW attempt and ends at the final B completion, using the existing BFM's
half-open interval convention.

## Results

All configurations transferred 68 W beats. L1 used 68 one-beat transactions;
L16 used six transactions, splitting each matrix as 16+16+2 beats.

| $g$ | Length | Transactions / W beats | Predicted pure writes | Measured A / B writes | Measured pure writes | End-to-end | L16 savings | L16 end-to-end speedup |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 | 1 | 68 / 68 | 204 | 102 / 102 | 204 | 239 | — | — |
| 0 | 16 | 6 / 68 | 80 | 40 / 40 | 80 | 115 | 124 | 2.0783× |
| 1 | 1 | 68 / 68 | 204 | 102 / 102 | 204 | 239 | — | — |
| 1 | 16 | 6 / 68 | 136 | 68 / 68 | 136 | 171 | 68 | 1.3977× |
| 3 | 1 | 68 / 68 | 270 | 134 / 136 | 270 | 305 | — | — |
| 3 | 16 | 6 / 68 | 270 | 134 / 136 | 270 | 305 | 0 | 1.0000× |
| 7 | 1 | 68 / 68 | 538 | 266 / 272 | 538 | 573 | — | — |
| 7 | 16 | 6 / 68 | 538 | 266 / 272 | 538 | 573 | 0 | 1.0000× |

The g=0 run reproduces the established 204/80 pure-write and 239/115
end-to-end baselines. Every measured pure-write result equals its prediction.
The unchanged post-write flow adds 35 cycles in every run: two for the READY
check and 33 from the subsequent START/poll/read-C interval. ACK adds another
three cycles to the repeatable-task interval.

## Interpretation

- At g=0, transaction amortization saves 124 cycles. L16 is 2.55× faster for
  pure writes and 2.0783× faster end to end.
- At g=1, L1's three-cycle transaction cadence still covers every other-cycle
  element arrival, while L16 waits within bursts. The absolute benefit shrinks
  to 68 cycles; the end-to-end speedup falls to 1.3977×.
- At g=3 and g=7, the absolute element readiness schedule is the bottleneck.
  Transaction overhead fits entirely inside time that would otherwise be
  spent waiting for data, so L1 and L16 finish at the same cycles.
- This experiment therefore observes shrinking absolute savings, not the
  alternative case where savings remain nearly constant while only the ratio
  declines.

These results describe this RTL, BFM policy, single-outstanding configuration,
and absolute producer schedule. They are cycle-level simulation results, not
CPU, memory-system, or silicon performance measurements.

## Evidence and reproduction

- Per-element readiness and W handshakes: [`element_events.csv`](element_events.csv)
- Per-transaction AW/first-W/last-W/B events: [`transaction_events.csv`](transaction_events.csv)
- Phase boundary timeline: [`timeline.csv`](timeline.csv)
- Complete measurements: [`comparison.csv`](comparison.csv)
- Paired L1/L16 deltas: [`gap_comparison.csv`](gap_comparison.csv)
- Simulation result: [`simulation.log`](simulation.log)

From any working directory:

```bash
bash /path/to/systolic-array/scripts/run_v2_burst_supply_gap.sh
```
