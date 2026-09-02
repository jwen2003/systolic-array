# Systolic Array MVP: Physical Implementation and PPA Analysis

[English](07_physical_implementation_plan-EN.md) | [简体中文](07_physical_implementation_plan-zh_CN.md)

## 1. Scope and Fixed Baseline

[Established fact] The implementation fixes $N=2$, $K=2$, `DATA_W=8`, and `ACC_W=18` with:

- ORFS commit `6101364b2d7909dd797e1e3e7f80695401cfa4e4`, description/tag `26Q3-345-g6101364b2`;
- immutable image `openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0`;
- OpenROAD `26Q3-1305-gf552262465`, container Yosys `0.68+post`, OpenSTA `3.1.0`;
- Yosys `0.68+136` for read_slang and independent formal.

All formal PPA numbers come from one complete fresh flow under that image, without combining netlists, ODB, placement, CTS, routing, or timing from another tool version. The baseline completed RTL/read_slang, Nangate45 mapping, floorplan, placement, CTS, global and detailed routing, extraction, final STA, GDS, and KLayout DRC.

## 2. Kepler Formal Compatibility and `LEC_CHECK`

[Tool limitation] The failure was not CTS. Clock-tree construction, post-CTS detailed placement, and `repair_timing` completed before `kepler-formal --config 4_rsz_lec_test.yml` raised `SIGILL`; even `kepler-formal --help` exited 132. Official Nangate45/GCD, 16-thread Systolic, and single-thread Systolic reproduced it under three pinned images:

- `sha256:d995618be9f2bcdfa5538b885123463070dfbf178bea1818716d4652fe0fa380`;
- `sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0`;
- `sha256:2e22028b36fd7a1cc6952f0f864527b88e42577acb1068fa0e34d373e61dec47`.

`LEC_CHECK` is an official CTS-stage ORFS variable. `LEC_CHECK=0` only suppresses the Kepler comparison netlist and `run_lec_test`; it does not change SDC or skip CTS, placement, timing repair, routing, extraction, STA, GDS, or DRC. The project config explicitly sets it to 0, and diagnosis evidence remains preserved.

## 3. Equivalence Evidence by Layer

- [Established fact] Baseline RTL to read_slang-derived frontend Verilog: 843/843 `$equiv` cells proven using `equiv_simple` plus 10-step `equiv_induct`.
- [Verification gap] Derived frontend to the 1902-cell mapped netlist: `inconclusive_tool_scalability`; sequential solving made no practical progress and was stopped without a counterexample. It is neither pass nor fail.
- [Tool limitation] Kepler stage LEC: `disabled_due_to_cpu_sigill`.
- [Verification gap] Post-route equivalence: not proven.

RTL Verilator regression verifies the original frozen baseline; it does not substitute for mapped or post-route equivalence.

## 4. Constraint Methodology

The run reuses the Butterfly 400 MHz evaluation methodology—it is not called the Butterfly default:

- period 2.500 ns; uncertainty 0.050 ns; clock transition 0.050 ns;
- input/output delay 0.250 ns; input transition 0.050 ns; output load 0.010;
- core utilization 50%; aspect ratio 1; placement-density lower-bound addon 0.10.

`rst_n` is a synchronous active-low reset. Active-operation STA false-paths `rst_n`, assuming it is released before the operation and stable during computation; external reset assertion/deassertion timing is not checked. Thus the 400 MHz result applies only to active-operation mode. Matrix inputs, `cycle_idx → feeder → boundary PE`, and result reads have no false or multicycle path. `check_setup` finds 0 unconstrained endpoints; the only input without delay is the explicitly false-pathed reset.

## 5. Mapping and Area

| Metric | Result |
|---|---:|
| Mapped standard cells | 1902 |
| Mapped cell area | 3442.572 µm² |
| Sequential cells / area | 110 / 497.420 µm² |
| Mapped combinational area | 2945.152 µm² |
| FA_X1 / HA_X1 | 228 / 182 |
| BUF_X1 / BUF_X2 / CLKBUF_X1 | 111 / 1 / 6 |
| INV_X1 | 102 |
| Final functional standard cells | 2068 |
| Final functional standard-cell area | 3522.64 µm² |
| All final instances including fill/tap | 4406 |

Mapped area, detailed-placement design area `3502.95 µm²`, final functional cell area `3522.64 µm²`, core area `6711.18 µm²`, and die area `7220.75 µm²` are distinct metrics. The final 2068 functional cells exclude 116 tap and 2338 fill cells. Four PE multiplier/accumulator datapaths map to FA, HA, and Boolean cells rather than multiplier macros. Final categories include 152 timing-repair buffers, 9 clock buffers, 7 clock inverters, and 102 ordinary inverters.

## 6. Floorplan and Placement

| Metric | Result |
|---|---:|
| Die / core area | 7220.75 / 6711.18 µm² |
| Floorplan / detailed utilization | 51.30% / 52.20% |
| Detailed-placement instances | 2052 |
| Detailed-placement design area | 3502.95 µm² |
| Estimated wirelength | 17466.6 µm |
| Placement violations | 0 |

There are no macros. Controller, Feeder, and PE cells share the small core; the final critical path directly couples control/Feeder logic to a boundary PE.

## 7. CTS

| Metric | Result |
|---|---:|
| Original sinks | 110 |
| Clock-tree levels | 3 |
| Clock buffers | 9 `CLKBUF_X3` |
| Dummy loads / buffer path depth | 7 / 2 |
| Rise latency | 0.091352–0.095769 ns |
| Fall latency | 0.093781–0.098114 ns |
| Final setup / hold skew | 0.053165 / 0.054306 ns |

CTS, post-CTS placement, and timing repair completed without placement, setup, or hold violation.

## 8. STA

| Stage | Setup WNS | Setup TNS | Hold WNS | Hold TNS |
|---|---:|---:|---:|---:|
| Independent post-synthesis STA | not established | not established | not established | not established |
| Floorplan | 0.859363 ns | 0 | 0.060854 ns | 0 |
| Detailed placement | 0.713213 ns | 0 | 0.063979 ns | 0 |
| Post-CTS | 0.714560 ns | 0 | 0.064591 ns | 0 |
| Post-global-route | 0.675832 ns | 0 | 0.067274 ns | 0 |
| Final extracted post-route | 0.720010 ns | 0 | 0.065023 ns | 0 |

ORFS did not produce independent STA on unfloorplanned `1_synth.odb`; the floorplan result must not be relabeled post-synthesis STA. Final transition, capacitance, fanout, setup, and hold violation counts are all 0.

## 9. Post-Route Critical Path

```text
u_controller.cycle_idx[0]/Q
→ feeder/control selection
→ boundary PE multiplier/accumulator logic
→ u_array.gen_row[1].gen_col[0].u_pe.psum_out[17]/D
```

Data-path delay is 1.69648 ns, excluding source clock-network latency. Cell delay is 1.69028 ns (99.63%); extracted net delay is 0.00620 ns (0.37%); slack is 0.72001 ns. In this small core, combinational cell delay dominates and the path remains `cycle_idx → feeder/control → boundary PE accumulator`.

## 10. Routing, Extraction, and DRC

| Metric | Result |
|---|---:|
| Global-route wirelength / resource usage | 31367 µm / 17.91% |
| Maximum layer usage | Metal2, 49.55% |
| Global overflow | 0 |
| Detailed-route wirelength / vias | 18551 µm / 13035 |
| Detailed-route DRC | 0 |
| Extracted nets / RC segments | 2532 / 6994 |
| KLayout DRC | 0 |
| Final GDS | `6_final.gds` generated |

Global routing, detailed routing, fill, extraction, final STA, GDS merge, and KLayout DRC all ran; final SPEF is nonempty. GRT's 31367 µm measures estimated global routing-tree planar segments with its grid-tile convention and no via-equivalent length. DRT's 18551 µm sums final planar `frPathSeg` shapes; 13035 vias are counted separately. The units match, but the stages, geometry, and definitions do not, so no improvement percentage is computed.

## 11. Warning Audit

Floorplan warnings concern core snapping and pre-parasitic wire-load estimation. The 92 `RSZ-0104` one-pin nets classify completely as 72 unused accumulator-register `QN`, 16 unused forwarding `QN`, 2 unused valid-forwarding `QN`, 1 unused Controller `done` `QN`, and 1 unused half-adder sum. None is a clock/sink, reset, functional top port, required Feeder output, accumulator `Q`, or 18-bit result. Detailed routing reports no antenna violation; finish warnings concern a deprecated extractor option and headless GUI environment. All stage error counts and final DRC/timing/electrical violation counts are 0.

## 12. `acc_clear` and Protocol Review

RTL regression continues to check matrix stability, Controller/Feeder/reset protocols, exactly $K$ MACs per PE, and A/B/k pairing. Physical flow adds no false or multicycle path. Timing repair eliminates max-fanout violations, but anonymized combinational nets prevent attributing every repair buffer specifically to `acc_clear`; no such tree is claimed proven.

## 13. Applicability Boundary

These results are a reproducible Nangate45/FreePDK45 educational-platform, typical-corner baseline—not commercial-process signoff. There is no multi-corner/multi-mode analysis, qualified extraction, OCV/AOCV/POCV, real switching activity, or silicon correlation. The roughly 0.823 mW default-assumption estimate is not trustworthy project power. Results establish an area, timing, and routability reference for N2/K2 but not complete PPA, and must not be extrapolated to other $N/K$ values before a controlled scaling sweep.
