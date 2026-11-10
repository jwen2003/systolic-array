# V2 Lite-only Nangate45 Antenna Diagnosis and Repair

## Experiment identity

- Top and parameters: `systolic_axi_lite_top`, `N=2`, `K=17`, `DATA_W=8`, `ACC_W=18`, `PACKED_ENABLE=0`.
- Corner and constraints: Nangate45 typical, 2.500 ns active-operation constraints; the SDC and RTL are unchanged.
- ORFS commit: `6101364b2d7909dd797e1e3e7f80695401cfa4e4`.
- Image: `openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0`.
- Baseline: `build/openroad/v2_lite_physical/cap_margin_10_2p5ns/`.
- Repair run: `build/openroad/v2_lite_antenna/input_buffer_fix_2p5ns/`.

## Marker disposition

| Marker | Corresponding net and geometry | Difference cause | Repair | Result |
|---|---|---|---|---|
| 1 | `s_axi_araddr[4]`; Metal6 rectangle `(52.665,0)`–`(52.805,57.26)` terminating at `input30/A` (`BUF_X1`) | KLayout computes $8.0164/0.02625=305.3867$, above 300. OpenROAD has no layer antenna model in the tech LEF and reports zero. | Keep the existing `input30` netlist cell at legal site `(52.06,1.40)`, next to the IO pin, before detailed placement. | Metal6 routed segment becomes `(52.665,0.07)`–`(52.805,2.10)`; no KLayout item. |
| 2 | `s_axi_araddr[5]`; Metal6 rectangle `(53.225,0)`–`(53.365,58.10)` terminating at `input31/A` (`BUF_X1`) | KLayout computes $8.134/0.02625=309.8667$, above 300. OpenROAD has no layer antenna model in the tech LEF and reports zero. | Keep the existing `input31` netlist cell at legal site `(52.63,1.40)`, next to the IO pin, before detailed placement. | Metal6 routed segment becomes `(53.225,0.07)`–`(53.365,0.42)`; no KLayout item. |

The XML values above are the rule's reported `ametal`, `agate`, `ratio`, and `max_ratio` fields. The count unit is a KLayout `<item>`, not each nested `<value>`; the original result has exactly two items, while the repaired result has zero. The marker-to-net association is established by intersecting each XML polygon with routed Metal6 shapes in the corresponding final ODB. See `baseline_markers.csv`, `baseline_net_geometry.csv`, and `fixed_net_geometry.csv`.

## Confirmed rule-model facts

- `FreePDK45.lydrc` maps Metal6 to GDS layer 21/0, connects the complete poly/contact/metal/via stack, derives `gate` from poly/active geometry, derives `diode` as `(nplus & active) - nwell`, and calls `antenna_check(gate, metal6, 300.0, diode)`.
- The original marker areas are exactly the full 0.14 µm-wide GDS Metal6 rectangles: $0.14\times57.26=8.0164\ \mu m^2$ and $0.14\times58.10=8.134\ \mu m^2$.
- The sink pins are both `BUF_X1/A`; its platform LEF reports `ANTENNAGATEAREA 0.02625`, matching KLayout's `agate` field.
- OpenROAD logs `GRT-0246` because the active platform LEF presents `ANTENNA_X1` as `CORE ANTENNACELL` but gives pin `A` an `ANTENNADIFFAREA` of 0.0. The Nangate45 tech LEF contains no layer antenna ratio properties, so OpenROAD's checker has no rule equivalent to KLayout's explicit 300:1 Metal6 check.
- The library GDS does contain geometry for `ANTENNA_X1`; applying the KLayout deck's diode expression produces 0.0081 µm². This conflicts with the zero LEF diffusion property. The cell is therefore not a complete, consistently modeled automatic repair resource in this platform configuration. No LEF property was invented or changed.
- OpenROAD detailed routing and antenna checking use routed OpenDB/LEF models. KLayout evaluates flattened final GDS geometry with its independent rule deck. Their zero/two discrepancy is explained by different rule inputs and geometric models, not by a layer-number mismatch.

## Repair choice and proof boundary

The selected repair is a supported placement constraint on two existing `BUF_X1` instances. It changes neither RTL nor the synthesized logical netlist. The locations are standard-cell sites in the first legal row; the normal ORFS detailed-placement stage validates legalization, and all downstream stages are regenerated in one fresh run. This directly shortens only the two offending IO-to-gate Metal6 conductors and avoids relying on an incompletely modeled diode.

Source-to-derived equivalence is 4,023/4,023 proven for the fresh run. This proves the frontend normalization, not the routed netlist. The repair itself does not add or reconnect logical cells, but later timing repair produces a slightly different physical netlist. Post-route equivalence and LVS remain unproven. This OpenROAD version has no `check_connectivity` command; available evidence is zero detailed-route DRC, zero OpenROAD antenna violations, successful final ODB/SPEF/GDS generation, and GDS merge reporting no missing or orphan library cells.

## Before/after physical results

| Metric | `cap_margin_10` baseline | Input-buffer repair |
|---|---:|---:|
| Setup WNS / TNS | +0.139143 / 0 ns | +0.128179 / 0 ns |
| Hold WNS / TNS | +0.00345954 / 0 ns | +0.00684956 / 0 ns |
| Functional standard cells | 5,834 | 5,836 |
| Functional standard-cell area | 11,418.6 µm² | 11,417.8 µm² |
| Timing-repair / clock buffers | 517 / 193 | 519 / 191 |
| Sequential cells | 801 | 801 |
| Max-cap / slew / fanout violations | 0 / 0 / 0 | 0 / 0 / 0 |
| Global overflow | 0 | 0 |
| Detailed-route DRC | 0 | 0 |
| OpenROAD antenna net / pin violations | 0 / 0 | 0 / 0 |
| KLayout DRC items | 2 | **0** |
| Detailed-route wirelength / vias | 82,550 µm / 40,351 | 82,498 µm / 40,302 |

The repaired critical path remains the Core path from `u_core.u_controller.cycle_idx[1]` through feeder/PE arithmetic to `PE(0,0)` accumulator bit 17. Its high-precision setup slack is +0.128179 ns. The two repaired AXI address nets are not the critical path. No PPA conclusion is drawn from the small area and routing differences; they include normal backend optimization differences caused by the placement constraint.

## Raw evidence and reproduction

- Original and repaired KLayout XML: each run's `work/reports/nangate45/systolic_axi_lite_n2_k17_constant_decode/base/6_drc.lyrdb`.
- KLayout logs: each run's `work/logs/nangate45/systolic_axi_lite_n2_k17_constant_decode/base/6_drc.log`.
- Routed ODB/SDC/SPEF/GDS: each run's `work/results/nangate45/systolic_axi_lite_n2_k17_constant_decode/base/`.
- Repaired high-precision STA: `build/openroad/v2_lite_antenna/input_buffer_fix_2p5ns/final_audit/`.
- Rule deck and layer map at the fixed ORFS commit: `flow/platforms/nangate45/drc/FreePDK45.lydrc` and `flow/platforms/nangate45/FreePDK45.lyt`.
- Placement hook: `physical/nangate45_lite_physical/antenna_input_buffer_fix.tcl`.

From WSL/Ubuntu:

```bash
export ORFS_ROOT=/path/to/OpenROAD-flow-scripts
export OSS_CAD_SUITE_ROOT=/path/to/oss-cad-suite-20260830
PHYSICAL_RUN=antenna_input_buffer_fix bash scripts/run_v2_lite_physical.sh
```

The command refuses to overwrite an existing published result. Two earlier hook-integration failures are preserved under `build/openroad/v2_lite_antenna/failed_*`; neither reached detailed placement.

## Conclusion boundary

All targeted checks executed by this flow now pass: extracted propagated-clock setup and hold, max capacitance/slew/fanout, global overflow, detailed-route DRC, OpenROAD antenna, full KLayout DRC, and GDS generation. The result is therefore a **clean physical baseline within the current Nangate45 single-corner, stated-check scope**. It is not commercial signoff, multi-corner closure, LVS, post-route formal equivalence, or a silicon-frequency result.
