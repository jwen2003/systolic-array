# V2 Lite versus restricted Burst controlled comparison

## Scope and controls

All runs use the current constant-address-decode Device, `N=2`, `K=17`, `DATA_W=8`, `ACC_W=18`, `PACKED_ENABLE=0`, identical row-major matrices, one outstanding transaction, AW/W asserted together for Lite, VALID held until handshake, no request gaps, immediate response READY, serialized load/START/poll/readback/ACK, and no overlap between operations. The restricted Burst path implements only aligned 32-bit INCR writes of 1–16 beats with one implicit ID; it is not full AXI4.

The fixed-seed (`0x5a17c0de`) robustness run inserts 0–3 cycles of deterministic `BREADY`/`RREADY` backpressure. It is a functional stability check, not part of the primary cycle comparison. Lite and all five Burst lengths pass the independent dot-product golden model. Every Burst length also completes a second load/compute/read/ACK sequence without reset, proving ACK/reload lifecycle recovery.

## Measured transport performance

| Configuration | Input write transactions / beats | A+B load | Device START→DONE | C readback | First input→last C | Through ACK | Input useful B/cycle |
|---|---:|---:|---:|---:|---:|---:|---:|
| AXI-Lite Top | 68 / 68 | 206 | 20 | 8 | 239 | 242 | 0.3301 |
| Burst Top, L=1 (`AxLEN=0`) | 68 / 68 | 206 | 20 | 8 | 239 | 242 | 0.3301 |
| Same Burst Top, L=2 | 34 / 68 | 138 | 20 | 8 | 171 | 174 | 0.4928 |
| Same Burst Top, L=4 | 18 / 68 | 106 | 20 | 8 | 139 | 142 | 0.6415 |
| Same Burst Top, L=8 | 10 / 68 | 90 | 20 | 8 | 123 | 126 | 0.7556 |
| Same Burst Top, L=16 | 6 / 68 | 82 | 20 | 8 | 115 | 118 | 0.8293 |

Each A/B window has 34 words. Tail lengths are therefore L2=`2×17`, L4=`4×8+2`, L8=`8×4+2`, and L16=`16×2+2`, independently for A and B. Each input is still an INT8 value in a 32-bit slot (`WSTRB=0001`): the 68 useful input bytes correspond to 272 bus data-beat bytes. The four INT18 results are counted as 9 bit-equivalent useful bytes and 16 returned 32-bit container bytes; therefore total useful bit-equivalent payload is 77 bytes and total slot/container traffic is 288 bytes.

The event interval is half-open in rising-edge cycle indices: `core_done_cycle - core_start_cycle = 20`. The Core RUN window remains 19 cycles; the Device `core_start` pulse is visible one edge before the controller enters RUN. Polling overlaps the compute interval, so phase durations must not be summed as independent work. Detailed event rows are in `performance.csv`.

All measured pure-write times exactly match $68+2T$, where $T$ is the total A/B transaction count: 204, 136, 104, 88, and 80 cycles. The ready check adds two cycles. Relative to L1, L2/L4/L8/L16 end-to-end speedups are 1.398×, 1.719×, 1.943×, and 2.078×. Benefits diminish because transaction count approaches its six-transaction floor while the fixed 20-cycle computation, polling, four result reads, START and ACK do not shrink. Single-beat Burst and Lite take the same cycles under this master policy; that is measured, not assumed.

## Comparable mapped hardware and post-synthesis STA

| Top | Mapped area | Sequential / combinational | Setup worst slack / TNS | Electrical violations | Worst path |
|---|---:|---:|---:|---:|---|
| `systolic_axi_lite_top` | 10,655.960 µm², 5,020 cells | 3,622.122 / 7,033.838 µm² | +0.015669 / 0 ns | cap 2, slew 1, fanout 0 | Core `cycle_idx` → feeder/PE → accumulator |
| `systolic_axi_burst_top` | 11,545.730 µm², 5,553 cells | 3,839.178 / 7,706.552 µm² | -0.015262 / -0.015262 ns | cap 4, slew 0, fanout 0 | Same Core path class |

The restricted Burst interface costs 889.770 µm² (+8.35%) and 533 cells (+10.62%) in this mapped comparison: +217.056 µm²/+48 sequential cells and +672.714 µm²/+485 combinational cells. Buffers increase 343→391 and inverters 155→160. Both source-to-derived checks pass (Lite 4,023/4,023; Burst 4,401/4,401).

The Burst mapped design narrowly misses the 2.500 ns setup assumption by 15.262 ps, while Lite has 15.669 ps positive worst slack. These are pre-layout, ideal-clock, Liberty `5K_hvratio_1_1` wire-load results, not routed timing or Fmax. Hold and electrical results are diagnostic and are not closure claims.

The synthesis/STA results are reused for the added L2/L4/L8 runtime tests. Current source hashes match both stored synthesis snapshots with zero mismatches; top parameters, filelists, fixed Yosys/ORFS/image, Liberty corner, SDC values and wire-load model are unchanged. Runtime `AxLEN` is not an elaboration parameter, so all Burst lengths share the single Burst netlist and PPA row. See `synthesis_reuse_audit.csv`.

The earlier constant-decode report gives Lite mapped area 10,928.078 µm², whereas this controlled rerun gives 10,655.960 µm². Both declare the same source design, parameters, tool versions and numeric constraints, but they use different frontend Tcl files and their generated `post_proc.v` files are not byte-identical (while each source-to-derived proof passes). The old and current config differ only in nickname/path/comments, and the visible frontend pass sequence is equivalent; no single causal pass or input change has been proven. Therefore the 272.118 µm² difference remains **unexplained tool/frontend-output sensitivity**, and only the jointly regenerated 10,655.960/11,545.730 µm² pair is used for the Lite-versus-Burst hardware delta.

## Workload attribution and limits

- Lite/single-beat: the 20-cycle Device interval is 8.4% of 239 end-to-end cycles; input load plus C readback occupies 214 cycles (89.5%). These percentages overlap polling/control boundaries and are descriptive, not additive utilization.
- Multi-beat: the same 20-cycle Device interval is 17.4% of 115 cycles; input load plus readback is 90 cycles (78.3%).
- The multi-beat gain comes from amortizing one AW and one B response over up to 16 W beats. The Slave accepts one W beat per cycle with no inserted wait in the primary run. No gain is attributed to the Core.
- Results apply to this blocking, single-outstanding BFM, immediate-ready receiver, polling policy, matrix size, and 32-bit slot layout. They are not CPU, DDR, DMA, or software wall-clock measurements.
- Placement, CTS, routing, propagated clocks, parasitics, congestion, and physical critical-path migration remain untested for the Burst Top.

## Reproduction and raw evidence

```bash
bash scripts/run_v2_lite_vs_burst.sh
ORFS_ROOT=/path/to/OpenROAD-flow-scripts \
OSS_CAD_SUITE_ROOT=/path/to/oss-cad-suite-20260830 \
bash scripts/run_v2_lite_vs_burst_synth_sta.sh
```

Full compile/simulation logs, mapped netlists, synthesis reports and complete timing paths are under ignored `build/v2_lite_vs_burst/`. Source hashes, tool identity and constraints are stored with each synthesis result.
