# V2 Lite-only N2/K17 Nangate45 synthesis and post-synthesis STA

## 1. Measured data

- Top/parameters: `systolic_axi_lite_top`, N=2, K=17, DATA_W=8, ACC_W=18; Lite-only, no Burst or packed path.
- Nangate45 typical (1.10 V, 25 C), mapped cell area **24493.280 µm²**, 14823 cells.
- Sequential: 801 cells / 3622.122 µm²; combinational: 14022 cells / 20871.158 µm².
- Buffers (including clock buffers): 860; inverters: 1058; inferred memories: 0.
- Setup WNS/TNS: **-8.69 / -2351.48 ns**.
- Hold WNS/TNS: **-0.04 / -0.08 ns**.
- Worst overall/input→register: `s_axi_araddr[12] (input port clocked by core_clk)` → `u_slave.s_axi_rdata_reg[10]$_SDFFE_PN0P_`, arrival 11.12 ns, required 2.43 ns, slack -8.69 ns.
- Worst register→register: `u_slave.awaddr_saved[5]$_SDFFE_PN0P_` → `u_device.a_matrix[136]$_DFFE_PP_`, slack -8.45 ns.
- Worst register→output slack: 2.02 ns. No input→output path was found.
- Electrical check reports 7 max-capacitance violations; no max-slew or max-fanout violation is printed.
- All synthesis checks report 0 problems; ORFS synthesis reports 0 warnings and 0 errors. Source-to-derived equivalence proves 3959/3959 cells.

## 2. Experimental assumptions and limitations

- Clock period 2.500 ns, uncertainty 0.050 ns, input/output max delay 0.250 ns, min delay 0, input transition 0.050 ns, output load 0.010 pF.
- The AXI I/O budget is an explicit comparison assumption reused from V1, not a measured interconnect contract.
- `rst_n` is synchronous active-low and explicitly false-pathed only for active-operation analysis. `check_setup` therefore lists it as the sole input without delay; there are no unintentionally unconstrained functional endpoints.
- Interconnect uses Liberty default wire-load model `5K_hvratio_1_1`; there is no placement, CTS, routed parasitic extraction, or clock-tree delay. This is not post-route timing.
- Hold uses ideal clock, zero min I/O delay and pre-layout wire-load assumptions; it is diagnostic, not a hold-closure result.
- Setup/hold violating endpoint counts are marked unavailable because this OpenSTA summary does not emit a direct unique-endpoint total.
- The mapped design is flattened. Core/Device/AXI area cannot be assigned reliably without changing the main optimization boundary, so no guessed hierarchy split is reported.
- A/B data maps to flip-flop state, not a memory macro. Theoretical partial state cross-checks are 544 A/B data bits, 68 bitmap bits and 72 accumulator bits; these are not total register count or area estimates.
- Detailed cell/net-delay separation is unavailable at full precision. The report shows ideal clock and wire-load/capacitance effects, with net increments rounded to 0.00 ns in the printed path.

## 3. Questions for independent analysis

1. Is area dominated by storage, compute, or interface control? See `cell_types.csv`, `synth_stat.rpt`, and the missing hierarchy-attribution limitation above.
2. What class is the worst path and what logic does it traverse? See `timing_paths.csv` and the full raw report under `build/v2_lite_synth_sta/n2_k17_2p5ns/sta/openroad_sta.log`.
3. Does the result support the earlier Buffer/Feeder-selection-path hypothesis? The global worst path is AXI read-address decode/read-data selection, while the worst reg→reg path is listed separately; compare both before attributing causality.
4. What requires placement and routing? Net delay, congestion, buffering, fanout repair, CTS/skew, routed setup/hold, physical critical-path migration, and achievable clock rate all remain unconfirmed.

## 4. Reproduction and traceability

From any working directory, with the fixed ORFS checkout and local OSS CAD Suite available:

```bash
ORFS_ROOT=/path/to/OpenROAD-flow-scripts OSS_CAD_SUITE_ROOT=/path/to/oss-cad-suite-20260830 bash /path/to/systolic-array/scripts/run_v2_lite_synth_sta.sh
```

The command requires the formal output directory to be absent, preserving fresh-build semantics. Run `python3 scripts/summarize_v2_lite_synth_sta.py` from any directory to regenerate this report after a successful flow. Source hashes and environment identity are in `source_sha256.txt` and `manifest.txt`. Full mapped netlist, ODB, frontend logs and OpenSTA report remain under ignored `build/v2_lite_synth_sta/n2_k17_2p5ns/`; the small audit copies in this directory do not include generated netlists or databases.
