# N8/K8 single-buffer versus dual-input-bank mapped STA

| Top | Mapped area / cells | Sequential / combinational area | Setup WNS/TNS | Actual worst setup slack | Hold WNS/TNS | Electrical violations | Worst path |
|---|---:|---:|---:|---:|---:|---:|---|
| `systolic_axi_burst_top` | 70461.272 µm² / 37,136 | 15438.108 / 55023.164 µm² | +0.000000 / +0.000000 ns | +0.518499 ns | -0.037322 / -0.094210 ns | slew 0, cap 14, fanout 0 | `u_core.u_controller.cycle_idx[1]$_SDFFE_PN0P_` → `u_core.u_array.gen_row[7].gen_col[0].u_pe.psum_out[17]$_SDFFE_PN0P_` |
| `systolic_axi_dual_bank_top` | 84399.672 µm² / 43,922 | 20651.974 / 63747.698 µm² | +0.000000 / +0.000000 ns | +0.324535 ns | -0.037322 / -0.099936 ns | slew 0, cap 7, fanout 0 | `u_core.u_controller.cycle_idx[0]$_SDFFE_PN0P_` → `u_core.u_array.gen_row[0].gen_col[0].u_pe.psum_out[17]$_SDFFE_PN0P_` |

- Dual-bank mapped area increment: **13938.400 µm² (19.78%)**, +6,786 cells. Sequential area increases by 5213.866 µm² and combinational area by 8724.534 µm².
- Architecture predicts 1,024 additional A/B data bits plus 128 written-map bits. The mapped sequential-cell delta is +1,153; it also includes ownership/control differences and is not a direct bit-to-area conversion.
- Both setup analyses meet 2.500 ns. OpenSTA aggregate WNS clamps positive slack to 0; the full reports show +0.518499 ns and +0.324535 ns. Both global worst paths remain Core `cycle_idx` → PE accumulator paths.
- The explicit single-bank input-storage → PE path has +0.801618 ns slack. Dual-bank storage → PE has +0.727716 ns; the separate `active_bank` selection → PE path has +0.381543 ns and is close to, but not the global worst path.
- Bitmap → state/control slack is +1.778307 ns single and +1.794902 ns dual. AXI decode/read/write logic is not represented in the global top five.
- Setup violating endpoints: 0 for both. The min-delay numbers are ideal-clock, pre-layout estimates and are not routed hold closure. Max-capacitance violations remain and require physical implementation to assess/fix.

## Conditions and limits

Nangate45 typical 1.10 V / 25 °C, 2.500 ns, 0.050 ns uncertainty, 0.250/0.000 ns max/min I/O delay, 0.050 ns input transition, 0.010 pF output load, and `5K_hvratio_1_1` wire-load model. All AXI functional inputs use the same budget; `rst_n` is the sole missing input-delay port because the existing active-operation SDC applies a reset false path. Clocks are ideal and interconnect is a synthesis wire-load estimate, not extracted routing.

Frontend Slang reports 0 errors/warnings and checks report 0 problems. N8/K8 source-to-derived equivalence was not used as a gate: an exploratory `equiv_induct` run produced scalability non-proofs. Post-synthesis and post-route equivalence are not proven. No placement, CTS, routing, LVS, or power analysis was run.

## Cycle-throughput context

The measured cycle totals are 3,919 single versus 3,254 dual, a 1.204364x same-clock speedup. To retain a throughput advantage, the dual implementation must preserve more than **83.03%** of the single-buffer clock frequency (`3254/3919`); equivalently it can tolerate at most **16.97%** frequency loss. This is a break-even calculation, not a measured Fmax claim.

## Reproduction

The retained measurements predate the C Burst Read integration. The saved source hashes identify the measured inputs. The current tree includes later result-ownership wiring in the shared dual-bank Device and Lite Top, so the runner uses a different source snapshot.

```bash
ORFS_ROOT=/path/to/OpenROAD-flow-scripts bash scripts/run_v2_n8k8_double_buffer_synth_sta.sh
python3 scripts/summarize_v2_n8k8_double_buffer_synth_sta.py
```
