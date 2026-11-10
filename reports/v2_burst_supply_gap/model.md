# V2 Burst input-supply interval model

This model was frozen before the RTL interval scan.

## Controlled conditions

- Top: `systolic_axi_burst_top`, `N=2`, `K=17`, `PACKED_ENABLE=0`.
- A followed by B forms one 68-element readiness schedule.
- Element $i$ becomes available at $t_0+i(g+1)$ and remains available.
- L1 and L16 use the same matrix values, readiness schedule, single-outstanding
  policy, and READY/START/poll/read-C/ACK flow.
- L1 issues one transaction per element. L16 splits each matrix as 16+16+2.

## BFM timing assumptions

The existing g=0 trace establishes these cycle-counter rules:

1. AW does not wait for the first element and is accepted one cycle after a
   transaction begins.
2. A W handshake recorded at cycle $c$ samples data that was available at the
   start of that step. Therefore element $i$ may handshake when the recorded
   cycle is at least $t_0+i(g+1)+1$.
3. Within one burst, consecutive ready beats may handshake on consecutive
   cycles. WVALID and its payload remain stable while WREADY is low.
4. A new single-outstanding transaction starts only after the preceding B
   handshake. With no supply wait, consecutive transactions place W handshakes
   three cycles apart.
5. B is accepted one cycle after the last W handshake.

Pure-write cycles are measured from the instant before the first AW attempt to
the final B completion, using the existing half-open BFM interval convention.

## Predictions

| Supply gap $g$ | L1 pure writes | L16 pure writes |
|---:|---:|---:|
| 0 | 204 | 80 |
| 1 | 204 | 136 |
| 3 | 270 | 270 |
| 7 | 538 | 538 |

For g=0 the unchanged post-load flow adds 35 cycles, predicting the existing
239/115 end-to-end baselines. Predictions for all gaps are checked against the
measured handshake timeline rather than inserted as measured data.
