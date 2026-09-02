# Systolic Array MVP: 验证计划

[English](04_verification_plan-EN.md) | [简体中文](04_verification_plan-zh_CN.md)

## 1. 文档状态

- 状态：最终 MVP 验证状态；baseline 定向回归、完整参数矩阵、MAC 次数、pairing 与协议 monitor 已通过
- 验证对象：baseline PE、裸阵列、Input Feeder、Controller、系统 Top，以及独立 Registered Boundary 实验变体
- 当前工具：Verilator 5.032 `--binary --timing --Wall`
- baseline 证据边界：5 组定向 testbench；8 种参数配置各执行 9 类确定性 corner 与 100 个可复现 random operation，共 $8\times109=872$ 个 parameterized operation；0 error、0 warning

本文档定义 Systolic Array MVP 需要证明什么、使用什么证据证明，以及功能验证、formal 与物理流程各自建立了哪些结论。测试数量本身不是目标；每项测试必须对应明确的设计契约或失败模式。

## 2. 验证目标

验证工作建立以下证据链：

> 局部 PE 语义正确 → 阵列互连正确 → 边界 skew 正确 → 控制周期正确 → 端到端矩阵结果正确 → 参数扩展仍满足契约

具体目标为：

1. signed 乘法、符号扩展和累加结果正确；
2. A/B data 与 valid 沿阵列分别同步传播；
3. 只有双 valid 才更新 accumulator；
4. `acc_clear` 清除旧 operation，并允许 baseline 在同拍接收首个 MAC；
5. feeder 为每个 PE 产生正确的 $k$ 配对；
6. `start`、`busy`、`cycle_idx`、`done` 满足对应 Top 的周期协议；
7. 每个 PE 每轮恰好执行 $K$ 次 MAC；
8. 顶层结果满足矩阵乘法参考模型；
9. $N$、$K$ 参数变化后，功能和完成周期仍正确；
10. lint 不存在未裁决的 width、signedness、latch 或接口 warning。

## 3. 参考模型

对输入矩阵：

- $A$ 的形状为 $N\times K$；
- $B$ 的形状为 $K\times N$；
- $C$ 的形状为 $N\times N$。

参考结果为：

$$
C[i][j]=\sum_{k=0}^{K-1}A[i][k]\times B[k][j]
$$

testbench 参考模型将 A/B 按 signed `DATA_W` 解释，使用足够宽的临时类型完成乘法与求和，并在比较 DUT 前明确转换到 `ACC_W`。当前 baseline 随机回归限制 $K\le4$，使 `DATA_W=8`、`ACC_W=18` 时全输入范围不会溢出。在定义 saturation、wraparound 或硬件溢出报告语义之前，不使用会超出 accumulator 数值范围的随机配置。

## 4. 周期模型

### 4.1 Baseline

baseline RUN 窗口总周期数为：

$$
TOTAL\_RUN\_CYCLES=K+2N-2
$$

最后一个计算周期编号为：

$$
LAST\_CYCLE=K+2N-3
$$

IDLE 上升沿接受 `start` 后进入 RUN，`busy=1`、`cycle_idx=0`。Cycle 0 的 feeder 数据与 `acc_clear=1` 在下一上升沿提交，允许 clear 与首个 MAC 同拍。提交 `LAST_CYCLE` 的上升沿后，`done=1`、`busy=0`，最终结果同步可见；`done` 下一拍清零。

### 4.2 Registered Boundary

Registered Boundary 在 Feeder 与 Array 之间增加一级寄存器，因此：

$$
TOTAL\_RUN\_CYCLES=K+2N-1
$$

$$
LAST\_CYCLE=K+2N-2
$$

RUN 0 只将 feeder 数据装入 Boundary，所有 PE 双 valid 必须为 0；$\mathrm{PE}(i,j)$ 对第 $k$ 项执行 MAC 的周期为 $i+j+k+1$。最后一次 MAC 与 `done` 在 `LAST_CYCLE` 提交边沿后同步可见。每个 PE 仍执行 $K$ 次 MAC，最终矩阵结果不变。

## 5. 定向验证层次

### 5.1 Baseline 五组定向 testbench

| Testbench | 主要覆盖 |
|---|---|
| `tb/tb_systolic_pe.sv` | 同步 reset、signed 极值、clear/MAC/hold 优先级、A/B data/valid 独立一拍转发 |
| `tb/tb_systolic_array.sv` | $2\times2$ 手工 skew、逐拍波前、signed 矩阵、drain、结果保持、广播 `acc_clear` |
| `tb/tb_input_feeder.sv` | $N=2,K=2$ 与 $N=2,K=3$ 注入、越界 invalid、invalid data 清零、`enable=0` |
| `tb/tb_systolic_controller.sv` | start 接受、Cycle 0 clear、计数、RUN 中忽略 start、done 单拍、二次 operation、$N=1,K=1$ |
| `tb/tb_systolic_array_top.sv` | 两轮 signed 矩阵乘法、operation 间 clear、精确 RUN 周期、done 与结果同步 |

### 5.2 Registered Boundary 定向 testbench

仓库包含并已提交以下独立 testbench：

- `tb/tb_systolic_boundary_pipe.sv`：同步 reset、clear 优先级、A/B valid 独立、一拍延迟、连续无气泡捕获；
- `tb/tb_systolic_pipelined_controller.sv`：扩展 RUN 窗口、`cycle_idx`、`acc_clear`、RUN 中忽略 start、done 单拍及第二参数配置；
- `tb/tb_systolic_array_pipelined_top.sv`：N2/K2 RUN 0 零 MAC、RUN 1 首个 MAC、最后一次 MAC 与 done 同边沿、二次 operation 无残留。

这些测试验证实验变体的新增时序，不替代 baseline 五组定向验证。

## 6. Baseline 参数化端到端验证

对应文件：`tb/tb_systolic_array_random.sv`；统一入口：`scripts/run_regression.sh`。

当前 runner 明确执行以下八种配置：

| $N$ | $K$ | 主要边界 |
|---:|---:|---|
| 1 | 1 | 最小 counter、单 PE、clear/MAC 同拍 |
| 2 | 1 | 每 PE 仅一次 MAC |
| 1 | 2 | 单 PE、多项内积 |
| 2 | 2 | 主要功能与物理 baseline |
| 4 | 2 | 较大阵列、较短内积 |
| 2 | 3 | $K\ne N$ 与 counter 调度 |
| 2 | 4 | 较长内积与 counter width |
| 4 | 4 | 16 个结果与完整 drain |

每种配置先执行 9 类确定性 corner，再执行 100 个固定 seed random operation，共 109 个 operation。总计：

$$
8\times(9+100)=872
$$

九类 corner 为：全 0、单位矩阵、单个非零元素、全 1、正负交替、127、-128、127/-128 混合、同时包含零行和零列。

每个 operation 均执行：

1. IDLE 期间生成并建立输入矩阵；
2. 独立 signed 参考模型计算完整结果；
3. 发出单拍 `start`，并在整个 `busy` 窗口保持矩阵稳定；
4. 检查完成周期、`busy/done/cycle_idx` 转换与 `acc_clear`；
5. 在 `done` 时比较全部 $N^2$ 个结果；
6. 检查每个 PE 恰好执行 $K$ 次 MAC；
7. 逐拍检查 A/B/$k$ pairing；
8. 检查 reset、idle feeder valid、done 后结果保持及连续 operation 无残留。

固定 seed 为 `32'h5a17_c3e9`。失败信息包含配置、seed、operation 编号、矩阵、周期、PE 坐标及 expected/actual，保证可复现性。

## 7. Registered Boundary 参数化验证范围

对应文件：`tb/tb_systolic_array_pipelined_random.sv`。该 TB 保留 baseline 的 signed 参考模型、9 类 corner、默认 100 个 random operation、最终结果比较、每 PE MAC count、pairing 与协议 monitor，并作以下时序调整：

- RUN 0 禁止任何 PE MAC；
- pairing 使用 $k=t-1-i-j$；
- `acc_clear` 仍严格为 `busy && cycle_idx == 0`；
- `busy` 与 matrix-stability 窗口增加一拍；
- monitor 在 `LAST_CYCLE` 提交边沿采样最后一次 MAC，不因随后可见的 `done` 提前结束；
- `done` 与最终 `psum` 同步可见，idle Boundary valid 为 0。

tracked 仓库证明该独立参数化 TB 及上述 monitor 已提交，但当前统一 runner 没有列出 Registered Boundary 的八配置执行清单，README 与 docs/09 也未给出可独立追溯的完整 operation 总数。因此本文不把 baseline 的 872 个 operation 计入 Registered Boundary，也不猜测其八配置总数。已建立的精确执行事实以三组独立定向 testbench、已提交的参数化 TB，以及 docs/09 记录的结构与物理门禁为边界。

## 8. 协议与结构 monitor

baseline 参数化 TB 已通过以下检查：

1. `busy=0` 时 feeder 所有 valid 为 0；
2. `acc_clear` 当且仅当 `busy && cycle_idx == 0`；
3. `done` 只保持一拍，且与 `busy` 互斥；
4. RUN 中除完成转换外，`cycle_idx` 每拍递增；
5. reset 采样后 Controller 与全部 PE 状态归零；
6. A/B 在整个 `busy` 窗口保持稳定；
7. $\mathrm{PE}(i,j)$ 在 baseline 周期 $i+j+k$ 使用 `A[i][k]` 与 `B[k][j]`；
8. 合法 $k$ 窗口外不得出现 PE 双 valid；
9. 每个 PE 每轮 MAC 次数等于 $K$，全阵列总有效 MAC 数为 $N^2K$；
10. `done` 与最后一次 accumulator 更新在同一提交边沿后可见。

这些层次化 monitor 只观察设计状态，不为验证方便改变可综合数据通路。

## 9. Formal 与物理流程状态

以下状态必须分层解释：

1. Baseline source-to-derived frontend equivalence：843/843 个 `$equiv` proven；
2. Registered Boundary source-to-derived frontend equivalence：860/860 个 `$equiv` proven；
3. Post-synthesis equivalence：`inconclusive_tool_scalability`。未发现反例，但求解未完成，不能称为 failed 或 proven；
4. Kepler stage LEC：`disabled_due_to_cpu_sigill`。Kepler Formal 二进制因 CPU 指令兼容问题在启动时发生 `SIGILL`，官方 Nangate45/GCD 也可复现；这不是设计等价失败；
5. Post-route equivalence：not proven；
6. Physical implementation checks：STA、routing、extraction、GDS、detailed-route DRC 与 KLayout DRC 的通过不等同于 formal equivalence。

不得把上述状态压缩为“formal 全部通过”。

## 10. 覆盖范围与非目标

当前验证覆盖无 stall、无 backpressure、operation 期间完整矩阵稳定、signed integer、output-stationary、固定 $N\times N$ 阵列、参数化 $K$ 与并行结果读取。

当前不覆盖：

- RUN 中修改输入矩阵；
- ready/valid backpressure、streaming 或 stall；
- SRAM、DMA、AXI、memory bandwidth 或 runtime；
- saturation、rounding、浮点或硬件 overflow flag；
- 多轮波前重叠；
- clock-domain crossing；
- multi-corner timing signoff；
- post-route formal equivalence。

这些非目标不能由当前测试结果推断为已支持。

## 11. 失败分类

| 失败表现 | 优先检查 |
|---|---|
| PE 定向测试失败 | signedness、位宽、clear/hold 优先级 |
| 裸阵列逐拍失败 | 邻接互连、valid 延迟、边界方向 |
| Feeder 失败 | `t-i/t-j` 索引、enable、越界条件 |
| Controller 失败 | start 接受、counter、`LAST_CYCLE`、done |
| 子模块通过但 Top 失败 | 模块间周期契约、busy/enable、clear 对齐 |
| 仅 random/corner 失败 | 参考模型宽度、二次 operation 残留、失败输入 |
| 仅较大参数失败 | generate、数组维度、`CYCLE_W`、完成周期 |
| Registered RUN 0 出现 MAC | Boundary clear/valid 与 Controller 对齐 |
| 最后 MAC 未被记录 | monitor 在 done 边沿提前结束 |

## 12. 退出标准与当前结论

baseline 的功能退出标准已经满足：5 组定向 testbench、8 种参数配置、872 个 parameterized operation、最终结果、完成周期、每 PE MAC count、A/B/$k$ pairing 与协议 monitor 全部通过；Verilator 5.032 `--Wall` 为 0 error、0 warning。该 baseline 已进入并完成 generic synthesis 与 Nangate45 N2/K2 物理实现。

Registered Boundary 作为独立实验变体保留，不替换默认 baseline。它的新增 Boundary、Controller 与 Top 定向验证、参数化 random TB、frontend equivalence、generic 结构和 500/667 MHz 物理对照均已建立相应证据；本文不在缺少 tracked 执行清单时宣称额外的八配置 operation 总数。

当前验证仍不构成任意参数组合的形式证明、post-route equivalence、商业工艺 signoff、可信功耗结论或完整系统验证。
