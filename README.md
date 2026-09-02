# Systolic Array MVP

一个面向 RTL/Digital Design、Hardware Performance 与 Validation 的参数化矩阵乘加项目。项目从逐拍 dataflow 推导出可综合 RTL，建立定向、随机、结构与协议验证，并完成 generic synthesis scaling 实验以及一套固定环境下的 Nangate45 RTL-to-GDS baseline。

## 项目目标与范围

本项目计算有符号整数矩阵乘法：

$$
C[i][j] = \sum_{k=0}^{K-1} A[i][k] \times B[k][j]
$$

当前 baseline 的参数含义为：

| 参数 | 定义 |
|---|---|
| `N` | 方形 PE array 的行数和列数，也是输出矩阵 $C$ 的维度 |
| `K` | 每个输出元素的 inner-product length；独立于 `N` |
| `DATA_W` | A/B signed operand width |
| `ACC_W` | 每个 PE 中 output-stationary accumulator/result width |

RTL baseline 包含完整矩阵并行输入与并行结果输出，但不包含 SRAM、DMA、矩阵装载协议、ready/valid backpressure 或重叠 operation。调用方需要在启动前准备输入矩阵，并在 operation 期间保持其稳定。

## Dataflow 与周期模型

### Output-stationary

每个 PE$(i,j)$ 保存一个局部 `psum_out`，依次累加 $K$ 个乘积；A 沿行向右传播，B 沿列向下传播，输出部分和不离开 PE。PE 在第 $i+j+k$ 个计算周期使用 $A[i][k]$ 与 $B[k][j]$。

### A/B skew

不同 PE 到输入边界的距离不同。组合式 Input Feeder 使用 `cycle_idx` 生成边界 skew：

- 第 $i$ 行在周期 $t$ 注入 `A[i][t-i]`；
- 第 $j$ 列在周期 $t$ 注入 `B[t-j][j]`；
- 超出合法 $k$ 窗口的 lane 输出 invalid。

这样，相同 $k$ 的 A/B operand 会在目标 PE 同拍相遇，无需在 PE 内缓存单边 operand 等待配对。

### `start` / `busy` / `done`

1. Controller 在 IDLE 上升沿采样到 `start=1`，随后进入 RUN，`busy=1`、`cycle_idx=0`。
2. 该边沿后的组合区间是 Cycle 0；下一上升沿提交第一批 MAC，同时完成 accumulator clear 与首项累加。
3. RUN 中的新 `start` 被忽略。
4. 计算窗口为 $K+2N-2$ 个周期，最后周期编号为 $K+2N-3$。
5. 最后一次 MAC 提交后，`busy=0`、`done=1`，全部 $N^2$ 个结果有效。
6. `done` 是单周期 pulse，下一拍自动清零。

`rst_n` 是 synchronous active-low reset。400 MHz active-operation STA 假设 reset 在 operation 开始前完成释放，并在运行期间保持稳定；该 STA 不验证外部 reset assertion/deassertion 接口时序。

## RTL模块

| 模块 | 职责 |
|---|---|
| `systolic_pe` | signed multiply、sign extension、accumulate，以及 A/B/valid 单拍转发 |
| `systolic_array` | 实例化 $N\times N$ PE，连接水平A pipe、垂直B pipe和并行 `psum` result |
| `input_feeder` | 根据 `cycle_idx` 对完整输入矩阵做组合索引，产生边界A/B skew与valid |
| `systolic_controller` | 接受 `start`，生成 `busy`、`cycle_idx`、`acc_clear`与单拍 `done` |
| `systolic_array_top` | 连接 Controller、Feeder和Array，定义完整operation协议 |

## 仓库结构

```text
rtl/       五个冻结的SystemVerilog baseline模块
tb/        五组定向TB和参数化端到端random/corner TB
synth/     Yosys generic synthesis Tcl与受控配置矩阵
physical/  Nangate45约束、frontend、equivalence与final audit Tcl
scripts/   regression、synthesis、structure check和physical audit入口
docs/      设计意图、dataflow、微架构、验证、综合缩放与物理实现证据
build/     自动生成产物，不提交Git
```

详细设计与证据链见 [docs/01_design_intent.md](docs/01_design_intent.md) 至 [docs/07_physical_implementation_plan.md](docs/07_physical_implementation_plan.md)。

## 验证方法与结果

验证从局部语义逐层推进到系统协议：PE → Array → Feeder → Controller → Top，并使用同一 signed reference model 检查最终矩阵结果。

- 5组定向 testbench：PE、Array、Feeder、Controller、Top；
- 8种参数配置：`N/K=1/1, 2/1, 1/2, 2/2, 4/2, 2/3, 2/4, 4/4`；
- 每种配置包含9个确定性 corner cases和100个固定seed random operations；
- 每种109个corner/random operations，共872个参数化端到端 operation；
- Verilator `--Wall`、结果值与精确完成周期全部通过；
- structural monitor、每PE MAC count monitor、逐拍 A/B/k pairing monitor、controller/feeder/reset/input-stability protocol monitor 全部通过；
- read_slang frontend equivalence：843/843个`$equiv` cell proven。

逐拍 pairing monitor 直接检查 PE$(i,j)$ 在周期 $i+j+k$ 接收 $A[i][k]$ 和 $B[k][j]$；MAC count monitor 要求每个 PE 每次 operation 恰好提交 $K$ 次 MAC。

## Generic synthesis 与 N/K scaling

Yosys generic flow 使用 read_slang elaboration，保存 pre-tech 与 techmap JSON/netlist，并自动检查 signed multiplier width/sign extension、$N^2$ 个 multiplier、$N^2$ 个 accumulator adder、register width及非空结构。

受控实验保持 `DATA_W=8`、`ACC_W=18`：

- 固定 `K=2`，`N=1,2,4`：multiplier、accumulator与result marker按 $N^2$ 增长；generic cell总量呈近似 $N^2$ scaling。固定controller/feeder开销使小规模点不严格服从比例。
- 固定 `N=2`，`K=1,2,3,4`：四个PE数据通路保持不变；主要变化来自controller/feeder选择逻辑与cycle counter。`K=3/4`跨越counter width边界，register bits由110增至111。
- Generic cells是工具版本相关的逻辑规模代理，不是目标工艺standard cell、面积、Fmax或功耗。

完整统计和口径见 [docs/06_synthesis_scaling_analysis.md](docs/06_synthesis_scaling_analysis.md)。

## Nangate45 N2/K2 RTL-to-GDS baseline

物理baseline固定为 `N=2`、`K=2`、`DATA_W=8`、`ACC_W=18`，ORFS commit `6101364b2d7909dd797e1e3e7f80695401cfa4e4`，镜像 `openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0`。

以下结果使用复用Butterfly的400 MHz active-operation评测口径：2.500 ns clock period、0.050 ns uncertainty；reset在operation前释放并在运行期间稳定。

| 指标 | 结果 |
|---|---:|
| Final setup WNS | **+0.72001 ns** |
| Final hold WNS | **+0.0650233 ns** |
| Final functional standard-cell area | **3,522.64 µm²** |
| Functional standard cells | **2,068** |
| Global-route overflow | **0** |
| Detailed-route DRC | **0** |
| KLayout DRC | **0** |
| Final GDS | 已生成 |

Global-route和detailed-route wirelength来自不同阶段与统计定义，项目分别保存原始结果，但不直接比较或计算改善比例。

## 关键路径分析

Post-route extracted critical path 为：

```text
cycle_idx → feeder/control → boundary PE accumulator
```

- Data delay：`1.69648 ns`；
- Cell delay占比：约`99.63%`；
- Net delay占比：约`0.37%`。

这条路径从Controller counter进入Feeder/control selection，最终到达边界PE的`psum_out[17]` accumulator register。对当前小型N2/K2 core，关键路径主要由组合算术cell delay主导，而非长互连或clock path；该观察不能直接外推到更大的N/K配置。

## Registered Boundary 实验结论

独立的 Registered Boundary 变体在 Feeder 与 Array 之间增加一级 A/B data/valid 寄存器，保持 4 个 signed multiplier 与 4 个 accumulator datapath 不变。500 MHz post-route setup WNS 从 baseline 的 `+0.219901 ns` 提升到 `+0.475003 ns`；在 667 MHz，同目标频率下 final cells 减少 11.38%、final area 减少 3.97%、timing-repair buffers 减少 62.5%。代价是 RUN window 从 4 拍增加到 5 拍，non-overlap 协议下同频 operation throughput 降低 20%。

因此 baseline 继续作为默认架构，Registered Boundary 作为 timing closure 与实现成本权衡的实验变体保留。完整结构、post-route 与吞吐率分析见 [docs/09_registered_boundary_ppa_analysis.md](docs/09_registered_boundary_ppa_analysis.md)。

## 最小软件契约

项目已冻结逻辑软件契约：workload 映射到固定硬件 shape，A/B 使用 signed `int8`、accumulator/result 使用 signed `int18`、host buffer 为 row-major；较小 shape 通过补零执行，command 遵循 `busy`/单拍 `start`/单拍 `done`，overflow 可选择暴露硬件 wrap 或由未来 wrapper 保守拒绝。该契约不表示 runtime、AXI 或 DMA 已实现，详见 [docs/10_minimal_software_contract.md](docs/10_minimal_software_contract.md)。

## 一键复现

以下命令从仓库根目录运行。Linux/WSL环境需要相应的Verilator、固定OSS CAD Suite、Docker及匹配的ORFS checkout。

```bash
# 5组定向TB + 8种参数配置，共872个端到端operation
scripts/run_regression.sh

# 8个受控N/K配置的generic synthesis与自动结构检查
scripts/run_synth.sh

# 对已有N2/K2 final ODB/SDC/SPEF重新执行非破坏性post-route STA audit
ORFS_ROOT=/path/to/OpenROAD-flow-scripts scripts/run_openroad_final_audit.sh

# 校验已有完整物理结果与机器指标
python3 scripts/check_openroad_results.py \
  build/openroad/lec_disabled/systolic_n2_k2_full
```

`run_openroad_final_audit.sh`不会重新执行完整RTL-to-GDS，但要求匹配的固定ORFS commit、固定Docker image，以及已有且非空的final ODB/SDC/SPEF。

## 结论边界与未完成事项

- Nangate45/FreePDK45是开源参考平台；结果不是商业工艺signoff。
- 当前没有基于真实activity、multi-corner library与silicon correlation的可信功耗结果，不宣称完整PPA。
- 尚未完成multi-corner/multi-mode signoff、OCV/AOCV/POCV或foundry-qualified extraction。
- Baseline RTL到read_slang derived frontend equivalence已证明。
- Post-synthesis equivalence状态为`inconclusive_tool_scalability`：未发现反例，但求解未完成，不能称为通过。
- Kepler stage LEC因主机CPU上可复现的`SIGILL`而以正式配置`LEC_CHECK=0`禁用；CTS、STA、routing、extraction、GDS与DRC没有被跳过。
- Post-route equivalence未证明。
- 尚未进行N/K physical scaling、clock sweep或activity-based power analysis；不得从单一N2/K2 baseline外推更大阵列的频率、面积、拥塞或功耗。

本仓库的可审计技术细节、工具版本、warning分类及统计定义均保留在 `docs/` 和可重复脚本中；README仅汇总已经建立的结论。
