# Systolic Array MVP: 设计意图

## 1. 文档状态

- 状态：第三版，baseline RTL、定向回归与第一阶段随机/结构回归已完成
- 当前覆盖范围：MVP 目标、系统边界、核心设计原则、外部操作协议与验收标准
- 当前验证证据：五组定向 testbench 通过；六种参数配置完成 600 轮可复现随机回归；每个 PE 每轮恰好执行 $K$ 次 MAC 的结构 monitor 通过
- 尚未完成：逐拍 A/B/$k$ 配对 monitor、系统化协议 assertions、定向 corner cases、综合与 PPA

本文档说明本项目为什么存在、MVP 要证明什么，以及哪些功能被明确排除。它不用于描述逐拍数据位置或具体 RTL 结构；这些内容分别记录在《02 数据流》和《03 微架构》中。

## 2. 项目目标

本项目实现一个可综合的 output-stationary Systolic Array，并用逐拍推导、自动验证、性能计数和综合结果回答以下问题：

1. 矩阵乘法如何映射为空间分布的 PE 计算；
2. A、B 数据为什么需要 skew，以及相同 $k$ 的操作数如何在目标 PE 同拍相遇；
3. fill、有效计算和 drain 如何决定总延迟与硬件利用率；
4. 阵列规模、工作负载规模和实际吞吐之间是什么关系；
5. PE 数量增加后，性能为什么不一定线性增加；
6. RTL 结构如何映射为乘法器、加法器、寄存器、互连和关键路径。

项目重点不是“得到正确的矩阵乘结果”，而是建立以下完整证据链：

> 数学映射 → 时空调度 → 微架构 → RTL → 验证 → 性能与 PPA

## 3. MVP 范围

### 3.1 已冻结范围

- 数据流：output-stationary；
- 阵列形态：参数化 $N \times N$ 二维 PE 阵列；
- 初始目标规模：先验证 $2 \times 2$，再扩展到 $4 \times 4$；
- 运算：signed integer matrix multiplication；
- 默认输入宽度：`DATA_W = 8`；
- 默认累加器宽度：`ACC_W = 18`，足以容纳四个 8-bit signed 极值乘积的累加；
- A 数据从左向右传播；
- B 数据从上向下传播；
- 每个 PE 的 accumulator 固定保存一个输出元素 $C[i][j]$；
- 只有 A、B 同拍有效时，PE 才执行一次 MAC；
- A、B 及其 valid 独立传播，不在 PE 内等待配对；
- baseline PE 的乘法与加法不插入中间 pipeline register；
- reset 清除 PE 的转发状态和 accumulator；
- `acc_clear` 开始一轮新的局部累加，并允许与该轮第一个有效 MAC 同拍发生。
- 输入矩阵形状为 $A:N\times K$、$B:K\times N$，输出为 $C:N\times N$；
- $N$ 与 $K$ 分别参数化，不要求 $K=N$；
- Input Feeder 根据 `cycle_idx` 组合索引完整输入矩阵，并在边界生成 skew；
- Controller 采用 `busy` 表示 `IDLE/RUN` 两种状态，以固定周期计数判断完成；
- `start` 在空闲上升沿被采样，随后进入 Cycle 0 准备区间，下一上升沿提交首次 MAC；
- `done` 在最后一次 MAC 提交后产生单周期脉冲；
- baseline 顶层并行暴露完整 `result[N][N]`。

### 3.2 当前明确不做

- AXI、DMA、NoC 或复杂片上总线；
- SRAM scratchpad、cache 或多级 memory hierarchy；
- ready/valid backpressure；
- PE 内部操作数等待、重放或动态配对；
- 浮点运算；
- 定点舍入、饱和及复杂量化；
- 稀疏计算、零跳过或结构化剪枝；
- 多租户、抢占或运行时调度；
- 完整神经网络算子栈；
- 为追求代码量而增加与核心问题无关的模块。

这些内容不是永久排除项，而是不属于当前 MVP 的证明目标。

## 4. 核心设计原则

### 4.1 局部规则必须简单

每个 PE 只执行两个局部动作：

1. 将有效的 A 向右、B 向下转发；
2. 当 A、B 同拍有效时，将乘积累加到本地 accumulator。

PE 不理解矩阵坐标、$k$ 的编号或整轮 operation 的进度。正确配对由阵列边界的时空调度保证。

### 4.2 调度复杂度放在阵列边界

不同 PE 到边界的传播距离不同。Input Feeder 必须通过 skew，使 $A[i][k]$ 和 $B[k][j]$ 在 PE$(i,j)$ 同拍到达，而不是要求 PE 暂存单边操作数并等待另一侧。

### 4.3 正确性包括周期正确性

以下情况都属于设计错误：

- 数值结果错误；
- A、B 的 $k$ 配对错误；
- valid 与数据错位；
- accumulator 在无有效 MAC 时改变；
- 结果正确但完成周期与定义不一致；
- 性能计数与实际 PE 活动不一致。

### 4.4 参数化不能掩盖未定义语义

参数化首先用于比较 $N=1$、$N=2$ 和 $N=4$ 的结构与性能，不追求任意参数组合都自动合理。每个参数必须有明确约束，例如 `ACC_W` 不得小于单个完整乘积的宽度。

## 5. 正确性定义

对于矩阵 $A$、$B$，输出应满足：

$$
C[i][j] = \sum_{k=0}^{K-1} A[i][k] \times B[k][j]
$$

在 output-stationary 映射中：

- PE$(i,j)$ 唯一负责 $C[i][j]$；
- 每轮 operation 中，PE$(i,j)$ 应恰好执行 $K$ 次有效 MAC；
- 第 $k$ 次 MAC 必须使用 $A[i][k]$ 和 $B[k][j]$；
- operation 完成后，PE accumulator 中保存最终 $C[i][j]$。

## 6. 性能问题

项目必须区分三种量：

- 理论峰值：所有 PE 每拍均执行一次 MAC；
- 调度利用率：有效 MAC 数占可用 PE-cycle 的比例；
- 实际实现性能：受到时钟频率、接口供数能力和控制开销影响的结果。

对于单次 $N \times N$ 输出、内积长度为 $K$ 的理想 skew 调度：

- 有效 MAC 数为 $N^2K$；
- 从第一次 MAC 到最后一次 MAC 的窗口为 $K + 2N - 2$ 拍；
- 阵列窗口利用率为 $K/(K+2N-2)$。

该公式只描述当前无 stall、供数充分的 baseline，不代表未来加入 memory system 后的实际利用率。

## 7. 验收标准

MVP 至少需要满足：

- PE 定向测试全部通过；
- signedness、位宽、clear、hold 和 forwarding 行为均被验证；
- $2 \times 2$ 阵列的逐拍波形与手算时空表一致；
- 随机矩阵结果与参考模型一致；
- 每个 PE 每轮恰好执行 $K$ 次 MAC；
- 完成周期与解析模型一致；
- $N=1$、$N=2$、$N=4$ 至少完成参数化回归；
- lint 无关键 latch、width 和 signedness 警告；
- 综合报告能够解释乘法器、寄存器、面积与关键路径的来源；
- 能够解释阵列扩大时 fill/drain 和供数约束为何限制加速。

截至当前 checkpoint，除综合/PPA 相关项目外，上述功能 baseline 的主要验收项已经通过：五组定向 testbench 持续通过；$N=1,K=1$、$N=2,K=1$、$N=2,K=2$、$N=2,K=3$、$N=4,K=1$、$N=4,K=4$ 六种配置各完成 100 轮固定 seed 随机回归；完成周期、全部结果和每 PE MAC 次数均符合模型；Verilator `--Wall` 无未裁决 warning。

这些结果仍不能替代逐拍操作数身份验证。当前 monitor 证明“每个 PE 算了 $K$ 次”，下一阶段还需直接证明每次 MAC 在周期 $i+j+k$ 使用 `A[i][k]` 与 `B[k][j]`。

## 8. 当前接口与操作约束

baseline 采用完整矩阵并行输入，而不是逐拍流式装载：

- 调用方必须在 `start` 被采样前准备好 A、B；
- A、B 从 `start` 接受到 `done` 期间必须保持稳定；
- `busy=1` 时新的 `start` 被忽略；
- feeder 仅在 `busy=1` 时输出有效边界数据；
- 两轮 operation 之间暂不支持无气泡衔接或波前重叠；
- `done=1` 时完整结果已经保存在并行 `result[N][N]` 端口。

该接口有意回避矩阵装载、SRAM 和带宽问题，用于先隔离并证明时空调度本身。

## 9. 当前里程碑与后续问题

当前已经完成：

1. 五个可综合 RTL 模块及其顶层集成；
2. PE、裸阵列、Input Feeder、Controller、系统顶层五组定向验证；
3. 参数化随机端到端 testbench 与 signed 参考模型；
4. 六种 $N/K$ 配置、合计 600 轮可复现随机 operation；
5. 每个 PE 每轮恰好执行 $K$ 次 MAC 的层次化 monitor；
6. 为 $N=1$ 将阵列互连重构为包含输入/输出边界位置的 pipe，并完成裸阵列、$N=2,K=2$、$N=4,K=4$ 回归。

进入首次综合与 PPA 前仍需完成：

1. 逐拍 A/B/$k$ 配对 monitor，直接检查 PE$(i,j)$ 在周期 $i+j+k$ 使用正确操作数；
2. `busy`、`done`、`acc_clear`、`cycle_idx`、reset 与输入稳定假设的系统化协议 monitor/assertions；
3. 全 0、单位矩阵、单个非零、全 1、正负交替、127、-128 及零行/零列等定向 corner cases；
4. 更大 $K$ 下 `ACC_W` 的推导和溢出策略；
5. 首次综合后分析乘法器、寄存器、面积、频率、关键路径与利用率；
6. 后续再评估矩阵装载存储、结果读取接口及索引式/延迟链式 feeder 的 PPA 差异。
