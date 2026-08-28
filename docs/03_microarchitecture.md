# Systolic Array MVP: 微架构

## 1. 文档状态

- 状态：第二版，baseline 微架构已冻结并实现，等待首次编译与仿真
- 对应 RTL：`rtl/systolic_pe.sv`、`rtl/systolic_array.sv`、`rtl/input_feeder.sv`、`rtl/systolic_controller.sv`、`rtl/systolic_array_top.sv`
- 当前目的：记录 PE 状态语义、阵列空间拓扑、边界调度、操作控制、顶层接口和参数约束

## 2. 基线系统分解

当前计划中的系统模块为：

| 模块 | 责任 | 状态 |
|---|---|---|
| `systolic_pe` | signed MAC、A/B 转发、valid 转发、本地 accumulator | 已冻结并实现 |
| `input_feeder` | 完整矩阵组合索引、边界供数与 skew | 已冻结并实现 |
| `systolic_array` | PE 生成、邻接互连和结果暴露 | 已冻结并实现 |
| `systolic_controller` | operation 启动、clear、周期计数和完成判断 | 已冻结并实现 |
| `systolic_array_top` | 集成 controller、feeder 和 array | 已冻结并实现 |

以上“已实现”表示 RTL 已写入，不表示已经通过工具编译或仿真。

## 3. PE 责任

PE 同时承担两项彼此独立的工作：

1. 数据传输：A 向右转发，B 向下转发；
2. 本地计算：双 valid 时，将 $A \times B$ 累加到本地 partial sum。

PE 不承担：

- 矩阵坐标解释；
- $k$ 编号跟踪；
- 单边操作数等待；
- 全局完成判断；
- saturation、rounding 或输出量化。

## 4. PE 接口

```systemverilog
module systolic_pe #(
    parameter int DATA_W = 8,
    parameter int ACC_W  = 18
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     acc_clear,

    input  logic signed [DATA_W-1:0] a_in,
    input  logic                     a_valid_in,
    input  logic signed [DATA_W-1:0] b_in,
    input  logic                     b_valid_in,

    output logic signed [DATA_W-1:0] a_out,
    output logic                     a_valid_out,
    output logic signed [DATA_W-1:0] b_out,
    output logic                     b_valid_out,

    output logic signed [ACC_W-1:0]  psum_out
);
```

### 4.1 接口语义

| 信号 | 语义 |
|---|---|
| `clk` | PE 所有寄存状态的上升沿时钟 |
| `rst_n` | 同步低有效复位 |
| `acc_clear` | 开始新的本地累加；不阻止 A/B 转发 |
| `a_in` | 当前周期从左侧或行边界到达的 A 数据 |
| `a_valid_in` | `a_in` 在当前周期具有计算与传播语义 |
| `b_in` | 当前周期从上方或列边界到达的 B 数据 |
| `b_valid_in` | `b_in` 在当前周期具有计算与传播语义 |
| `a_out` | 寄存后的 A 数据，供右侧 PE 下一拍采样 |
| `a_valid_out` | 与 `a_out` 对齐的 valid |
| `b_out` | 寄存后的 B 数据，供下方 PE 下一拍采样 |
| `b_valid_out` | 与 `b_out` 对齐的 valid |
| `psum_out` | 本 PE 保存的 output-stationary accumulator |

当前 PE 没有 `ready`、`stall` 或 `psum_valid_out`。是否完成由未来的阵列 controller 判断。

## 5. PE 内部状态

PE 保存五项寄存状态：

- `a_out`；
- `a_valid_out`；
- `b_out`；
- `b_valid_out`；
- `psum_out`。

`a_in` 和 `b_in` 是模块输入，不属于本 PE 的内部状态。`product` 与 `product_ext` 是当前周期的组合结果，也不跨周期保存。

## 6. 数据通路

基线组合路径为：

```text
a_in, b_in
    │
    ▼
signed multiplier
    │ product
    ▼
sign extension
    │ product_ext
    ▼
adder with old psum
    │
    ▼
psum_out register
```

A/B 的转发路径独立于 MAC：

```text
a_in ──► a_out register ──► right PE
b_in ──► b_out register ──► lower PE
```

因此 baseline PE 的预期关键路径是 multiplier → adder → accumulator register。未来若加入 product pipeline register，会改变 PE latency、valid 对齐、阵列完成周期和 PPA，必须作为独立微架构变体重新验证。

## 7. 位宽与有符号语义

### 7.1 乘积宽度

两个 `DATA_W` 位 signed 输入的完整乘积宽度为：

$$
PROD\_W=2\times DATA\_W
$$

默认 `DATA_W = 8`，因此 `PROD_W = 16`。

8-bit signed 输入范围为 $[-128,127]$。最大正乘积为：

$$
(-128)\times(-128)=16384
$$

signed 15-bit 最大只能表示 16383，因此完整乘积必须使用 16-bit signed 表示。

### 7.2 累加器宽度

默认 MVP 最多累加四个乘积。最大正和为：

$$
4\times16384=65536
$$

signed 17-bit 的正数上限为 65535，因此默认采用 `ACC_W = 18`。

该结论只保证 $K\le4$ 时的极值累加。若未来允许更大的 $K$，必须重新推导 `ACC_W`，不能仅依赖默认值。

### 7.3 显式符号扩展

16-bit `product` 在进入 18-bit accumulator 加法前，需要复制符号位扩展到 `ACC_W`。正数高位补 0，负数高位补 1，数值保持不变。

当前 RTL 的参数约束为：

$$
ACC\_W \ge 2\times DATA\_W
$$

这只保证 accumulator 能容纳一个完整乘积，不自动保证任意 $K$ 下累加不溢出。

## 8. 每拍转发行为

复位释放后，每个上升沿均执行：

```text
a_out       <- a_in
a_valid_out <- a_valid_in
b_out       <- b_in
b_valid_out <- b_valid_in
```

转发表为：

| A valid | B valid | A 转发 | B 转发 | 执行 MAC |
|---:|---:|---:|---:|---:|
| 0 | 0 | 否 | 否 | 否 |
| 1 | 0 | 是 | 否 | 否 |
| 0 | 1 | 否 | 是 | 否 |
| 1 | 1 | 是 | 是 | 是 |

当 valid 为 0 时，对应 data register 仍可以采样端口上的数值，但该数值没有语义，后级必须通过 valid 忽略它。

## 9. 累加器更新语义

定义：

`mac_valid = a_valid_in && b_valid_in`

更新优先级为：

1. `!rst_n`；
2. `acc_clear`；
3. `mac_valid`；
4. 保持旧值。

完整状态表为：

| `rst_n` | `acc_clear` | `mac_valid` | `psum_out_next` |
|---:|---:|---:|---|
| 0 | X | X | 0 |
| 1 | 1 | 0 | 0 |
| 1 | 1 | 1 | `product_ext` |
| 1 | 0 | 1 | `psum_out + product_ext` |
| 1 | 0 | 0 | 保持 `psum_out` |

`acc_clear` 与有效 MAC 同拍时，语义是先丢弃旧 accumulator，再以本拍乘积开始新一轮累加。因此新值是 `product_ext`，不是 0，也不是旧值加乘积。

## 10. 复位语义

`rst_n` 为同步低有效复位，只在 `posedge clk` 被采样。复位时清除：

- A/B 转发数据寄存器；
- A/B valid 寄存器；
- accumulator。

复位优先级高于转发、clear 和 MAC。若 `rst_n = 0`，本拍输入不会被转发或计算。

baseline 系统中的 Controller、Array 和 PE 统一采用同步低有效复位。

## 11. 当前 RTL 对应关系

`rtl/systolic_pe.sv` 已实现：

- `PROD_W = 2 * DATA_W`；
- signed combinational multiplication；
- 显式 product sign extension；
- `DATA_W > 0` 与 `ACC_W >= PROD_W` 参数检查；
- 独立 A/B data 与 valid forwarding；
- clear 同拍接收首个 MAC；
- 无双 valid 时 accumulator 保持。

代码注释固定使用英文；设计文档和验证说明使用中文。

## 12. PE 验证要求

定向测试至少覆盖：

1. 同步复位清除全部状态；
2. 0 参与乘法；
3. 正数乘正数；
4. 正数乘负数；
5. 负数乘负数；
6. `-128 * -128` 极值；
7. 连续多个有效 MAC；
8. A-only valid；
9. B-only valid；
10. 双 invalid 时 accumulator 保持；
11. clear 且双 invalid；
12. clear 与有效 MAC 同拍；
13. valid 与 data 转发延迟恰好一拍；
14. reset 对 clear 和 MAC 的优先级。

关键 assertion 应至少证明：

- 无 clear 且无双 valid时，accumulator 不得改变；
- A/B 输出及其 valid 等于上一拍对应输入；
- clear 与双 valid 同拍后，accumulator 等于上一拍输入乘积；
- reset 采样后，所有输出寄存状态为 0。

## 13. 裸阵列微架构

`systolic_array` 是只表达空间拓扑的参数化 $N \times N$ PE fabric。它不保存完整矩阵，不生成 skew，也不解释 operation 的开始或结束。

### 13.1 边界接口

| 端口 | 语义 |
|---|---|
| `a_left[i]` | 从左边界进入第 $i$ 行的 A 数据 |
| `a_valid_left[i]` | 与 `a_left[i]` 对齐的 valid |
| `b_top[j]` | 从上边界进入第 $j$ 列的 B 数据 |
| `b_valid_top[j]` | 与 `b_top[j]` 对齐的 valid |
| `psum[i][j]` | PE$(i,j)$ 的本地 accumulator |
| `acc_clear` | 同拍广播到全部 PE 的 accumulator clear |

边界输入必须已经具有正确的 cycle-level skew。裸阵列不会纠正错误配对。

### 13.2 A 邻接规则

对 PE$(i,j)$：

- 当 $j=0$ 时，A 输入来自 `a_left[i]`；
- 当 $j>0$ 时，A 输入来自 PE$(i,j-1)$ 的 `a_out`；
- A valid 始终沿完全相同的路径传播。

### 13.3 B 邻接规则

对 PE$(i,j)$：

- 当 $i=0$ 时，B 输入来自 `b_top[j]`；
- 当 $i>0$ 时，B 输入来自 PE$(i-1,j)$ 的 `b_out`；
- B valid 始终沿完全相同的路径传播。

### 13.4 内部连线

阵列使用四组二维 link array：

```systemverilog
logic signed [DATA_W-1:0] a_link       [N-1:0][N-1:0];
logic                     a_valid_link [N-1:0][N-1:0];
logic signed [DATA_W-1:0] b_link       [N-1:0][N-1:0];
logic                     b_valid_link [N-1:0][N-1:0];
```

每个 PE 的输出统一写入自身坐标对应的 link。相邻 PE 根据行列位置选择边界信号或前一级 link，因此 PE 实例本身不需要边界特例。

最右列的 A 输出和最下行的 B 输出当前不暴露为顶层端口，也不参与结果计算。矩阵结果直接由 `psum[i][j]` 暴露。

### 13.5 全局控制信号

所有 PE 共享 `clk`、`rst_n` 和 `acc_clear`。当前 `acc_clear` 直接广播，不在阵列内部增加延迟。Controller 保证该广播与 Cycle 0 边界输入遵循已冻结的 clear/MAC 同拍语义。

## 14. Input Feeder 微架构

`input_feeder` 是无时钟、无内部状态的组合调度模块。输入矩阵形状为：

- `a_matrix[N][K]`；
- `b_matrix[K][N]`。

输出为阵列左边界和上边界的 A/B 数据及 valid。它根据 `cycle_idx=t` 实现：

```text
a_left[i] = a_matrix[i][t-i],  when i <= t < i+K
b_top[j]  = b_matrix[t-j][j],  when j <= t < j+K
```

条件不成立时，对应 data 输出 0、valid 输出 0。RTL 在执行减法索引前先检查 `t>=i/j`，避免无符号下溢。

feeder 的 `enable` 输入由 `busy` 驱动。`enable=0` 时全部输出 invalid，防止复位后或 operation 完成后因 `cycle_idx` 停留而重复注入。

## 15. Controller 微架构

Controller 使用 `busy` 表示两种逻辑状态：

| 状态 | `busy` | 行为 |
|---|---:|---|
| IDLE | 0 | 等待 `start`，feeder 禁用 |
| RUN | 1 | 驱动 `cycle_idx`，启用 feeder，并在末周期产生完成事件 |

### 15.1 启动与 Cycle 0

当 IDLE 状态在上升沿采样到 `start=1`：

- `busy` 置 1；
- `cycle_idx` 置 0；
- 随后的时钟区间成为 Cycle 0；
- feeder 组合产生 Cycle 0 边界数据；
- `acc_clear = busy && (cycle_idx == 0)`。

下一个上升沿同时提交 accumulator clear 和 Cycle 0 的首批 MAC。运行期间再次出现的 `start` 被忽略。

### 15.2 计数与完成

计算窗口总长度为：

$$
TOTAL\_CYCLES=K+2N-2
$$

最后一个计算周期编号为：

$$
LAST\_CYCLE=K+2N-3
$$

当 `cycle_idx==LAST_CYCLE` 的上升沿到达时，阵列提交右下角最后一次 MAC；同一边沿后 Controller 令 `busy=0` 并将 `done` 拉高一拍。此时完整结果可读。下一拍 `done` 自动回到 0。

## 16. 顶层微架构

`systolic_array_top` 只进行参数统一和模块连接：

```text
start
  -> systolic_controller
       -> busy, cycle_idx -> input_feeder
       -> acc_clear       -> systolic_array

a_matrix, b_matrix
  -> input_feeder
       -> a_left/b_top and valid
            -> systolic_array
                 -> result[N][N]
```

顶层不复制或缓存输入矩阵。调用方必须在 `start` 被采样前提供稳定矩阵，并保持到 `done`。结果直接映射到各 PE 的 accumulator；baseline 不提供索引读取、串行排出或结果握手。

## 17. 参数与接口约束

- $N>0$；
- $K>0$；
- `DATA_W > 0`；
- `ACC_W >= 2 * DATA_W`；
- `CYCLE_W` 必须能表示 `0 ... K+2N-3`；
- 默认 `ACC_W=18` 只保证最多四个 8-bit signed 极值乘积的累加；
- A/B 在 `busy=1` 期间不得改变。

`CYCLE_W` 的 baseline 推导为：当 `TOTAL_CYCLES<=1` 时取 1，否则取 `$clog2(TOTAL_CYCLES)`。Controller 和 feeder 使用同一宽度。

## 18. 当前验证资产与状态

已编写以下自检式 testbench：

| Testbench | 主要覆盖 |
|---|---|
| `tb_systolic_pe.sv` | signed MAC、clear、hold、独立 forwarding、复位优先级 |
| `tb_systolic_array.sv` | $2\times2$ 手工 skew、逐拍 accumulator、drain、广播 clear |
| `tb_input_feeder.sv` | $N=2,K=2$、$N=2,K=3$、invalid 清零和 disable 行为 |
| `tb_systolic_controller.sv` | 启动延迟、计数、单拍 done、busy 时忽略 start、$N=1,K=1$ |
| `tb_systolic_array_top.sv` | 两轮 $2\times2$ 运算、结果保持、$2\times3\cdot3\times2$ 端到端运算 |

当前环境尚未安装 SystemVerilog 仿真器。上述 testbench 已完成设计和人工检查，但尚未编译或执行，因此当前状态是“待验证”，不能记为“通过”。

首次回归应按 PE、Array、Feeder、Controller、Top 的顺序执行，以保持故障定位能力。回归通过前不继续扩展 $4\times4$、随机验证、利用率计数器、SRAM/AXI 或 PPA。

## 19. 后续开放问题

1. 更大 $K$ 下 `ACC_W` 的自动推导与溢出语义；
2. `N=4` 参数化回归和 PPA；
3. 每个 PE 每轮恰好执行 $K$ 次 MAC 的 assertion 或计数验证；
4. 索引式 feeder 与延迟链式 feeder 的实现代价比较；
5. 连续 operation、流式输入和 memory system 的后续接口；
6. 并行结果端口是否替换为索引读取或串行排出。
