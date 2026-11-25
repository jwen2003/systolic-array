# N8/K8 single-buffer versus dual-input-bank physical comparison

## Final results

| Metric | Single buffer | Dual input bank |
|---|---:|---:|
| Top | `systolic_axi_burst_top` | `systolic_axi_dual_bank_top` |
| Mapped area / cells | 70461.272 µm² / 37,136 | 84399.672 µm² / 43,922 |
| Final functional area / cells (tap/fill excluded) | 71289.558 µm² / 37,450 | 85492.652 µm² / 44,618 |
| Timing-repair / clock buffers | 2,125 / 798 | 2,530 / 1,069 |
| Setup WNS / TNS | +0.344990 / 0.000000 ns | +0.244351 / 0.000000 ns |
| Hold WNS / TNS | +0.011694 / 0.000000 ns | +0.007640 / 0.000000 ns |
| Setup / hold violating endpoints | 0 / 0 | 0 / 0 |
| Slew / capacitance / fanout violations | 0 / 19 / 0 | 0 / 22 / 0 |
| Core / die area | 140268 / 142427 µm² | 168424 / 170445 µm² |
| Actual utilization | 51.001% | 50.923% |
| Global / detailed wirelength | 920,809 / 646,960 µm | 1,258,320 / 918,544 µm |
| Detailed-route vias | 275,119 | 334,934 |
| Detailed-route DRC / OpenROAD antenna | 0 / 0 | 0 / 0 |
| KLayout DRC | interrupted after 86 min | not run |

Dual buffering adds **14203.094 µm² (19.923%)** of final functional standard-cell area under the common tap/fill-excluded accounting.

## Routed timing paths

| Variant / path | Slack | Cell delay | Net delay | Startpoint → endpoint |
|---|---:|---:|---:|---|
| Single global | +0.344990 ns | 1.955624 ns | 0.116774 ns | `u_core.u_controller.cycle_idx[1]$_SDFFE_PN0P_` → `u_core.u_array.gen_row[2].gen_col[0].u_pe.psum_out[17]$_SDFFE_PN0P_` |
| Single storage → PE | +0.773438 ns | 1.623385 ns | 0.006470 ns | `u_device.a_matrix[143]$_DFFE_PP_` → `u_core.u_array.gen_row[2].gen_col[0].u_pe.psum_out[17]$_SDFFE_PN0P_` |
| Dual global | +0.244351 ns | 1.930719 ns | 0.217627 ns | `u_core.u_controller.cycle_idx[0]$_SDFFE_PN0P_` → `u_core.u_array.gen_row[1].gen_col[0].u_pe.psum_out[17]$_SDFFE_PN0P_` |
| Dual storage → PE | +0.645314 ns | 1.724957 ns | 0.017797 ns | `u_device.a_bank[0][84]$_DFFE_PP_` → `u_core.u_array.gen_row[1].gen_col[0].u_pe.psum_out[17]$_SDFFE_PN0P_` |
| Dual active_bank → PE | +0.374448 ns | 1.857838 ns | 0.155216 ns | `u_device.active_bank$_SDFFE_PN0P_` → `u_core.u_array.gen_row[2].gen_col[0].u_pe.psum_out[17]$_SDFFE_PN0P_` |

Both routed global worst paths remain Core `cycle_idx` → feeder/PE accumulator paths. The dual `active_bank` path does not become globally critical. Compared with mapped STA, the single global slack changes from +0.518499 to +0.344990 ns and dual from +0.324535 to +0.244351 ns. The checked-in CSVs summarize the paths. The runner writes full path reports to each variant's `final_audit/` directory under the ignored build root.

## Interpretation and scope

- Both variants pass routed setup and hold at 2.500 ns with extracted parasitics and propagated clocks, so **both reach the same target clock under this timing analysis**.
- The measured 3,919 / 3,254 cycle totals therefore correspond to a **1.2044× same-clock throughput advantage** for the dual-bank schedule. The break-even dual frequency is 83.03% of the single-buffer frequency.
- Neither variant passes every requested physical check because max-capacitance violations remain (19 / 22). No backend parameter was changed asymmetrically to repair them.
- The detailed-route DRC reports are empty (zero items), and OpenROAD reports zero antenna violations. Global routing completed, but this ORFS log does not emit a numeric final-overflow field; it is recorded as unavailable rather than inferred.
- The complete KLayout deck was attempted on single buffer and remained in an active FEOL geometry operation after 86 minutes; it was stopped so both requested physical/STA runs could complete. It was not run for dual. Consequently this is not a KLayout-clean or signoff claim.
- Final STA reads the matching final ODB, SDC, and SPEF for each run. SPEF annotation coverage percentage is not emitted by this tool version. `check_setup` reports only `rst_n` without input delay, consistent with the documented active-operation reset false path.
- Nangate45 typical single-corner results are not LVS, post-route formal equivalence, multi-corner signoff, or silicon Fmax evidence.

## Reproduction

The retained measurements predate the C Burst Read integration. The saved source hashes identify the measured inputs. The current tree includes later result-ownership wiring in the shared dual-bank Device and Lite Top, so the runner uses a different source snapshot.

```bash
ORFS_ROOT=/path/to/OpenROAD-flow-scripts \
  OPENROAD_THREADS=16 \
  bash scripts/run_v2_n8k8_double_buffer_physical.sh

python3 scripts/summarize_v2_n8k8_double_buffer_physical.py
```
