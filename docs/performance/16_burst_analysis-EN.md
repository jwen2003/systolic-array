# Lite versus Burst Load Model and RTL Measurements

[English](16_burst_analysis-EN.md) | [简体中文](16_burst_analysis-zh_CN.md)


## 1. Question and Controls

Hypothesis: amortizing address/response cost over multiple beats reduces small-matrix loading overhead. Hold N=2, K=17, INT8/INT18, input data/Core, control/poll/readback policy, continuous supply and clock constant. One INT8 still occupies a 32-bit slot; there is no packing.

Lite runs on the dual-port Top, so this comparison does not quantify the extra port's area. See [AXI scope](../wrapper/13_axi_protocol-EN.md). Burst is not DMA.

## 2. Independent Model

Let D=2*N*K, maximum beats L, and B=2*ceil(N*K/L), splitting A/B separately with short tails. With no contention, per-Burst nondata overhead H=2 and final ready-read cost R=2:

$$T_{load}=D+BH+R$$

H=2 was a pre-RTL prediction subsequently checked against data-stage and total RTL counts. It is not guaranteed by AXI. models/wrapper/burst_load_model.py produces model predictions, not RTL observations.

## 3. Continuous-Supply Measurements

| Path/maximum length | Confirmed load | Full invocation |
|---|---:|---:|
| Lite | 206 | 244 |
| Burst 1 | 206 | 244 |
| Burst 2 | 138 | 176 |
| Burst 4 | 106 | 144 |
| Burst 8 | 90 | 128 |
| Burst 16 | 82 | 120 |

Units are DUT cycles, with two data operations per setting and golden checks. Snapshot: [burst_comparison.csv](../../reports/wrapper/burst_comparison.csv). Full invocation runs from preflight STATUS through ACK response. Confirmed load includes the final ready read. The other 38 cycles remain equal in this setting only, not for arbitrary N/K or polling.

## 4. Gaps and Attribution

BFM gap is inserted only between successful beats within one Burst. First beat is immediately available; there is no post-last-beat gap. Model slave_gap is hypothetical, not an implemented adjustable delay of the continuous receiver.

Each data cycle is classified exclusively: transfer=VALID/READY 1/1, master_only=0/1, slave_only=1/0, both=0/0. Do not double-count simultaneous waits. With current slave_gap=0:

$$T_{load}=D+(D-B)G+2B+2$$

G=3 can make longer Bursts slower as D-B internal gaps increase. That establishes this stimulus policy, not a universal short-Burst preference. If data preparation also crosses transactions or overlaps AW/B, change the model. Nonzero-gap rows are sensitivity tests, not fair comparisons against a Lite Host without matching preparation constraints.

## 5. Conclusions

[Established] Under continuous supply/no write contention, L16 is the minimum-cycle tested reference: load 82, invocation 120. The independent model agrees with 30 Burst rows.

[Hypotheses] Packing may change receive interval, area/frequency and Host supply. See [packing experiment](17_packed_analysis-EN.md). No DDR, CPU, PCIe, power or final Pareto claim follows.
