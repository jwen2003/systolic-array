# V2 Lite-only post-synthesis long-path diagnosis

## Directly measured facts

This analysis reuses the fixed mapped netlist and SDC from the N=2, K=17, DATA_W=8, ACC_W=18 baseline. It is post-synthesis STA with the Nangate45 typical Liberty wire-load model, not post-route timing.

| Path | Data arrival | External/launch component | Combinational mapped-cell arcs | Buffer/inverter arcs | MUX arcs (max consecutive) | Wire-load delay | Slack |
|---|---:|---:|---:|---:|---:|---:|---:|
| `s_axi_araddr[12] (input port clocked by core_clk)` → `u_slave.s_axi_rdata_reg[10]$_SDFFE_PN0P_` | 11.120170 ns | 0.250000 ns input delay | 222 | 44 | 13 (2) | 0.004155 ns | -8.694842 ns |
| `u_slave.awaddr_saved[5]$_SDFFE_PN0P_` → `u_device.a_matrix[136]$_DFFE_PP_` | 10.870124 ns | 0.092712 ns clock-to-Q | 225 | 46 | 3 (1) | 0.004540 ns | -8.445550 ns |

The earlier “about 222 levels” statement is exact only for the read path: it contains **222 mapped combinational cell output arcs**. Input and output pin rows are not counted twice. The write path contains one launch DFF clock-to-Q arc plus **225 combinational cell arcs**. Clock path, external input delay, setup time, and endpoint clock are excluded from these logic-level counts.

High-fanout (fanout >= 10) drivers account for 17 arcs / 0.808167 ns on the read path and 17 arcs / 0.774791 ns on the write path. These are load-associated driver arc delays, not an independently separable wire-delay contribution.

## Evidence-supported diagnosis

- Both paths traverse very deep arithmetic-style mapped logic (half adders, XNOR/XOR, AOI/OAI, AND/OR) rather than a deep serial MUX chain. The read path has 13 MUX arcs but no more than 2 consecutive MUX arcs; the write path has 3 and no more than 1 consecutive MUX arcs.
- The final pre-tech frontend statistics retain 2 `$div_32` and 2 `$mod_32` cells after optimization. The retained JSON further contains 5741 primitive cells tagged with the A-read dynamic-index source at `systolic_device.sv:158` and 9611 tagged with the A-write dynamic-index source at line 230; 4284 cells carry both source locations. Together these establish that `/17` and `%17`-derived dynamic indexing survives normalization and that optimization shares portions of the read/write index network.
- Therefore the dominant common cause is the wide address-to-index/dynamic-array-selection network created around K=17, including divider/remainder-derived logic and its shared decode. Plain CSR/A/B/C result selection contributes, but the physical path is not dominated by a serial MUX tree.
- Buffer/inverter delay is exactly accounted in `path_breakdown.csv`; all remaining non-buffer standard cells are conservatively marked `unknown/shared logic` because source attributes were removed when the mapped Verilog was emitted. They are not guessed into address arithmetic, decode, data selection, or write-enable buckets.

`u_device.a_matrix[136]` is the first bit after 17 elements × 8 bits = 136 bits. Under the retained flattened ordering it corresponds to A row 1, k=0, data bit 0. The numerical boundary and write-index logic support this mapping; the mapped netlist no longer retains the original unpacked-array coordinate as metadata, so confidence is medium rather than absolute.

## Uncertainties and hypotheses still requiring validation

- Exact delay attribution among base subtraction, `/17`, `%17`, range/permission checks, bitmap checks, and dynamic data selection is unavailable after flattening and technology mapping. `path_breakdown.csv` deliberately leaves their combined delay in `unknown/shared non-buffer logic` rather than double-counting gates.
- OpenSTA reports cell-arc delay and wire-load input-pin increments. The latter is an estimated pre-layout interconnect model; it is not routed net delay.
- Neighboring worst input-to-register endpoints are adjacent read-data bits, and neighboring register-to-register endpoints are adjacent A-buffer bits, so the two reported paths represent repeated structures. This does not prove all design paths share the same cause.

## Candidate follow-up experiments (not implemented)

1. Replace only the `/17` and `%17` address decomposition in an isolated diagnostic copy with a bounded compare/subtract or predecoded table, then remap under the same constraints. Compare cone depth and path delay; do not infer top-level benefit from the microbenchmark alone.
2. In a diagnostic RTL variant, separate index generation from the A/B/CSR read multiplexer with an observable register boundary. Re-run synthesis and post-route timing to test whether timing improves enough to justify the added transaction latency and state; the present report does not establish that tradeoff.

## Evidence files

- `build/v2_lite_path_diagnosis/high_precision_paths.rpt`: complete six-digit OpenSTA paths and ten neighboring paths per class.
- `reports/v2_lite_path_diagnosis/path_details.csv`: one row per mapped cell output arc, including load, slew, delay, arrival, and conservative ownership.
- `reports/v2_lite_path_diagnosis/path_breakdown.csv`: non-overlapping additive delay accounting plus explicitly non-additive functional evidence rows.
- `rtl/wrapper/systolic_device.sv:112`, `:148`, `:230`: write decode, read decode/index/data selection, and A-buffer write.
