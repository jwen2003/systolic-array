# V2 packed Burst physical implementation

## Final comparison

| Metric | PACKED_ENABLE=0 | PACKED_ENABLE=1 (antenna repair) |
|---|---:|---:|
| Mapped cells / area | 5,542 / 11372.032 µm² | 5,889 / 12109.118 µm² |
| Final functional cells / area (tap/fill excluded) | 6,216 / 12002.412 µm² | 6,821 / 12924.984 µm² |
| Timing-repair / clock buffers | 800 / 191 | 1,066 / 191 |
| Setup WNS / TNS | +0.115657 / 0.000000 ns | +0.149201 / 0.000000 ns |
| Hold WNS / TNS | +0.004894 / 0.000000 ns | +0.008039 / 0.000000 ns |
| Slew / cap / fanout violations | 0 / 0 / 0 | 0 / 0 / 0 |
| Core / die area | 22570.4 / 23350.9 µm² | 23934.7 / 24844.1 µm² |
| Utilization | 53.494% | 54.308% |
| Global overflow | 0 | 0 |
| Detailed-route / OpenROAD antenna / KLayout DRC | 0 / 0 / 0 | 0 / 0 / 0 |
| Detailed wirelength / vias | 87,143 µm / 44,091 | 98,463 µm / 48,609 |

PACKED_ENABLE=1 adds 922.572 µm² (7.687%) of final functional standard-cell area under the common tap/fill-excluded accounting.

## Timing and packed-path audit

- PACKED_ENABLE=0 critical path: `u_core.u_controller.cycle_idx[0]$_SDFFE_PN0P_/QN` to `u_core.u_array.gen_row[0].gen_col[1].u_pe.psum_out[17]$_SDFFE_PN0P_/D`, slack +0.115700 ns.
- PACKED_ENABLE=1 critical path: `u_core.u_controller.cycle_idx[0]$_SDFFE_PN0P_/QN` to `u_core.u_array.gen_row[0].gen_col[1].u_pe.psum_out[17]$_SDFFE_PN0P_/D`, slack +0.149200 ns.
- Both global critical paths remain in the Core `cycle_idx` to feeder/PE accumulator cone.
- The routed PACKED_ENABLE=1 `current_addr` to matrix path has slack +1.448011 ns; the bitmap path has slack +1.502475 ns.

## Antenna disposition and scope

- The default PACKED_ENABLE=1 run has one KLayout `METAL6_ANTENNA` item on the top-edge `s_axi_araddr[4]` route to existing `BUF_X1 input31/A`: ratio 331.413333, threshold 300.
- OpenROAD reports zero antenna violations because this platform lacks an equivalent modeled rule.  The repair fixes the existing buffer at a legal top-row site near the input pin; it adds no logical cell or timing exception.  The fresh repair run has zero KLayout items, zero detailed-route DRC, and zero OpenROAD antenna violations.
- The default/fixed packed1 functional areas are 12952.084/12924.984 µm², with 1083/1066 timing-repair buffers.  The small decrease is normal backend variation from the placement constraint, not an area benefit attributed to the repair.
- Source-to-derived equivalence proves 4614/4614 cells for packed0 and 5173/5173 for packed1.  Kepler LEC remains disabled; post-route equivalence and LVS are not proven.
- Results are extracted, propagated-clock Nangate45 typical single-corner measurements at 2.500 ns, not commercial signoff or silicon Fmax.

## Reproduction

```bash
export ORFS_ROOT=/path/to/OpenROAD-flow-scripts
export OSS_CAD_SUITE_ROOT=/path/to/oss-cad-suite-20260830
PACKED_ENABLE=1 OPENROAD_THREADS=16 bash scripts/run_v2_packed_physical.sh
PACKED_ENABLE=0 OPENROAD_THREADS=16 bash scripts/run_v2_packed_physical.sh
PACKED_ENABLE=1 PHYSICAL_RUN=antenna_input_buffer_fix OPENROAD_THREADS=16 bash scripts/run_v2_packed_physical.sh
python3 scripts/summarize_v2_packed_physical.py
```
