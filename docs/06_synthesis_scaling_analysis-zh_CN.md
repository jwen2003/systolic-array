# Systolic Array MVP: 综合缩放分析

[English](06_synthesis_scaling_analysis-EN.md) | [简体中文](06_synthesis_scaling_analysis-zh_CN.md)

## 1. 分析目标

本轮在冻结 RTL 和验证语义不变的前提下，用 Yosys generic synthesis 分别观察阵列维度 $N$ 与内积长度 $K$ 对逻辑结构规模的影响。实验不包含 Liberty 映射、STA 或物理实现。

## 2. 已建立事实

- [已建立事实] 使用 OSS CAD Suite `20260830` 中的 Yosys `0.68+136`，SystemVerilog 前端为 `read_slang`。
- [已建立事实] 八组配置均完成 `hierarchy`、`proc`、`opt`、`check`、`memory`、`techmap`、`opt` 和 `stat`；Slang 均为 0 error、0 warning，四次 `check` 均为 0 problems。
- [已建立事实] 所有配置的 pre-tech 与 techmap cell set 均非空，signed multiplier 的宽度、属性和符号扩展检查均通过。
- [已建立事实] `pe_result_markers` 是层次化 `psum_out` 结果 netname 标记数，不是 flatten 后的独立 PE module cell 数。它与精确的 $N^2$ 个 multiplier、$N^2$ 个 accumulator adder 以及非空检查共同构成 PE 结构未消失的证据。
- [已建立事实] 本文的 generic cell 是 Yosys techmap primitive，不是目标工艺 standard cell。

## 3. 实验变量和控制变量

实验变量为 $N$ 和 $K$；所有配置固定 `DATA_W=8`、`ACC_W=18`，使用同一 Git 工作树、同一综合 Tcl、同一 Yosys 版本和同一优化流程。

周期计数器的 RTL 参数宽度检查公式为：

$$
W_{cycle}=\max\left(1,\left\lceil\log_2(K+2N-2)\right\rceil\right)
$$

配置由 `synth/synth_configs.tsv` 单一管理。`n2_k2` 只综合一次，同时属于 `baseline`、`n_sweep` 和 `k_sweep`。

## 4. 配置矩阵

| 配置 | $N$ | $K$ | 实验组 |
|---|---:|---:|---|
| n1_k1 | 1 | 1 | baseline |
| n2_k1 | 2 | 1 | k_sweep |
| n1_k2 | 1 | 2 | n_sweep |
| n2_k2 | 2 | 2 | baseline、n_sweep、k_sweep |
| n4_k2 | 4 | 2 | n_sweep |
| n2_k3 | 2 | 3 | k_sweep |
| n2_k4 | 2 | 4 | k_sweep |
| n4_k4 | 4 | 4 | baseline |

## 5. 固定 $K=2$ 的 $N$ sweep

| 配置 | $N$/$N^2$ | PE markers / mul / acc add | cycle bits | reg cells / bits | pre-tech | generic | generic/$N^2$ | reg bits/$N^2$ |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| n1_k2 | 1 / 1 | 1 / 1 / 1 | 1 | 4 / 21 | 30 | 834 | 834.000 | 21.000 |
| n2_k2 | 2 / 4 | 4 / 4 / 4 | 2 | 13 / 110 | 75 | 3337 | 834.250 | 27.500 |
| n4_k2 | 4 / 16 | 16 / 16 / 16 | 3 | 55 / 497 | 215 | 13155 | 822.188 | 31.063 |

- [已建立事实] 相对 `n1_k2`，$N$ 分别增长 $2\times$ 和 $4\times$，$N^2$、PE markers、multiplier 与 accumulator adder 分别精确增长 $4\times$ 和 $16\times$。
- [已建立事实] generic cells 分别增长到 $4.001\times$ 和 $15.773\times$；generic cells/$N^2$ 为 834.000、834.250、822.188，表现为近似 $N^2$ 缩放而非严格相等。
- [已建立事实] pre-tech cells 为 30、75、215，受固定控制开销、宽度变化与高层 cell 粒度影响，没有严格按 $N^2$ 增长。
- [基于结构的解释] controller/feeder 的固定开销在小阵列中占比更高；随 $N$ 增长，MAC 数据通路在 generic 统计中占主导，因此总 generic cell 更接近 $N^2$ 趋势。这不能推出所有子模块都按 $N^2$ 增长。
- [基于结构的解释] register bits/$N^2$ 从 21.000 增至 31.063。较小阵列有更高比例的边界/terminal forwarding 信号，其未被外部使用的寄存器可被优化；较大阵列保留更多内部 A/B forwarding 边，因而每 PE 平均寄存器位数上升。这是由 flattened 结构推断的解释，不是模块归属证明。

固定 $K=2$ 的 primitive 统计如下：

| 配置 | AND | MUX | NOT | OR | SDFFE | SDFF | XOR | 总 generic |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| n1_k2 | 342 | 88 | 2 | 117 | 19 | 2 | 264 | 834 |
| n2_k2 | 1373 | 310 | 12 | 474 | 74 | 36 | 1058 | 3337 |
| n4_k2 | 5483 | 1032 | 32 | 1881 | 291 | 206 | 4230 | 13155 |

## 6. 固定 $N=2$ 的 $K$ sweep

| 配置 | $K$ | cycle bits | PE markers / mul / acc add | other add | reg cells / bits | pre-tech | generic |
|---|---:|---:|---:|---:|---:|---:|---:|
| n2_k1 | 1 | 2 | 4 / 4 / 4 | 1 | 13 / 110 | 71 | 3306 |
| n2_k2 | 2 | 2 | 4 / 4 / 4 | 1 | 13 / 110 | 75 | 3337 |
| n2_k3 | 3 | 3 | 4 / 4 / 4 | 1 | 13 / 111 | 83 | 3413 |
| n2_k4 | 4 | 3 | 4 / 4 / 4 | 1 | 13 / 111 | 83 | 3413 |

- [已建立事实] PE markers、multiplier 和 accumulator adder 在全部 $K$ 配置中保持为 4，说明 $K$ 没有复制 MAC 硬件。
- [已建立事实] cycle counter 在 $K=1,2$ 时为 2 bit，在 $K=3,4$ 时为 3 bit，符合 RTL 参数公式。
- [已建立事实] register cell 数保持 13；counter 跨越位宽边界后 register bits 从 110 增至 111。
- [已建立事实] 相对 `n2_k1`，generic cell 的绝对变化依次为 0、31、107、107，对应比例为 $1.000\times$、$1.009\times$、$1.032\times$、$1.032\times$。
- [基于结构的解释] $K$ 增加扩展输入矩阵的可选元素，新增组合逻辑可能主要来自 feeder selection/MUX；counter 位宽边界也会改变 controller 比较与更新逻辑。由于 JSON 已 flatten，不能把每个新增 primitive 可靠归属到 feeder 或 controller。
- [已建立事实] `n2_k3` 与 `n2_k4` 的全部当前统计相同，形成平台而非随 $K$ 严格单调增长。
- [基于结构的解释] 两者具有相同 counter 位宽；在当前常量传播、MUX 化简和 techmap 流程下，不同参数范围收敛到相同结构。这是当前工具版本观察，不应直接视为设计错误或跨工具规律。

相对 `n2_k1` 的 primitive 增量为：

| 配置 | AND | MUX | NOT | OR | SDFFE | SDFF | XOR | generic 总增量 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| n2_k1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| n2_k2 | 0 | +32 | 0 | -1 | 0 | 0 | 0 | +31 |
| n2_k3 | +3 | +98 | +1 | +2 | +1 | 0 | +2 | +107 |
| n2_k4 | +3 | +98 | +1 | +2 | +1 | 0 | +2 | +107 |

## 7. 架构不变量

- [已建立事实] 对本轮全部配置，PE result markers、signed multiplier 和 accumulator adder 均精确为 $N^2$。
- [已建立事实] 改变 $K$ 不改变 PE、multiplier 或 accumulator adder 数量。
- [已建立事实] accumulator adder 通过其 `psum_out` A 端连接和 `ACC_W` 宽度可靠分类；其 $N^2$ 数量是本设计的架构检查。
- [已建立事实] $N=1$ 时仍保留完整 A/B pipe 宽度检查。

## 8. Yosys/工具相关观察

- [已建立事实] 每组均观察到 1 个非 accumulator adder。原三组 baseline 的 total adder=$N^2+1$ 继续作为固定 Yosys 版本结构回归；新增配置不把该总数硬编码为架构要求。
- [已建立事实] primitive 数量由 `generic_netlist.json` 自动统计，不使用硬编码期望值。
- [基于结构的解释] pre-tech cell、MUX、布尔 primitive 和总 generic cell 会受 elaboration、常量传播、优化次序及 Yosys 版本影响，因此属于工具相关结构观察。

## 9. 无法从当前实验得出的结论

- [待验证假设] generic cell 数可作为逻辑规模代理，但不能换算为目标工艺面积。
- [待验证假设] 当前没有 Liberty、SDC、gate delay、wire delay、placement、routing、CTS 或寄生参数，不能得到 Fmax、真实 critical path、功耗、布线后时序或物理关键路径。
- [待验证假设] flattened JSON 中观察到的增量不能被严格归因到某一个 RTL 子模块。

## 10. 下一阶段的 STA 和物理实现假设

待验证的内部 PE 候选路径为：registered A/B → multiplier → accumulator adder → accumulator register。

待验证的边界 PE 候选路径为：cycle_idx register → feeder selection/mux → boundary PE multiplier → accumulator adder → accumulator register。

- [基于结构的解释] 增加 $N$ 不增加单个内部 PE 的逻辑级数，但会增加阵列规模和全局负载。
- [待验证假设] 增加 $K$ 可能通过 feeder mux 复杂度影响边界 PE 路径。
- [待验证假设] `acc_clear` 的 $N^2$ 扇出可能在物理实现中影响时序与缓冲需求。
- [待验证假设] 后续判断上述路径需要目标 Liberty、时钟及 I/O SDC、目标工艺、STA 工具，以及包含 placement、CTS、routing 和寄生提取的物理实现流程。

机器可读结果位于 `build/synth/structure_summary.json` 和 `build/synth/structure_summary.tsv`；每个正式配置目录还包含独立 `structure_summary.json`、综合日志和完整 `config.txt` 追溯信息。
