# V2 packed vs. unpacked controlled RTL cycle comparison

## Measured results

Both modes use the same `systolic_axi_burst_top` instance compiled with
`PACKED_ENABLE=1`, `N=2`, `K=17`, `DATA_W=8`, and `ACC_W=18`. The benchmark
resets that instance between modes and changes only the A/B write windows and
payload packing.

| Mode | Write transactions | W beats | A write | B write | Pure writes | Ready check | Load including ready | START access | Device START-to-DONE | DONE polling | C readback | End-to-end | Including ACK | Useful input bytes/write cycle |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Unpacked | 6 | 68 | 40 | 40 | 80 | 2 | 82 | 3 | 20 | 22 | 8 | 115 | 118 | 0.85000 |
| Packed | 2 | 18 | 11 | 11 | 22 | 2 | 24 | 3 | 20 | 22 | 8 | 57 | 60 | 3.09091 |

The end-to-end speedup is $115/57 = 2.0175\times$. The pure-write speedup is
$80/22 = 3.6364\times$. Both modes pass the same independent signed matmul
golden model for all four C elements, and the two result vectors are also
compared directly.

## Prediction check

The measurements exactly reproduce the predicted 80-to-22-cycle pure-write
reduction and 115-to-57-cycle end-to-end reduction. Fifty fewer W beats save 50
cycles, while four fewer write transactions save another eight cycles because
each transaction has one AW setup cycle and one B response cycle. The ready
check, command access, computation, polling, C readback, and ACK costs are
unchanged.

The 20-cycle device computation interval overlaps the 22-cycle polling
interval. It must not be added again when reconstructing the end-to-end total.
The event boundaries are half-open cycle intervals: the first request begins at
the recorded `first_request` edge, and each phase duration is the next boundary
minus the previous one.

## Transaction evidence

- Unpacked A and B each use bursts of 16, 16, and 2 beats at the legacy
  `0x1000` and `0x2000` windows. Every beat uses `WSTRB=0x1`.
- Packed A and B each use one 9-beat burst at `0x4000` and `0x5000`. The first
  eight beats use `WSTRB=0xf`, and the ninth uses `WSTRB=0x3` for the final two
  valid INT8 lanes.
- All eight transactions receive `OKAY`; `AxLEN`, AW, first/last W, WLAST, and B
  completion cycles are recorded in `transaction_events.csv`.

The earlier packed regression's 62-cycle `total` uses a different boundary: it
starts before a two-cycle preflight status read and includes ACK. Removing that
preflight gives the controlled benchmark's 60-cycle repeat-task interval. Its
22-cycle writes and 24-cycle ready-confirmed load are otherwise identical to
this run.

## Reproduction

From any working directory:

```bash
bash /path/to/systolic-array/scripts/run_v2_packed_performance.sh
```

Raw evidence is in `comparison.csv`, `transaction_events.csv`, `timeline.csv`,
`prediction_vs_measurement.csv`, `compile.log`, and `simulation.log` in this
directory. These are RTL simulation cycle counts for the stated BFM and Slave;
they are not CPU, DDR, or wall-clock performance measurements.
