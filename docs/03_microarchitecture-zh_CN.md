# Systolic Array MVP: 微架构

## 1. 文档状态

- 状态：第三版，baseline 微架构已冻结、实现并通过完整参数回归矩阵
- 对应 RTL：`rtl/systolic_pe.sv`、`rtl/systolic_array.sv`、`rtl/input_feeder.sv`、`rtl/systolic_controller.sv`、`rtl/systolic_array_top.sv`
- 当前目的：记录 baseline 的状态语义、空间拓扑、时间调度、组合路径、控制协议和参数约束

## 2. 基线系统分解

当前计划中的系统模块为：

| 模块 | 责任 | 状态 |
|---|---|---|
| `systolic_pe` | signed MAC、A/B 转发、valid 转发、本地 accumulator | 已冻结并实现 |
| `input_feeder` | 矩阵边界供数与 skew | 已冻结并实现 |
| `systolic_array` | PE 生成、邻接互连和结果暴露 | 已冻结并实现 |
| `systolic_controller` | operation 启动、clear、周期计数和完成判断 | 已冻结并实现 |
| `systolic_array_top` | 集成 feeder、array 和 controller | 已冻结并实现 |

完整矩阵由顶层输入提供，并在一次 operation 的 `busy` 区间保持稳定。baseline 不包含矩阵装载协议、SRAM、DMA 或 backpressure。

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

当前 PE 没有 `ready`、`stall` 或 `psum_valid_out`。完成时刻由系统级 controller 根据固定计算窗口判断。

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

$$PROD\_W=2\times DATA\_W$$

默认 `DATA_W = 8`，因此 `PROD_W = 16`。

8-bit signed 输入范围为 $[-128,127]$。最大正乘积为：

$$(-128)\times(-128)=16384$$

signed 15-bit 最大只能表示 16383，因此完整乘积必须使用 16-bit signed 表示。

### 7.2 累加器宽度

默认 MVP 最多累加四个乘积。最大正和为：

$$4\times16384=65536$$

signed 17-bit 的正数上限为 65535，因此默认采用 `ACC_W = 18`。

该结论只保证 $K\le4$ 时的极值累加。若未来允许更大的 $K$，必须重新推导 `ACC_W`，不能仅依赖默认值。

### 7.3 显式符号扩展

16-bit `product` 在进入 18-bit accumulator 加法前，需要复制符号位扩展到 `ACC_W`。正数高位补 0，负数高位补 1，数值保持不变。

当前 RTL 的参数约束为：

$$ACC\_W \ge 2\times DATA\_W$$

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

当前所有具有寄存状态的 baseline 模块统一采用同步低有效复位；组合式 feeder 不保存复位状态。

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

## 12. PE 验证状态与后续 assertion

PE 定向 testbench 已通过 17 项检查，覆盖：

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

后续关键 assertion 仍应固化：

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

阵列使用四组包含两侧边界位置的二维 pipe array：

```systemverilog
logic signed [DATA_W-1:0] a_pipe       [N-1:0][N:0];
logic                     a_valid_pipe [N-1:0][N:0];
logic signed [DATA_W-1:0] b_pipe       [N:0][N-1:0];
logic                     b_valid_pipe [N:0][N-1:0];
```

对 A 通路，`a_pipe[i][0]` 接收 `a_left[i]`，PE$(i,j)$ 从 `a_pipe[i][j]` 读取并写入 `a_pipe[i][j+1]`。对 B 通路，`b_pipe[0][j]` 接收 `b_top[j]`，PE$(i,j)$ 从 `b_pipe[i][j]` 读取并写入 `b_pipe[i+1][j]`。valid 使用完全相同的索引规则。

这种表示在 $N=1$ 时仍保留完整的“输入边界 → PE → 输出边界”通路，不会产生只为邻居服务、但在单 PE 配置中完全未使用的 link array。最右侧 A 和最下侧 B 的末端位置当前不暴露为模块端口，也不参与结果计算。矩阵结果直接由 `psum[i][j]` 暴露。

### 13.5 全局控制信号

所有 PE 共享 `clk`、`rst_n` 和 `acc_clear`。当前 `acc_clear` 直接广播，不在阵列内部增加延迟。controller 已保证该广播与 Cycle 0 边界输入遵循已冻结的 clear/MAC 同拍语义。

## 14. Feeder、Controller 与系统顶层

baseline feeder 是组合索引调度器，不保存矩阵。周期 $t$ 时，第 $i$ 行在 $i\le t<i+K$ 时注入 `A[i][t-i]`；第 $j$ 列在 $j\le t<j+K$ 时注入 `B[t-j][j]`。`enable=0` 时所有边界 valid 为 0，invalid lane 的 data 固定为 0。

controller 在 IDLE 上升沿采样到 `start=1` 后进入 RUN，边沿后的 `cycle_idx=0`。Cycle 0 同时广播 `acc_clear=1` 并允许首批 MAC。总计算窗口为：

$$
TOTAL\_CYCLES=K+2N-2
$$

提交 `LAST_CYCLE=K+2N-3` 的上升沿后，`done=1`、`busy=0`，全部结果有效。`done` 为单拍脉冲；RUN 中的 `start` 被忽略。

系统顶层将 `busy` 作为 feeder 的 `enable`，将 controller 的 `acc_clear` 广播到裸阵列，并直接暴露全部 `result[i][j]`。当前仍未支持连续波前重叠、矩阵写入协议、结果索引读取或 ready/valid backpressure；这些属于 baseline 之外的扩展问题。

## 15. 当前实现与验证 checkpoint

当前五个 RTL 模块均已在 Verilator `--Wall` 下完成编译和定向回归。参数化随机顶层回归覆盖六种配置：$N=1,K=1$、$N=2,K=1$、$N=2,K=2$、$N=2,K=3$、$N=4,K=1$、$N=4,K=4$，每种 100 轮。

层次化 monitor 直接观察每个 PE 的 `a_valid_pe_in && b_valid_pe_in`，并在 operation 完成后检查每个 PE 的 MAC 次数等于 $K$。该 monitor 不修改可综合数据通路。

逐拍 pairing monitor 已对全局 Cycle $t$ 计算 $k=t-i-j$，并在 $0\le k<K$ 时检查 PE$(i,j)$ 的输入为 `A[i][k]` 与 `B[k][j]`；无合法 $k$ 时检查不得出现双 valid。该 monitor 已在六种配置、600 轮 operation 中通过，且未修改可综合数据通路。

参数化端到端 TB 现已加入系统协议 monitor，覆盖 controller 计数与完成转换、`done` 单拍、`done`/`busy` 互斥、`acc_clear` 定义、idle feeder valid、同步 reset 后全部 PE 状态，以及 RUN 期间输入矩阵稳定性。上述检查与九类确定性 corner cases 已由统一回归脚本在六种配置中通过。
