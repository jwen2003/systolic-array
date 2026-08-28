# Systolic Array MVP: 验证计划

## 1. 文档状态

- 状态：第一版，baseline 定向回归已通过，随机与结构验证待实现
- 验证对象：PE、裸阵列、Input Feeder、Controller 与系统顶层
- 当前工具：Verilator `--binary --timing --Wall`
- 当前证据边界：已证明既定参数和定向场景下的功能与周期行为；尚未证明更广泛输入空间、全部参数组合和内部结构不变量

本文档定义 Systolic Array MVP 需要证明什么、使用什么证据证明，以及何时可以进入综合和 PPA。测试数量本身不是目标；每项测试必须对应明确的设计契约或失败模式。

## 2. 验证目标

验证工作需要建立以下证据链：

> 局部 PE 语义正确 → 阵列互连正确 → 边界 skew 正确 → 控制周期正确 → 端到端矩阵结果正确 → 参数扩展仍满足契约

具体目标为：

1. signed 乘法、符号扩展和累加结果正确；
2. A/B data 与 valid 沿阵列分别同步传播；
3. 只有双 valid 才更新 accumulator；
4. `acc_clear` 能清除旧 operation，并允许同拍接收首个 MAC；
5. feeder 为每个 PE 产生正确的 $k$ 配对；
6. `start`、`busy`、`cycle_idx`、`done` 满足已冻结周期协议；
7. 每个 PE 每轮恰好执行 $K$ 次 MAC；
8. 顶层结果满足矩阵乘法参考模型；
9. $N$、$K$ 参数变化后，功能和完成周期仍正确；
10. lint 不存在未裁决的 width、signedness、latch 或接口警告。

## 3. 参考模型

对输入矩阵：

- $A$ 的形状为 $N\times K$；
- $B$ 的形状为 $K\times N$；
- $C$ 的形状为 $N\times N$。

参考结果为：

$$
C[i][j]=\sum_{k=0}^{K-1}A[i][k]\times B[k][j]
$$

testbench 参考模型必须：

- 将 A/B 按 signed `DATA_W` 解释；
- 使用足够宽的临时类型完成乘法与求和；
- 在比较 DUT 前明确转换到 `ACC_W`；
- 对 baseline 随机回归限制 $K\le4$，使 `DATA_W=8`、`ACC_W=18` 时全输入范围不会溢出。

在定义 saturation、wraparound 或溢出报告语义之前，不使用会超出 accumulator 数值范围的随机配置。

## 4. 周期模型

计算窗口总周期数为：

$$
TOTAL\_CYCLES=K+2N-2
$$

最后一个计算周期编号为：

$$
LAST\_CYCLE=K+2N-3
$$

周期语义为：

1. IDLE 上升沿采样到 `start=1`；
2. 该边沿后进入 RUN，`busy=1`、`cycle_idx=0`；
3. 随后的区间为 Cycle 0，feeder 准备首批边界数据，`acc_clear=1`；
4. 下一上升沿提交 Cycle 0 的 clear 与首批 MAC；
5. 提交 `LAST_CYCLE` 的上升沿后，`done=1`、`busy=0`，结果有效；
6. `done` 下一拍自动清零。

端到端 testbench 必须从 `start` 接受边沿之后开始统计 RUN 提交边沿，并精确观察 `TOTAL_CYCLES` 个周期。

## 5. 验证层次

### 5.1 PE 定向验证

对应文件：`tb/tb_systolic_pe.sv`

当前已通过 17 项检查，覆盖：

- 同步复位和复位优先级；
- 零乘积；
- 正×正、正×负、负×负；
- `-128 × -128` 极值；
- 连续无气泡 MAC；
- A-only、B-only、双 invalid；
- accumulator hold；
- clear 且无 MAC；
- clear 与首个 MAC 同拍；
- A/B data 与 valid 的一拍转发。

### 5.2 裸阵列定向验证

对应文件：`tb/tb_systolic_array.sv`

当前定向场景已通过，覆盖：

- $2\times2$ 手工 skew；
- 四个 accumulator 的逐拍波前；
- signed 正负混合矩阵；
- Cycle 3 drain；
- 完成后保持；
- 广播 `acc_clear`。

### 5.3 Feeder 定向验证

对应文件：`tb/tb_input_feeder.sv`

当前已通过 11 项检查，覆盖：

- $N=2,K=2$ 的全部注入和 post-injection 周期；
- $N=2,K=3$，证明 $K$ 独立于 $N$；
- 越界周期输出 invalid；
- invalid lane data 清零；
- `enable=0` 时禁止所有边界注入。

### 5.4 Controller 定向验证

对应文件：`tb/tb_systolic_controller.sv`

当前已通过 15 项检查，覆盖：

- 同步复位和复位优先级；
- IDLE 保持；
- `start` 接受与 Cycle 0 clear；
- 计数递增；
- RUN 中忽略 `start`；
- 末周期完成；
- `done` 单拍；
- 二次 operation；
- RUN 中复位；
- $N=1,K=1$ 单周期边界。

### 5.5 顶层定向验证

对应文件：`tb/tb_systolic_array_top.sv`

当前已通过 6 项结果检查，覆盖：

- 两轮 signed $2\times2$ 矩阵乘法；
- operation 间 accumulator 清除；
- 完成后结果保持；
- `done` 单拍；
- 精确 RUN 周期数；
- $2\times3$ 与 $3\times2$ 的端到端矩阵乘法。

## 6. 随机端到端验证

计划新增：`tb/tb_systolic_array_random.sv`

### 6.1 第一阶段配置

| 配置 | 主要目的 | 建议轮数 |
|---|---|---:|
| $N=2,K=2$ | 基础随机 signed 数据与多轮 clear | 100 |
| $N=2,K=3$ | 非方形内积长度与索引调度 | 100 |
| $N=4,K=4$ | 参数扩展、长波前和 16 个结果端口 | 100 |

每一轮执行：

1. 在 IDLE 期间生成新的随机矩阵；
2. testbench 计算完整参考矩阵；
3. 产生单拍 `start`；
4. 在 `busy=1` 期间保持 A/B 不变；
5. 统计完成周期；
6. 在 `done` 有效时比较全部 $N^2$ 个结果；
7. 随机插入 0～3 个 idle cycle；
8. 启动下一轮，验证旧 accumulator 不会污染新结果。

### 6.2 随机可复现性

每次回归必须打印：

- 配置 $N,K,DATA\_W,ACC\_W$；
- 初始 seed；
- 失败 operation 编号；
- 失败矩阵 A/B；
- 期望和实际结果；
- 观察到的完成周期。

相同 seed 必须能够重现相同矩阵序列。不能只报告“随机测试失败”而不保留失败输入。

### 6.3 定向 corner case 插入

纯均匀随机不保证及时命中关键边界，因此随机回归前后仍需插入：

- 全 0；
- 单位矩阵；
- 单个非零元素；
- 全 1；
- 正负交替；
- 127；
- -128；
- 127 与 -128 混合；
- 行或列完全为 0。

## 7. 协议性质

后续 assertion 或 testbench monitor 至少证明：

1. `busy=0` 时 feeder 所有 valid 为 0；
2. `acc_clear` 当且仅当 `busy=1 && cycle_idx=0`；
3. `done` 不连续保持超过一拍；
4. `done=1` 时 `busy=0`；
5. RUN 中除末周期外，`cycle_idx` 每拍增加 1；
6. `busy=1` 时 `start` 不改变当前 operation 的进度；
7. reset 采样后 `busy`、`done`、`cycle_idx` 和所有 PE 状态归零；
8. A/B 在 `busy=1` 期间保持稳定属于环境假设，testbench 必须遵守并可加入检查。

## 8. 数据通路与结构不变量

需要进一步证明：

1. 无 `acc_clear` 且无双 valid 时，`psum_out` 保持；
2. A/B 输出 data 与 valid 等于上一拍对应输入；
3. PE$(i,j)$ 在周期 $i+j+k$ 使用 $A[i][k]$ 与 $B[k][j]$；
4. 每个 PE 每轮恰好执行 $K$ 次 MAC；
5. 每轮总有效 MAC 数为 $N^2K$；
6. 最后一项发生在 PE$(N-1,N-1)$ 的 `LAST_CYCLE`；
7. `done` 与最后一次 accumulator 更新在同一提交边沿后可见。

其中第 3～6 项不能只通过最终矩阵结果间接推断。后续可以采用 bind assertion、层次化 monitor 或仅仿真的 MAC 活动计数器；不得为了验证方便而改变可综合数据通路语义。

## 9. 参数化回归矩阵

baseline 至少覆盖：

| $N$ | $K$ | 目的 |
|---:|---:|---|
| 1 | 1 | 最短 counter 和单 PE 边界 |
| 2 | 1 | 只有一次 MAC 的传播与 drain |
| 2 | 2 | 基础配置 |
| 2 | 3 | $K\ne N$ |
| 4 | 1 | 大阵列、低利用率 |
| 4 | 4 | 目标扩展配置 |

参数回归必须同时检查：

- 编译和 lint；
- 完成周期；
- 全部结果；
- reset 和连续 operation；
- `CYCLE_W` 没有截断；
- `ACC_W` 对当前输入范围足够。

## 10. 覆盖范围与非目标

当前验证覆盖：

- 无 stall、无 backpressure；
- 完整矩阵在 operation 期间稳定；
- signed integer；
- output-stationary；
- 固定 `N×N` 阵列与参数化 $K$；
- 直接并行读取 result。

当前不覆盖：

- 输入矩阵在 RUN 中变化；
- ready/valid backpressure；
- SRAM、DMA、AXI 或 memory bandwidth；
- saturation、rounding 或浮点；
- 多轮波前重叠；
- clock-domain crossing；
- timing back-annotation；
- physical design effects。

这些非目标不能通过 baseline 测试结果推断为已支持。

## 11. 失败分类

回归失败时按以下顺序定位：

| 失败表现 | 优先检查 |
|---|---|
| PE 定向测试失败 | signedness、位宽、clear/hold 优先级 |
| 裸阵列逐拍失败 | 邻接互连、valid 延迟、边界方向 |
| Feeder 失败 | `t-i/t-j` 索引、enable、越界条件 |
| Controller 失败 | start 接受、counter、LAST_CYCLE、done |
| 子模块通过但顶层失败 | 模块间周期契约、busy/enable、clear 对齐 |
| 仅随机测试失败 | corner case、参考模型宽度、二次 operation 残留 |
| 仅 $N=4$ 失败 | generate、数组维度、CYCLE_W、完成周期 |

## 12. 进入综合前的退出标准

进入首次综合与 PPA 前，至少需要：

- 五组现有定向 testbench 持续通过；
- 随机端到端验证覆盖 $N=2,K=2$、$N=2,K=3$、$N=4,K=4$；
- 每种随机配置至少 100 轮，固定 seed 可复现；
- 参数化边界 $N=1,K=1$ 通过；
- 完成周期全部符合解析模型；
- 全部结果与参考模型一致；
- 每个 PE 每轮 MAC 次数检查通过；
- `--Wall` 无未裁决 warning；
- 当前限制和未覆盖功能已经记录。

满足这些条件后，综合结果才建立在足够稳定的功能 baseline 上。PPA 阶段若改变 pipeline、feeder 或接口结构，必须重新运行全部相关回归。

