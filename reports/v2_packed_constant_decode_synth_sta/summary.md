# V2 packed constant-address decode: synthesis and post-synthesis STA

## Four-run comparison

| Experiment | `PACKED_ENABLE` | Mapped area / cells | Sequential / combinational area | Setup WNS / TNS | Hold WNS / TNS | Slew / cap / fanout violations | Worst path |
|---|---:|---:|---:|---:|---:|---:|---|
| Old dynamic index | 0 | 11545.730 µm² / 5,553 | 3839.178 / 7706.552 µm² | -0.015262 / -0.015262 ns | -0.037323 / -0.220520 ns | 0 / 4 / 0 | `u_core.u_controller.cycle_idx[0]$_SDFFE_PN0P_` → `u_core.u_array.gen_row[0].gen_col[1].u_pe.psum_out[17]$_SDFFE_PN0P_` |
| Old dynamic index | 1 | 47206.488 µm² / 32,701 | 3961.272 / 43245.216 µm² | -11.434590 / -3259.177979 ns | -0.037323 / -0.172229 ns | 1 / 15 / 0 | `u_burst.state[1]$_SDFFE_PN0P_` → `u_device.a_matrix[16]$_DFFE_PP_` |
| New constant decode | 0 | 11372.032 µm² / 5,542 | 3839.178 / 7532.854 µm² | -0.036055 / -0.049059 ns | -0.037323 / -0.163694 ns | 0 / 1 / 0 | `u_core.u_controller.cycle_idx[1]$_SDFFE_PN0P_` → `u_core.u_array.gen_row[0].gen_col[0].u_pe.psum_out[17]$_SDFFE_PN0P_` |
| New constant decode | 1 | 12109.118 µm² / 5,889 | 3961.272 / 8147.846 µm² | +0.000000 / +0.000000 ns | -0.037323 / -0.172040 ns | 0 / 0 / 0 | `u_core.u_controller.cycle_idx[0]$_SDFFE_PN0P_` → `u_core.u_array.gen_row[1].gen_col[0].u_pe.psum_out[17]$_SDFFE_PN0P_` |

## Measured effects

- Packed-enabled area changes by -35097.370 µm² (-74.35%), and mapped cells by -26,812.
- Packed-enabled combinational area changes by -35097.370 µm²; sequential area remains 3961.272 µm² versus 3961.272 µm².
- The packed-enabled frontend generic network falls from 49,765 to 12,077 primitives. Neither new frontend log contains `$div` or `$mod` templates.
- The new packed address path is `u_burst.current_addr[6]$_SDFFE_PN0P_` → `u_device.b_matrix[13]$_DFFE_PP_`, slack +1.674469 ns and 13 combinational cell traversals. The bitmap path slack is +1.692279 ns.
- The new packed-enabled global worst path has moved back to the Core. It is no longer a packed write path under this mapped, wire-load-model experiment.

## Packed-disabled baseline audit

- The packed-disabled behavior remains frontend-proven and retains 849 sequential cells. No packed high-byte/strobe path exists, and no `$div`/`$mod` template is present.
- It does not reproduce the old mapped netlist bit-for-bit: area changes by -173.698 µm² and cells by -11. The post-process generic count falls from 9,273 to 9,205, entirely due to 68 fewer generic muxes; all other generic primitive categories and register counts match. Removing the old runtime `packed_index` expression therefore changed the optimized disabled elaboration even though packed behavior is pruned. This is a synthesis-structure difference, not evidence of a functional change.

## Proof and scope

- Slang reports 0 errors and 0 warnings. Three frontend checks and the mapped Yosys check report 0 problems for both new runs.
- Source-to-derived equivalence proves 4614/4614 cells for packed-disabled and 5173/5173 for packed-enabled. This does not prove old RTL against new RTL, nor post-synthesis equivalence.
- Constraints and tools match the old experiment: Nangate45 typical, 2.500 ns, 0.050 ns uncertainty, 0.250 ns I/O max delay, zero min delay, 0.050 ns input transition, 0.010 pF output load, and `5K_hvratio_1_1` wire-load model.
- `rst_n` is intentionally the only input without delay under the active-operation false-path convention. These are pre-layout estimates with ideal clocks, not routed closure.

## Functional regression

- Wrapper unit tests pass: AXI-Lite slave 84 checks, AXI Burst write slave 132 checks, existing Device 391 checks, and the new direct packed-decode test 36 checks.
- Lite Top N=2/K=3 passes 262 checks. The Burst comparison passes 1,531 checks, including the unchanged N=2/K=17 L=16 result of 82 load cycles and 120 total cycles.
- Packed integration passes for N=2/K=17 (772 checks), N=2/K=16 (725), N=3/K=5 (480), and N=1/K=5 (264). The N=2/K=17 packed L=16 result remains 22 write cycles, last commit at cycle 21, confirmed ready at cycle 24, and 62 total cycles.
- The new Device test directly checks the N=2/K=17 A word-4 row crossing, independent same-word lanes, A/B tail strobes including zero and illegal lanes, matrix and bitmap side effects, signed bytes, and high-address alias rejection.
- Simulation plus the independent matrix golden model checks the exercised behavior; it is not a formal proof of old RTL against new RTL.

## Reproduction

```bash
ORFS_ROOT=/path/to/OpenROAD-flow-scripts \
PACKED_SYNTH_BUILD_ROOT=build/v2_packed_constant_decode_synth_sta \
bash /path/to/systolic-array/scripts/run_v2_packed_synth_sta.sh

python3 /path/to/systolic-array/scripts/summarize_v2_packed_constant_decode.py
```

Raw new logs, netlists, ODB, and full paths are under ignored `build/v2_packed_constant_decode_synth_sta/`. The pre-change file and the first diagnostic synthesis attempt remain under ignored `build/v2_packed_constant_decode/` and `build/v2_packed_constant_decode_synth_sta_attempt1/`.
