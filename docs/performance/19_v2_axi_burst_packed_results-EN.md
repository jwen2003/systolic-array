# Systolic Array V2: AXI Burst and Packed Results

[English](19_v2_axi_burst_packed_results-EN.md) | [简体中文](19_v2_axi_burst_packed_results-zh_CN.md)

This chapter consolidates the completed V2 Wrapper work through the controlled packed-versus-unpacked cycle comparison. V2 surrounds the frozen output-stationary Core with matrix input storage, written bitmaps, command/status control, AXI-Lite, and a restricted AXI write-burst interface. It does not replace the V1 Core verification, synthesis, physical baseline, or Registered Boundary conclusions.

## 1. Configuration and Timing Boundaries

The main experiment fixes `N=2`, `K=17`, `DATA_W=8`, and `ACC_W=18`. A and B each contain 34 INT8 elements, while C has four results. RTL cycles are measured with the Verilator BFM using one outstanding transaction, no artificial request gap, and immediate response READY. Every mode performs input loading, the READY check, START, DONE polling, C readback, and ACK.

End-to-end timing starts with the first input request and ends with the last C response; ACK is reported separately. Device START acceptance to DONE is 20 cycles. The 22-cycle polling window overlaps computation and must not be added twice. Physical results use Nangate45 typical (1.10 V, 25 °C), 2.500 ns active-operation constraints, extracted post-route parasitics, and propagated clocks.

The interface is a restricted implementation, not a claim of full AXI4, DMA, CPU, or DDR system performance.

## 2. Constant Decode for the Normal A/B/C Windows

The old Device converted byte addresses into row/column indices at runtime and dynamically indexed the matrices. The optimized implementation elaborates a full address constant for every fixed coordinate:

- A: `A_BASE + 4*(r*K+k)`;
- B: `B_BASE + 4*(k*N+c)`;
- C: `C_BASE + 4*(r*N+c)`.

Writes match the full address to a fixed coordinate and bitmap bit. Reads form a one-hot OR of mutually exclusive hit terms while preserving unwritten-read-zero behavior, permissions, sign extension, error priority, and rejection of high-address aliases. Each 32-bit slot in the normal `0x1000`/`0x2000` windows still carries one INT8 value.

| Lite mapped-synthesis metric | Old dynamic index | Constant-address decode | Change |
|---|---:|---:|---:|
| Mapped cell area | 24,493.280 µm² | 10,928.078 µm² | −13,565.202 µm² (−55.38%) |
| Mapped cells | 14,823 | 5,165 | −9,658 |
| Original read-bottleneck logic delay | 10.870170 ns | 0.606711 ns | −10.263459 ns |
| Original write-bottleneck logic delay | 10.777412 ns | 0.720582 ns | −10.056830 ns |

The global worst setup path moves back to the Core `cycle_idx → feeder/PE → accumulator` cone. These are post-synthesis STA results with Nangate45 mapped cells, ideal clocks, and a wire-load model, not routed timing. Evidence: [`reports/v2_lite_constant_decode_sta/`](../../reports/v2_lite_constant_decode_sta/).

## 3. Lite, Single-Beat Burst, and Burst-Length Sweep

The length sweep uses the unpacked windows of the current Burst RTL. Maximum length is a runtime `AxLEN`; all lengths share the same Burst hardware and netlist. A and B each contain 34 elements and use short tail bursts as needed.

| Maximum length (beats) | A/B input-write transactions | W beats | Pure A/B writes (cycles) | End-to-end (cycles) |
|---:|---:|---:|---:|---:|
| 1 | 68 | 68 | 204 | 239 |
| 2 | 34 | 68 | 136 | 171 |
| 4 | 18 | 68 | 104 | 139 |
| 8 | 10 | 68 | 88 | 123 |
| 16 | 6 | 68 | 80 | 115 |

For the current continuously supplied BFM and Slave:

$$
T_{write}=N_{W\ beat}+2N_{A/B\ transactions}
$$

The two fixed cycles per transaction correspond to AW setup and B response. Longer bursts amortize this transaction cost, but W beats, computation, polling, and readback remain fixed, so gains diminish. Lite and single-beat Burst both take 239 cycles under the same control policy. This is a controlled property of the current BFM/Slave, not a general AXI timing guarantee. The CSV total-write-transaction field also counts START and ACK; the table reports only A/B input writes.

Raw cycle and handshake evidence: [`reports/v2_lite_vs_burst/`](../../reports/v2_lite_vs_burst/).

## 4. Same-Batch Lite versus Burst Physical Cost

To avoid mixing different frontends or implementation stages, Lite and Burst were rerun fresh with the same frontend, tools, corner, constraints, floorplan policy, and final checks. Burst uses unpacked transfers with `PACKED_ENABLE=0`.

| Metric | Lite | Burst | Burst versus Lite |
|---|---:|---:|---:|
| Mapped area / cells | 10,655.960 µm² / 5,020 | 11,545.730 µm² / 5,553 | +8.350% / +533 |
| Final functional standard-cell area / cells | 11,041.972 µm² / 5,398 | 12,159.914 µm² / 6,221 | +10.124% / +823 |
| Setup WNS | +0.161062 ns | +0.172356 ns | both pass |
| Hold WNS | +0.0128362 ns | +0.0123354 ns | both pass |
| Global overflow | 0 | 0 | no added overflow |
| Detailed-route / OpenROAD antenna / KLayout DRC | 0 / 0 / 0 | 0 / 0 / 0 | both clean |

Final functional standard-cell area includes logic, clock, and timing-repair cells while excluding filler and tap cells. Burst adds approximately 10.12% over Lite. This hardware-cost comparison must remain separate from the packed0/packed1 comparison below. Evidence: [`reports/v2_burst_physical/`](../../reports/v2_burst_physical/).

## 5. Packed Constant Word-Address and Byte-Lane Decode

Packed aliases occupy `0x4000`/`0x5000`. A 32-bit word carries up to four consecutive INT8 elements. For each fixed linear element index $p$, elaboration determines word index $\lfloor p/4\rfloor$, lane $p\bmod4$, full word address, matrix coordinate, and bitmap bit. Runtime logic only checks the address hit, permission/error gates, and `WSTRB[lane]`; all legal lanes in one word can update independently on the same edge.

For `N=2`, `K=17`, A packed word 4 crosses a row boundary: lane 0 is `A[0][16]`, and lane 1 is `A[1][0]`. If `WSTRB` selects an illegal lane in a tail word, the existing contract rejects the entire beat with no matrix or bitmap side effect. Normal unpacked-window semantics remain unchanged.

| `PACKED_ENABLE=1` mapped-synthesis metric | Old dynamic index | Constant word/lane decode | Change |
|---|---:|---:|---:|
| Mapped area | 47,206.488 µm² | 12,109.118 µm² | −35,097.370 µm² (−74.35%) |
| Mapped cells | 32,701 | 5,889 | −26,812 |
| Setup WNS | −11.434590 ns | reported as 0 ns | bottleneck leaves packed write path |
| Representative packed address-to-matrix path | about 282 combinational cells | 13 combinational cells | endpoints are not identical |

The new frontend netlist has zero runtime `$div`/`$mod` templates in the packed path. Representative packed address-to-matrix and bitmap slacks are +1.674469 ns and +1.692279 ns. The global critical path moves back to the Core, but packed support still has an area cost. Evidence: [`reports/v2_packed_constant_decode_synth_sta/`](../../reports/v2_packed_constant_decode_synth_sta/).

## 6. Current-RTL packed0/packed1 Physical Comparison

Both runs use the optimized Burst Top, the same Core, identical 2.500 ns constraints, and the same physical checks. Each floorplan is sized for its own area; percentages are calculated only within this pair.

| Metric | `PACKED_ENABLE=0` | `PACKED_ENABLE=1` (after antenna repair) | Increment |
|---|---:|---:|---:|
| Mapped area / cells | 11,372.032 µm² / 5,542 | 12,109.118 µm² / 5,889 | +737.086 µm² / +347 |
| Final functional standard-cell area / cells | 12,002.412 µm² / 6,216 | 12,924.984 µm² / 6,821 | +922.572 µm² (+7.687%) / +605 |
| Timing-repair / clock buffers | 800 / 191 | 1,066 / 191 | +266 / 0 |
| Setup WNS / TNS | +0.115657 / 0 ns | +0.149201 / 0 ns | both pass |
| Hold WNS / TNS | +0.004894 / 0 ns | +0.008039 / 0 ns | both pass |
| Slew / cap / fanout violations | 0 / 0 / 0 | 0 / 0 / 0 | clean |
| Global overflow | 0 | 0 | clean |
| Detailed-route / OpenROAD antenna / KLayout DRC | 0 / 0 / 0 | 0 / 0 / 0 | clean |

Both global worst paths remain in the Core `cycle_idx → feeder/PE → accumulator` cone. Routed packed1 `current_addr → matrix` and `current_addr → bitmap` paths have +1.448011 ns and +1.502475 ns slack.

The default packed1 run had one KLayout `METAL6_ANTENNA` item on the long route from `s_axi_araddr[4]` to an existing input buffer: ratio 331.413333 versus threshold 300. The repair fixes that buffer to a legal site near the IO without changing RTL, logical connectivity, or timing exceptions. The fresh repaired run has zero KLayout items, zero OpenROAD antenna violations, and zero detailed-route DRC.

These measurements are Nangate45 typical single-corner results with extracted parasitics and propagated clocks, not commercial signoff or silicon Fmax. Evidence: [`reports/v2_packed_physical/`](../../reports/v2_packed_physical/).

## 7. Controlled Packed versus Unpacked Cycle Comparison

Both modes use one `systolic_axi_burst_top` elaborated with `PACKED_ENABLE=1`, the same data, BFM, golden model, maximum burst length 16, and event-counting code. The DUT is reset before each mode. Only the A/B write windows and payload packing change.

| Mode | Bursts per matrix | A/B transactions / W beats | Pure writes / load with READY | START→DONE / C readback | End-to-end / including ACK |
|---|---|---:|---:|---:|---:|
| Unpacked | 16+16+2 beats | 6 / 68 | 80 / 82 | 20 / 8 | 115 / 118 |
| Packed | 9 beats, tail `WSTRB=0x3` | 2 / 18 | 22 / 24 | 20 / 8 | 57 / 60 |

End-to-end time falls from 115 to 57 cycles, a measured $115/57=2.0175\times$ speedup. Of the 58 saved cycles, 50 come from sending 50 fewer W beats and eight from removing four transactions at two fixed cycles each. START-to-DONE remains 20 cycles; 22 cycles of polling overlap computation.

All four C elements in both modes pass an independent signed matmul golden model, and the two result vectors are compared directly. Every transaction returns `OKAY`. The old packed regression's 62-cycle total begins before a two-cycle preflight status read and includes ACK; removing that preflight aligns it with the current 60-cycle repeat-task boundary. Evidence: [`reports/v2_packed_performance/`](../../reports/v2_packed_performance/).

## 8. Verification and Proof Boundaries

- Functional regression establishes protocol, address, bitmap, side-effect, and matrix-result behavior for the executed stimuli, including a cross-row packed word, single/multiple lanes, partial/zero/illegal tail strobes, high-address aliases, ACK/reload, fixed-seed backpressure, and an independent golden model. It is not a formal equivalence proof.
- Source-to-derived frontend equivalence proves each source RTL against its own derived Verilog: Lite 4,023/4,023; unpacked Burst 4,401/4,401; packed0 4,614/4,614; packed1 5,173/5,173. It does not prove old RTL against new RTL, mapped equivalence, or post-route equivalence.
- Physical checks establish the executed STA, electrical, overflow, detailed-route DRC, OpenROAD antenna, and KLayout DRC results for the corresponding GDS/ODB runs. DRC clean is not LVS or formal equivalence.
- Kepler stage LEC remains disabled because of CPU SIGILL. Post-route formal equivalence and LVS are not proven.
- All PPA numbers apply only to Nangate45 typical, the stated parameters, and active-operation constraints. There is no trustworthy power, multi-corner signoff, or real CPU/DDR/PCIe performance conclusion.

## 9. Reproduction

Run these commands from the repository root. Physical flows require the recorded `ORFS_ROOT` and `OSS_CAD_SUITE_ROOT` environments.

```bash
bash scripts/run_v2_lite_constant_decode_sta.sh
bash scripts/run_v2_lite_vs_burst.sh
OPENROAD_THREADS=16 bash scripts/run_v2_burst_physical.sh
OPENROAD_THREADS=16 bash scripts/run_v2_lite_comparable_physical.sh
bash scripts/run_v2_packed_synth_sta.sh
PACKED_ENABLE=1 OPENROAD_THREADS=16 bash scripts/run_v2_packed_physical.sh
PACKED_ENABLE=0 OPENROAD_THREADS=16 bash scripts/run_v2_packed_physical.sh
PACKED_ENABLE=1 PHYSICAL_RUN=antenna_input_buffer_fix OPENROAD_THREADS=16 bash scripts/run_v2_packed_physical.sh
python3 scripts/summarize_v2_packed_physical.py
bash scripts/run_v2_packed_performance.sh
```

This chapter stops at V2 interface loading, functional verification, synthesis/STA, physical implementation, and controlled RTL cycle measurement. Packed is not DMA. The current follow-up order is sticky-DONE polling intervals, double buffering, and DMA, followed by OS versus WS. Real software/memory systems, power, LVS, and post-route formal remain separate future work.
