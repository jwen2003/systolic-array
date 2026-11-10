# V2 Burst packed support: synthesis and post-synthesis STA

## Measured comparison

| `PACKED_ENABLE` | Mapped area / cells | Sequential / combinational area | Setup WNS / TNS | Hold WNS / TNS | Electrical violations | Worst path |
|---:|---:|---:|---:|---:|---:|---|
| 0 | 11545.730 µm² / 5,553 | 3839.178 / 7706.552 µm² | -0.015262 / -0.015262 ns | -0.037323 / -0.220520 ns | slew 0, cap 4, fanout 0 | `u_core.u_controller.cycle_idx[0]$_SDFFE_PN0P_` → `u_core.u_array.gen_row[0].gen_col[1].u_pe.psum_out[17]$_SDFFE_PN0P_` |
| 1 | 47206.488 µm² / 32,701 | 3961.272 / 43245.216 µm² | -11.434590 / -3259.177979 ns | -0.037323 / -0.172229 ns | slew 1, cap 15, fanout 0 | `u_burst.state[1]$_SDFFE_PN0P_` → `u_device.a_matrix[16]$_DFFE_PP_` |

- Enabling packed support adds **35660.758 µm² (308.87%)** and **27,148 cells**.
- Sequential area rises by only 122.094 µm²; combinational area rises by 35538.664 µm². The mapped cost is therefore overwhelmingly combinational, not stored state.
- The packed-disabled fresh run exactly reproduces the audited Burst reference: 11,545.730 µm², 5,553 cells, setup WNS -0.015262 ns.
- The packed-enabled global worst path moves from the Core feeder/PE accumulator path into packed write logic and misses 2.500 ns by 11.434590 ns under the same post-synthesis wire-load assumptions.

## Packed-path evidence

- `current_addr` → matrix data (`PACKED_ENABLE=1`): `u_burst.current_addr[2]$_SDFFE_PN0P_` → `u_device.a_matrix[16]$_DFFE_PP_`, slack -11.293473 ns, 282 mapped combinational cell traversals, including 55 buffer/inverter traversals.
- `current_addr` → written bitmap (`PACKED_ENABLE=1`): `u_burst.current_addr[2]$_SDFFE_PN0P_` → `u_device.a_written[15]$_SDFF_PN0_`, slack -0.438741 ns, 43 mapped combinational cell traversals.
- High byte-lane data and strobes (`s_burst_wdata[8/16/24/31]`, `s_burst_wstrb[1/2/3]`) have no matrix/bitmap path when packed support is disabled; corresponding paths exist and meet timing when enabled. The failing cone is controlled by packed address/index selection rather than the byte data pin itself.
- The packed-enabled frontend log explicitly expands `$div` and `$mod` templates; the packed-disabled log has neither. After technology mapping these operators no longer appear as named cells: the generic network grows from 9,273 to 49,765 primitives, especially mux/AND/OR/XOR logic. This proves retention and expansion of the packed index arithmetic, but source-name loss after flattening prevents assigning every mapped gate exclusively to `/17`, `%17`, byte-lane enable, or matrix selection.

## Frontend and constraint scope

- Both runs use the same top, source filelist, N=2, K=17, DATA_W=8, ACC_W=18, Nangate45 typical library, ORFS commit and immutable image. Only `PACKED_ENABLE` differs.
- Clock 2.500 ns; uncertainty 0.050 ns; I/O max delay 0.250 ns; min delay 0; input transition 0.050 ns; output load 0.010 pF; Liberty wire-load model `5K_hvratio_1_1`.
- All three Yosys frontend checks report 0 problems for each run. Source-to-derived equivalence proves 4401/4401 cells for packed-disabled and 4592/4592 for packed-enabled. This is not post-synthesis or post-route equivalence.
- `rst_n` is the single input without delay because the existing active-operation SDC false-paths reset. No other functional input is reported unconstrained.
- These are mapped, pre-layout results with ideal clock and wire-load interconnect. Hold and electrical results are diagnostics, not routed closure; no placement, CTS, extraction, or route was run.

## Next diagnostic focus

Before any RTL optimization, isolate the packed `current_addr`/beat-to-element-index arithmetic from the fixed-element write-enable/matrix selection network. The first candidate is the K=17 quotient/remainder cone; the second is the resulting large dynamic selection/write-enable fanout. The current evidence shows both are present in the failing cone but does not safely apportion delay between them after flattening.

## Reproduction

```bash
ORFS_ROOT=/path/to/OpenROAD-flow-scripts OSS_CAD_SUITE_ROOT=/path/to/oss-cad-suite-20260830 bash /path/to/systolic-array/scripts/run_v2_packed_synth_sta.sh

python3 /path/to/systolic-array/scripts/summarize_v2_packed_synth_sta.py
```

Raw logs, mapped netlists, ODB, full STA paths, manifests, and hashes remain under ignored `build/v2_packed_synth_sta/packed0/` and `packed1/`. Machine-readable results are `comparison.csv`, `path_summary.csv`, and `cell_type_delta.csv` in this directory.
