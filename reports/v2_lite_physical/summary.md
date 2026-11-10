# V2 Lite-only Nangate45 Physical Implementation

## Experiment identity

- Top: `systolic_axi_lite_top`
- Parameters: `N=2`, `K=17`, `DATA_W=8`, `ACC_W=18`, `PACKED_ENABLE=0`
- Git HEAD at run time: `b5077a7537c0929f4b0b97793ff1cfee4671c3cd`; the manifest records the dirty working tree and all input hashes.
- ORFS commit: `6101364b2d7909dd797e1e3e7f80695401cfa4e4`
- Image: `openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0` (`linux/amd64`)
- Frontend Yosys/read_slang: `0.68+136`; container Yosys: `0.68+post`; OpenROAD: `26Q3-1305-gf552262465`; OpenSTA: `3.1.0`; KLayout: `0.30.7`.
- Liberty/corner: `NangateOpenCellLibrary_typical.lib`, Nangate45 typical, nominal 1.10 V / 25 °C platform point.
- Routed parasitics: OpenRCX `rcx_patterns.rules`, with the platform layer RC table in `setRC.tcl`; clock routing uses metal5 and signal estimation uses metal3 before extraction.

The 2.500 ns active-operation SDC uses 0.050 ns clock uncertainty and transition, 0.250/0.000 ns max/min AXI input and output delay, 0.050 ns input transition, and 0.010 output load. `rst_n` is a synchronous active-low reset and is false-pathed only for the stated active-operation assumption: reset is released before an operation and remains stable during it.

## Measured results

| Run / stage | Setup WNS / TNS | Hold WNS / TNS | Functional cell area | Electrical violations | Overflow / DRC | Complete |
|---|---:|---:|---:|---:|---:|---|
| Baseline / synthesis | post-synth baseline about -0.077388 ns | post-synth hold violation | 10,928.078 µm² | 5 max-cap in post-synth STA | n/a | yes |
| Baseline / detailed placement | +0.127891 / 0 ns | -0.015445 / -0.030859 ns | 10,884.5 µm² | 0 | n/a | yes |
| Baseline / CTS | +0.130004 / 0 ns | +0.002486 / 0 ns | 11,386.7 µm² | 0 | n/a | yes |
| Baseline / global route | +0.080864 / 0 ns | +0.003412 / 0 ns | 11,386.7 µm² | 1 max-cap | 0 / n/a | yes |
| Baseline / extracted final | +0.127300 / 0 ns | +0.006762 / 0 ns | 11,386.7 µm² | 2 max-cap | 0 / 0 | yes |
| `CAP_MARGIN=10` / detailed placement | +0.131937 / 0 ns | -0.015708 / -0.031153 ns | 10,903.1 µm² | 0 | n/a | yes |
| `CAP_MARGIN=10` / CTS | +0.141404 / 0 ns | +0.003872 / 0 ns | 11,417.3 µm² | 0 | n/a | yes |
| `CAP_MARGIN=10` / global route | +0.093366 / 0 ns | +0.005572 / 0 ns | 11,418.6 µm² | 0 | 0 / n/a | yes |
| `CAP_MARGIN=10` / extracted final | **+0.139143 / 0 ns** | **+0.003460 / 0 ns** | **11,418.6 µm²** | **0** | **0 / 0** | **yes** |

The baseline completed and met setup/hold and routing DRC, but retained two small max-capacitance violations. The one permitted adjustment set ORFS `CAP_MARGIN=10` and reran the complete frontend-to-GDS flow. It cleared both violations at a cost of 18 functional standard cells, 31.9 µm², 16 timing-repair buffers, and 2 clock buffers. Final utilization rose from 52.4692% to 52.6163%; core/die area remained 21,701.6/22,452 µm².

Both fresh synthesis runs produced exactly 5,165 mapped cells and 10,928.078 µm². Their emitted Verilog differs byte-for-byte only because source-location attributes contain different temporary `.run.*` directory names; after normalizing that path component, the netlists are identical.

The adjusted design has 5,834 functional standard cells, including 801 sequential cells, 517 timing-repair buffers, 193 clock buffers, and 202 inverters. Global routing has zero overflow and 121,387 µm estimated tree wirelength. Detailed routing has zero DRC, 82,550 µm routed-shape wirelength, and 40,351 vias. The two wirelength figures use different stage definitions and are not used to claim an improvement percentage. Antenna checks report zero net and pin violations. GDS stream-out completed and found no orphan or missing library cells.

The separate Nangate45 KLayout rule-deck run completed for both GDS files and reports two DRC items in each, both `METAL6_ANTENNA`. The ORFS-generated `6_drc_count.rpt` says 14 because it counts all XML `<value>` fields (seven fields per item), not violation items. The adjusted markers have ratios 305.3867 and 309.8667 against a 300 limit. OpenROAD's antenna checker reports zero violations and the platform logs that no `ANTENNACELL` is available, so this is a real unresolved discrepancy between the OpenROAD and KLayout antenna models; detailed-route DRC=0 must not be presented as KLayout DRC=0.

CTS started from 801 sequential sinks, created 138 clock buffers and 138 clock nets, and reported a maximum H-tree level of 4 with three buffers on each sink path. It inserted 103 dummy loads, after which the CTS summary reports 904 sinks; later repair produces the final class count of 193 clock buffers. These counts describe different CTS/reporting stages and are not interchangeable.

## Final critical path

The adjusted routed critical path remains the Core path:

`u_core.u_controller.cycle_idx[1]` → feeder selection / PE multiplier and accumulator logic → `u_core.u_array.gen_row[0].gen_col[0].u_pe.psum_out[17]`.

The high-precision SPEF/propagated-clock audit reports 0.169300 ns launch-clock latency, 0.156400 ns clock-to-Q, 2.108200 ns combinational cell delay, 0.015100 ns extracted net delay, and 2.449000 ns data arrival. Capture-clock latency is 0.175800 ns, so path-specific clock skew is +0.006500 ns. With 0.050000 ns uncertainty and 0.037650 ns library setup time, required time is 2.588000 ns and slack is +0.139100 ns. The path contains 36 combinational instances, of which three are buffers/inverters. These categories are computed from consecutive pins in OpenSTA's JSON path and do not double-count input/output pins of one cell.

The original Device bottleneck is no longer close to critical: the worst routed input-to-register read path has +1.488220 ns slack, and the targeted `awaddr_saved` to A/B matrix write paths have at least +1.434788 ns slack in the reported set.

## Constraints, coverage, and proof boundaries

- The clock is propagated after CTS; final timing uses the routed ODB, final SDC, and extracted SPEF.
- `check_setup` reports only `rst_n` as lacking input delay. This is intentional and coincides with the narrowly scoped active-operation false path. No functional AXI endpoint is reported unconstrained.
- Source-to-derived equivalence proves 4,023/4,023 cells for both fresh runs.
- `LEC_CHECK=0` remains required because the fixed Kepler Formal binary triggers the documented host CPU SIGILL. Post-route equivalence is not proven.
- Detailed-route DRC and GDS integrity checks are physical checks, not functional equivalence. KLayout DRC is not clean because of the two antenna markers described above.
- This is a single typical corner on an open reference platform. It is not commercial signoff, multi-corner closure, a silicon Fmax measurement, or a credible power result.

The adjusted ORFS log contains no `[ERROR]` records. Its warnings comprise 799 `RSZ-0104` one-pin-net messages from optimized-away or intentionally unused signals, two `PDN-1051`, two `GRT-0246` notices that the library has no antenna-diode cell, and one each of `EST-0027`, `IFP-0028`, `RCX-0514`, and `GUI-0076`. Yosys `check` reports zero structural problems, the antenna checker reports zero net/pin violations, and final setup/hold/electrical checks are used as the acceptance gates; the warnings are retained rather than suppressed.

Accordingly, 2.500 ns is met for extracted setup/hold and final electrical checks, routing converges with zero overflow and zero detailed-route DRC, but the complete physical target is **not fully clean** because KLayout reports two antenna items. No evidence points to an RTL timing change: the remaining work is to reconcile the antenna rule models and apply a supported backend antenna fix (for example, a verified diode/jumper strategy) without weakening the deck.

## Reproduction and raw evidence

From WSL/Ubuntu:

```bash
export ORFS_ROOT=/path/to/OpenROAD-flow-scripts
bash scripts/run_v2_lite_physical.sh
PHYSICAL_RUN=cap_margin_10 bash scripts/run_v2_lite_physical.sh
```

The runner refuses to overwrite either published build directory. Manifests and input SHA-256 lists are stored under:

- `build/openroad/v2_lite_physical/baseline_2p5ns/`
- `build/openroad/v2_lite_physical/cap_margin_10_2p5ns/`

Raw ORFS reports are in each run's `work/reports/.../base/`; stage metrics JSON files are in `work/logs/.../base/`; routed ODB/SDC/SPEF/netlist/GDS files are in `work/results/.../base/`; high-precision audit reports are in `final_audit/`.
