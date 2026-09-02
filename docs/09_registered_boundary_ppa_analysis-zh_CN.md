# Systolic Array MVP: Registered Boundary PPA 分析

## 1. 实验目的

[已建立事实] 本实验评估在 `input_feeder` 与 `systolic_array` 之间加入一级 Registered Boundary，能否切断 baseline 的 Feeder/control 到边界 PE accumulator 的长组合路径，并量化其周期、面积与物理收敛代价。实验保持 $N=2$、$K=2$、`DATA_W=8`、`ACC_W=18`、Nangate45 平台、active-operation 约束以及固定 ORFS 环境不变。

- ORFS commit：`6101364b2d7909dd797e1e3e7f80695401cfa4e4`；
- 镜像：`openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0`；
- baseline 与 Registered Boundary 均采用 non-overlap operation 协议。

## 2. Baseline 与 Registered Boundary 的结构差异

[已建立事实] 两个版本均保留 4 个 PE、4 个 signed $8\times8$ multiplier 和 4 个 18-bit accumulator adder。Registered Boundary 不复制或删除 MAC datapath，而是在 A/B boundary data 及其 valid 上加入一级寄存器；baseline Top 与 RTL 保持不变，variant 使用独立 Top、Controller、Boundary module、综合 filelist 和物理配置。

| 结构指标 | Baseline | Registered Boundary |
|---|---:|---:|
| PE | 4 | 4 |
| Signed $8\times8$ multiplier | 4 | 4 |
| 18-bit accumulator adder | 4 | 4 |
| Generic register bits | 110 | 145 |
| RUN cycles | 4 | 5 |

[基于结构的解释] Boundary 的逻辑状态量为

$$
2\times N\times(\mathrm{DATA\_W}+1)=2\times2\times9=36\ \text{bits}.
$$

Yosys 将波形等价的 valid 状态合并，最终只保留 34 个独立 Boundary register bits；pipelined Controller 的 counter 比 baseline 多 1 bit，因此总 register bits 从 110 增至 $110+34+1=145$。这属于当前工具版本下的优化结果，不应外推为所有综合工具的固定打包方式。

## 3. 功能与周期语义

[已建立事实] Registered Boundary 的 RUN 窗口为

$$
\mathrm{TOTAL\_RUN\_CYCLES}=K+2N-1,
$$

最后周期为 $K+2N-2$。对 N2/K2，RUN cycle 为 0 至 4：RUN 0 只将 Feeder 输出装入 Boundary，并清空 PE accumulator；第一次 MAC 在 RUN 1，最后一次 MAC 在 RUN 4。PE$(i,j)$ 在 RUN cycle $t$ 的 pairing monitor 使用

```text
k = cycle_idx - 1 - i - j
```

每个 PE 仍执行恰好 $K$ 次 MAC，A/B/k 数学配对和最终矩阵结果不变；`done` 在最后一次 MAC 提交的同一同步边沿后可见。相较 baseline，operation 增加一拍。

## 4. Generic synthesis 结构对比

[已建立事实] 相同 read_slang/Yosys pass sequence 下，baseline 与 Registered Boundary 均通过 elaboration、非空 Top、signed multiplier width、accumulator width 和结构检查。Registered Boundary 的寄存器位于 Feeder selection 与 Array 输入之间，未观察到从 `cycle_idx` 或 matrix input 绕过 Boundary 直接进入 PE multiplier 的组合旁路；Boundary clear 只控制 Boundary，PE accumulator clear 仍来自 pipelined Controller。

[基于结构的解释] 该 generic netlist 证明寄存器边界存在及 MAC datapath 未被复制或丢失，但不证明 post-route timing 一定改善。

## 5. 500 MHz post-route 对比

| 指标 | Baseline 500 MHz | Registered Boundary 500 MHz |
|---|---:|---:|
| Period | 2.000 ns | 2.000 ns |
| RUN cycles | 4 | 5 |
| Setup WNS | +0.219901 ns | +0.475003 ns |
| Hold WNS | +0.064352 ns | +0.052253 ns |
| Final functional cells | 2,068 | 2,084 |
| Final functional area | 3,523.17 µm² | 3,723.47 µm² |
| Timing-repair buffers | 152 | 152 |
| CTS clock buffers | 9 | 17 |
| Detailed-route vias | 13,134 | 13,081 |

[已建立事实] Registered Boundary 的 setup WNS 增加 0.255102 ns，cell count 增加 0.77%，area 增加 5.69%；hold WNS 略降但仍为正。non-overlap operation latency 从 8 ns 增至 10 ns，因此同频 operation throughput 与 useful MAC throughput 均降低 20%。

## 6. 667 MHz post-route 对比

| 指标 | Baseline 667 MHz | Registered Boundary 667 MHz |
|---|---:|---:|
| Period | 1.500 ns | 1.500 ns |
| RUN cycles | 4 | 5 |
| ns/operation | 6.000 | 7.500 |
| Operations/s | 166.667 Mops/s | 133.333 Mops/s |
| Useful MAC/s | 1.333 GMAC/s | 1.067 GMAC/s |
| Setup WNS | +0.024937 ns | +0.031136 ns |
| Hold WNS | — | +0.063782 ns |
| Final functional cells | 2,372 | 2,102 |
| Final functional area | 3,896.63 µm² | 3,742.09 µm² |
| Area / throughput | 23.380 µm²/(Mop/s) | 28.066 µm²/(Mop/s) |
| Timing-repair buffers | 456 | 171 |
| CTS clock buffers | 9 | 17 |
| Detailed-route vias | 13,861 | 13,194 |

[已建立事实] Registered Boundary 667 MHz 的 global overflow、detailed-route DRC、KLayout DRC、antenna violations 和 unconstrained endpoints 均为 0；frontend equivalence 为 860/860 proven。Kepler stage LEC 仍因既有 CPU `SIGILL` 以 `LEC_CHECK=0` 禁用，post-route equivalence 未证明。

[基于结构的解释] 在相同 667 MHz target 下，Registered Boundary 的 final cells 减少 11.38%、area 减少 3.97%、timing-repair buffers 减少 62.5%，说明切断长组合路径降低了高频物理收敛成本；但额外 RUN cycle 使同频吞吐率降低 20%，area/throughput 反而约恶化 20%。

## 7. 关键路径迁移

[已建立事实] Baseline 500 MHz 的关键路径是 `cycle_idx → Feeder/control → boundary PE accumulator`。Registered Boundary 500 MHz 的关键路径迁移为 `Boundary register → multiplier/accumulator`，Feeder selection 不再与 PE multiplier 串联。

[已建立事实] Registered Boundary 667 MHz 的关键路径为 `boundary_b[11]/Q → PE(0,1) multiplier/accumulator`：data delay 为 1.3773 ns，其中 cell delay 为 1.3755 ns（99.869%），net delay 为 0.0018 ns（0.131%）。

[基于结构的解释] 关键路径迁移与 Boundary 切分组合路径的设计目的相符；cell delay 仍占绝对主导，因此结果不表示互连已成为主要瓶颈。

## 8. 吞吐率与面积效率

| 跨频点比较 | Baseline 500 MHz | Registered Boundary 667 MHz |
|---|---:|---:|
| Operations/s | 125.000 Mops/s | 133.333 Mops/s |
| Final functional area | 3,523.17 µm² | 3,742.09 µm² |
| Area / throughput | 28.185 µm²/(Mop/s) | 28.066 µm²/(Mop/s) |

[已建立事实] Registered Boundary 667 MHz 相对 baseline 500 MHz 的 operation throughput 增加 6.67%，area 增加 6.21%，area efficiency 基本相同，Registered Boundary 约好 0.42%。但是 baseline 自身也能在 667 MHz 完成实现，因此这个跨频点比较不能证明 Registered Boundary 全面占优。

## 9. 架构裁决

1. [已建立事实] Baseline 继续作为默认架构；Registered Boundary 保留为独立实验变体，不替换冻结 baseline。
2. [已建立事实] 实验确认了 Feeder critical combinational path 可被切断，并在 667 MHz 降低 physical convergence cost：cells -11.38%、area -3.97%、timing-repair buffers -62.5%。
3. [已建立事实] 代价是增加 1 个 RUN cycle；non-overlap latency 增加 25%，同频 operations/s 和 useful MAC/s 降低 20%，同频 667 MHz area-throughput efficiency 约恶化 20%。
4. [基于结构的解释] Registered Boundary 不是 throughput winner，而是 timing closure 与 implementation cost 的另一种权衡。
5. [尚未验证的假设] 若要以 5-cycle operation 匹配 baseline 667 MHz 的 operation throughput，目标频率需约为 $5/4\times666.667\approx833.3$ MHz；本项目不据此宣称该频率可实现，也不继续追逐该点。
6. [尚未验证的假设] Overlap、double buffering 或更深 pipeline 可能改变吞吐率结论，但均超出当前协议与实验范围。

## 10. 结论边界与未完成事项

[已建立事实] 结论只适用于 Nangate45 开源参考平台、N2/K2、8-bit operand、18-bit accumulator、当前 active-operation constraints、固定 ORFS commit/image 与 non-overlap protocol。

[尚未验证的假设] 本实验不能证明或声称：

- 商业工艺 signoff 或 silicon Fmax；
- multi-corner timing signoff；
- 基于真实 activity 的可信功耗；
- post-route formal equivalence；
- Registered Boundary 对所有频率、N/K 或实现目标全面优于 baseline。

Registered Boundary frontend source-to-derived equivalence 已证明；Kepler stage LEC 与 post-route equivalence 的验证缺口仍然保留。
