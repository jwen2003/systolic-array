# Systolic Array MVP: 最小软件契约

[English](10_minimal_software_contract-EN.md) | [简体中文](10_minimal_software_contract-zh_CN.md)

## 1. 文档定位与目的

[当前 RTL 已建立的事实] Systolic Array MVP 已定义矩阵乘加的数据流、定点算术、`start`/`busy`/`done` 时序和参数化硬件 shape，但当前 Top 使用并行 unpacked-array 端口，不是 CPU 可直接访问的设备接口。

[本文冻结的软件抽象] 本文从合理的 Matmul 调用反向定义 shape、dtype、layout、overflow、command 和 status 语义，建立一个 workload 到一个硬件 operation 的映射。这样可以避免未来软件只是机械适配现有 RTL 端口，并提前暴露硬件接口中的隐含假设。

[未来问题] 本文不是已经实现的 C ABI、CPU driver、runtime 或 memory-mapped interface，也不把 MVP 扩张为完整 AI accelerator 软件栈。

## 2. 逻辑 API 与配置对象

逻辑调用定义为：

```text
status = systolic_matmul_execute(config, A, B, C)
```

它描述行为而非现有函数符号或 ABI。抽象配置为：

```text
config:
    hardware_n
    hardware_k
    logical_m
    logical_n
    logical_k
    input_dtype
    accumulator_dtype
    layout
    overflow_policy
```

[当前 RTL 已建立的事实] 阵列为方形 `hardware_n × hardware_n`；`hardware_n`、`hardware_k`、`DATA_W` 和 `ACC_W` 均为 elaboration-time 参数，软件不能在运行时改变它们。

[本文冻结的软件抽象] `logical_m`、`logical_n` 和 `logical_k` 只描述映射到当前硬件实例的实际 workload。为避免输出维度的 `logical_n` 与硬件阵列维度 `hardware_n` 混淆，本文后续公式用 $P=\mathrm{logical\_n}$ 表示输出列数。当前 MVP 不是任意 shape 动态硬件。

## 3. 数据与 shape 契约

逻辑矩阵为：

$$
A\in\mathbb{Z}^{M\times K_{logical}},\qquad
B\in\mathbb{Z}^{K_{logical}\times P},\qquad
C\in\mathbb{Z}^{M\times P}.
$$

必须满足：

$$
1\le M\le hardware\_n,\qquad
1\le P\le hardware\_n,\qquad
1\le K_{logical}\le hardware\_k.
$$

[本文冻结的软件抽象] 软件构造以下完整硬件视图：

- Hardware A：`hardware_n × hardware_k`；
- Hardware B：`hardware_k × hardware_n`；
- Hardware C：`hardware_n × hardware_n`；
- A/B 未使用位置补零；
- 只向调用者返回 C 的前 `M × P` 有效区域；
- 超过硬件 shape 的 workload 返回 `UNSUPPORTED_SHAPE`；
- 大矩阵 tiling 不属于当前契约。

[当前 RTL 已建立的事实] Controller 仍执行完整 `hardware_k` 次 MAC。零填充在数学上有效，因为补入项的乘积为零，不改变有效区域的结果。

## 4. Layout 与 dtype

[本文冻结的软件抽象]

- A、B、C 的 host-side buffer 均按 row-major 解释；
- A/B 为 signed two's-complement `int8`；
- hardware accumulator/result 为 signed two's-complement `int18`；
- 软件侧 C 使用 `int32` 容器接收符号扩展后的 `int18` 结果。

[当前 RTL 已建立的事实] RTL unpacked-array 端口本身不构成 memory layout 或总线协议。当前硬件没有 scale、zero point、rounding、requantization 或 saturation，因此该接口不是量化神经网络 API。

[未来问题] AXI/DMA 或其他搬运实现必须保持上述逻辑顺序，或者显式执行 layout 转换。

## 5. 算术与 overflow 语义

[当前 RTL 已建立的事实] 乘积是完整 signed $8\times8$ 结果，累加器宽度固定为 18 bit。超出 signed 18-bit 范围 $[-131072,131071]$ 时执行固定宽度 two's-complement wrap；硬件没有 overflow flag、saturation 或异常状态。

[本文冻结的软件抽象] 支持两种策略：

1. `RAW_WRAP`：精确暴露当前 RTL 行为，允许 18-bit two's-complement wrap。
2. `REJECT_OVERFLOW_RISK`：未来软件 wrapper 在发起 operation 前执行保守检查；若不能保证每个结果落入 18-bit 范围，则返回 `ACCUMULATOR_OVERFLOW_RISK`。这不是当前 RTL 已有功能。

保守界限为：

```text
sum_abs_bound(i,j) =
    sum over k of abs(A[i][k]) * abs(B[k][j])
```

若任一 `sum_abs_bound(i,j) > 131071`，wrapper 拒绝该 operation。该对称界限保证正负方向均安全，但可能拒绝依靠符号抵消后实际仍合法的输入。未来 runtime 可以采用更精确策略，但不能改变 `RAW_WRAP` 的硬件语义。

## 6. Command 与 status 契约

抽象状态为：

```text
IDLE
RUN
DONE_EVENT
```

[本文冻结的软件抽象] 一个 operation 的顺序为：

1. 软件确认 `busy == 0`；
2. 建立并保持完整 A/B 硬件视图；
3. 发出单拍 `start`；
4. `start` 在 idle 采样边沿被接受；
5. `busy == 1` 期间 A/B 保持稳定；
6. 软件等待单拍 `done`；
7. `done` 可见时最终 `psum` 已经可见；
8. 软件读取 C；
9. 结果保持到下一次被接受的 operation 清除 accumulator。

[当前 RTL 已建立的事实] RUN 期间额外 `start` 会被忽略。合理的软件 wrapper 不得把被忽略的请求报告为成功，而应在发起前发现 `busy` 并返回 `BUSY`。当前没有 queue、ready/valid command channel 或 operation ID；operation 不能重叠；`done` 是事件而非持续状态。

[未来问题] 若软件可能错过 `done` 脉冲，真实寄存器接口需要 sticky completion status；当前 MVP 没有该接口。

## 7. 周期契约

Baseline 默认实现：

```text
TOTAL_RUN_CYCLES = hardware_k + 2*hardware_n - 2
```

Registered Boundary 实验变体：

```text
TOTAL_RUN_CYCLES = hardware_k + 2*hardware_n - 1
```

[当前 RTL 已建立的事实] RUN 周期从 `start` 被接受后进入 RUN 开始计算。Baseline 是默认软件契约对应实现；Registered Boundary 是额外增加一拍 latency 的实验 variant。

[本文冻结的软件抽象] 上述公式只表示 device-side RUN 窗口，不包含 host buffer 准备、数据复制、轮询、中断或结果搬运。因此当前 MVP 的性能结果不能等同于完整系统吞吐。

## 8. 软件抽象状态码

这些状态码不是当前 RTL 已提供的 error pins 或 status registers：

| 状态码 | 触发条件 |
|---|---|
| `OK` | Operation 被接受并完成，C 有效区域已可返回 |
| `BUSY` | 硬件正在 RUN，wrapper 不发出新的 `start` |
| `INVALID_SHAPE` | shape 元数据缺失、为零、为负或矩阵维度彼此不相容 |
| `UNSUPPORTED_SHAPE` | 合法逻辑 shape 超过当前实例的 `hardware_n` 或 `hardware_k` |
| `INVALID_DTYPE` | 输入或 accumulator dtype 不符合 `int8`/`int18` 契约 |
| `INVALID_LAYOUT` | Host buffer 不是约定的 row-major，且未提供显式转换 |
| `ACCUMULATOR_OVERFLOW_RISK` | `REJECT_OVERFLOW_RISK` 检查不能保证 18-bit 累加安全 |
| `NOT_READY` | Device 尚未初始化、仍处于 reset，或结果尚未完成 |
| `UNSUPPORTED_OPERATION` | 请求了 Matmul 之外的操作或当前契约未支持的模式 |

## 9. 映射示例

### 9.1 精确 N2/K2

A 为 $2\times2$、B 为 $2\times2$，无需 padding，完整返回 $2\times2$ 的 C。Baseline 的 RUN cycles 为 $2+2\times2-2=4$。

### 9.2 N2/K2 执行 $1\times2$ 乘 $2\times1$

设置 `logical_m=1`、`logical_n=1`、`logical_k=2`。软件将 A 的第二行和 B 的第二列补零，形成完整 $2\times2$ 硬件输入，只返回 `C[0][0]`。

### 9.3 拒绝超出硬件 shape

N2/K2 收到 `logical_m=3` 或 `logical_k=3` 时返回 `UNSUPPORTED_SHAPE`。当前契约不自动 tiling。

### 9.4 Overflow 策略

若 N2/K2 的有效 dot product 使用两项 `127 × 127`，则保守 bound 为 $2\times16129=32258$，两种策略都可执行。若未来较大 `hardware_k` 的 bound 超过 131071，`RAW_WRAP` 仍按 18-bit wrap 执行，而 `REJECT_OVERFLOW_RISK` 在发出 `start` 前返回错误；后者是软件策略，不是硬件保护。

## 10. 当前接口暴露的 codesign 结论

1. 当前 array-port Top 适合 RTL 验证和物理实现，不是软件可直接访问的设备接口。
2. 软件契约要求先检查 `busy`，但硬件 command 接口没有 `ready` 或显式拒绝响应。
3. `done` 是单拍事件，真实寄存器接口可能需要 sticky done。
4. 结果保持便于软件读取，但下一次 operation 会覆盖旧结果。
5. 编译时 N/K 限制意味着任意 shape 需要 padding、多个硬件实例或未来 tiling runtime。
6. 18-bit accumulator 没有 overflow 状态，软件安全策略必须显式面对该约束。
7. 这些结论是未来设计输入，不要求修改冻结 baseline RTL。

## 11. 非目标与下一阶段

当前文档不定义 AXI、DMA、NoC、memory-mapped register map、interrupt controller、cache coherency、ready/valid streaming、backpressure、double buffering、overlapping operations、arbitrary-size tiling、compiler integration、完整 runtime、端到端搬运性能或 power model。

[未来问题]

- S3：流式边界和 backpressure；
- S4：最小 runtime 与 tiling/scheduling；
- S5：端到端性能与数据搬运分析。

## 12. MVP 冻结裁决

[本文冻结的软件抽象] 当前 MVP 的软件可见数学语义、shape/dtype/layout、overflow、command/status 及周期契约已经冻结。本文不宣称软件栈已经实现，也不宣称硬件具备 CPU 可访问接口；该契约足以作为未来 runtime 或接口设计的上游依据。

Systolic Array MVP 在本文提交后可以进入发布审计。
