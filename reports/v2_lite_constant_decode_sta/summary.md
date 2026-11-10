# V2 Lite constant-address decode synthesis/STA comparison

## Measured comparison

| Metric | Baseline | Constant decode | Delta |
|---|---:|---:|---:|
| Mapped cell area | 24493.280 µm² | 10928.078 µm² | -13565.202 µm² |
| Mapped cells | 14823 | 5165 | -9658 |
| Sequential cells / area | 801 / 3622.122 µm² | 801 / 3622.122 µm² | unchanged |
| Combinational cells / area | 14022 / 20871.158 µm² | 4364 / 7305.956 µm² | -9658 / -13565.202 µm² |
| Buffers / inverters | 860 / 1058 | 353 / 202 | -507 / -856 |
| Setup WNS / TNS | -8.69 / -2351.48 ns | -0.08 / -0.22 ns | +8.61 / +2351.26 ns |
| Hold WNS / TNS | -0.04 / -0.08 ns | -0.04 / -0.07 ns | +0.00 / +0.01 ns |
| Max-capacitance violations | 7 | 5 | -2 |
| Original read bottleneck logic | 10.870170 ns / 222 arcs | 0.606711 ns / 12 arcs | -10.263459 ns / -210 |
| Original write bottleneck logic | 10.777412 ns / 225 arcs | 0.720582 ns / 13 arcs | -10.056830 ns / -212 |

The new worst setup path is `u_core.u_controller.cycle_idx[0]$_SDFFE_PN0P_` → `u_core.u_array.gen_row[0].gen_col[1].u_pe.psum_out[17]$_SDFFE_PN0P_`. It is inside the V1 controller/feeder/PE datapath, so the former AXI read/write decode bottlenecks have migrated out of first place.

## Functional verification

- `tb_systolic_device`: 391 checks, including row-boundary/last-element mapping, direct storage and bitmap observation, unwritten reads, sign extension, and high-address alias rejection.
- AXI-Lite integration: N/K = 1/1 (178 checks), 2/3 (262), 2/17 (514), and 3/5 (402), each with an independent matrix golden model.
- Existing AXI slave and burst-slave unit tests: 84 and 132 checks.
- Existing Burst comparison: 1531 checks. Packed comparisons: N/K = 2/17 (772), 2/16 (725), 3/5 (480), and 1/5 (264).
- Verilator 5.032 `-Wall --assert`: no warning or error in the rebuilt affected tests.

## Interpretation boundaries

- Same top, parameters, Nangate45 typical Liberty, 2.5 ns SDC, I/O assumptions, ABC flow, and `5K_hvratio_1_1` wire-load model as the baseline.
- This is mapped post-synthesis STA, not placement or post-route timing.
- Source-to-derived equivalence proves 4023/4023 cells. This does not prove old Device RTL and new Device RTL are equivalent.
- The only runtime `/` and `%` operations left in Device RTL are in the optional packed-access branch. The Lite-only mapped result has `PACKED_ENABLE=0`; no conclusion is claimed for optimizing packed accesses.
- The remaining setup violation (-0.08 ns) is in the Core path and requires separate architectural or physical investigation.
