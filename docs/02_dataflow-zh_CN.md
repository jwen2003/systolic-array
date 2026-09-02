# Systolic Array MVP: 数据流

[English](02_dataflow-EN.md) | [简体中文](02_dataflow-zh_CN.md)

## 1. 文档状态

- 状态：第三版，baseline 数据流与边界调度已冻结，并通过定向、随机与 MAC 次数结构回归
- 已冻结并实现：output-stationary 映射、A/B 传播方向、索引式 skew、PE 相遇时间、fill/drain 和理想利用率
- 当前输入协议：完整矩阵在 operation 期间保持稳定，feeder 由 `busy` 和 `cycle_idx` 驱动
- 当前证据边界：八种 $N/K$ 配置各完成 9 类确定性 corner 与 100 轮可复现随机 operation，共 872 个 parameterized operation；结果、完成周期、每 PE MAC 次数及逐拍操作数身份均正确

## 2. 数学映射

矩阵乘法定义为：

$$
C[i][j] = \sum_{k=0}^{K-1} A[i][k] \times B[k][j]
$$

当前设计将每个输出元素静态映射到一个 PE：

- PE$(i,j)$ 负责 $C[i][j]$；
- $A[i][k]$ 沿第 $i$ 行从左向右传播；
- $B[k][j]$ 沿第 $j$ 列从上向下传播；
- PE$(i,j)$ 在相同 $k$ 的 A、B 同拍到达时执行 MAC；
- partial sum 始终保存在 PE$(i,j)$ 内部，直到 operation 完成。

这就是 output-stationary：保持不动的是输出部分和，而不是 A 或 B。

## 3. PE 的局部数据流规则

每个 PE 不知道全局矩阵坐标，只执行以下规则：

```text
if A is valid:
    forward A to the right

if B is valid:
    forward B downward

if A and B are both valid in the same cycle:
    psum = psum + A * B
```

A/B 转发彼此独立，MAC 则要求两路同时有效。如果只有一侧有效，该数据继续传播，PE 不会将其缓存以等待另一侧。

因此：

> PE 负责局部计算和局部传输；Input Feeder 负责全局时间配对。

## 4. 为什么需要 skew

对于 PE$(i,j)$：

- A 从第 $i$ 行左边界进入后，需要向右传播 $j$ 拍；
- B 从第 $j$ 列上边界进入后，需要向下传播 $i$ 拍。

如果所有行和列都在同一拍注入第 $k$ 项，那么 A、B 的传播距离不同，非对角线 PE 会收到错误的 $k$ 配对。

当前采用的边界注入规则为：

- $A[i][k]$ 在第 $i+k$ 拍注入第 $i$ 行；
- $B[k][j]$ 在第 $j+k$ 拍注入第 $j$ 列。

传播到 PE$(i,j)$ 后：

- A 到达时间为 $(i+k)+j$；
- B 到达时间为 $(j+k)+i$。

两者均为：

$$
t(i,j,k)=i+j+k
$$

因此，相同 $k$ 的 $A[i][k]$ 与 $B[k][j]$ 会在 PE$(i,j)$ 同拍相遇。

这里的延迟不是等待前一个 PE 完成计算，而是补偿不同的空间传播距离。

## 5. Input Feeder 的索引调度

baseline feeder 不保存内部时序状态，也不使用物理延迟链。它接收完整矩阵、`enable` 和 `cycle_idx=t`，通过组合索引产生阵列边界输入。

对第 $i$ 行 A：

- 当 $i\le t<i+K$ 时，输出 `a_matrix[i][t-i]` 且 valid 为 1；
- 其他周期输出 0 且 valid 为 0。

对第 $j$ 列 B：

- 当 $j\le t<j+K$ 时，输出 `b_matrix[t-j][j]` 且 valid 为 1；
- 其他周期输出 0 且 valid 为 0。

`enable` 由 controller 的 `busy` 驱动。`busy=0` 时，即使 `cycle_idx=0`，全部边界 valid 也必须为 0，避免阵列在 operation 之外继续累加。

该实现直接对应 $i+k$ 和 $j+k$ 的注入公式，适合验证调度语义；它可能综合成较大的矩阵选择 mux，未来可与延迟寄存器链 feeder 进行 PPA 对比。

## 6. 2×2 示例

设：

```text
A = [a b]    B = [e f]
    [c d]        [g h]
```

正确结果为：

- $C[0][0]=ae+bg$；
- $C[0][1]=af+bh$；
- $C[1][0]=ce+dg$；
- $C[1][1]=cf+dh$。

### 6.1 边界注入时序

| Cycle | A 第0行 | A 第1行 | B 第0列 | B 第1列 |
|---:|---|---|---|---|
| 0 | a | 无效 | e | 无效 |
| 1 | b | c | g | f |
| 2 | 无效 | d | 无效 | h |
| 3 | 无效 | 无效 | 无效 | 无效 |

第1行 A 延迟一拍，第1列 B 也延迟一拍。valid 必须与数据使用相同的延迟。

### 6.2 PE 计算波前

| Cycle | PE00 | PE01 | PE10 | PE11 |
|---:|---|---|---|---|
| 0 | ae | 空闲 | 空闲 | 空闲 |
| 1 | bg | af | ce | 空闲 |
| 2 | 空闲 | bh | dg | cf |
| 3 | 空闲 | 空闲 | 空闲 | dh |

计算活动从左上方向右下方传播，形成波前：

- Cycle 0～1 主要是 fill；
- Cycle 2～3 主要是 drain；
- 对更大的 $K$，每个 PE 在波前到达后会连续执行更多 MAC，固定 fill/drain 开销被摊薄。

## 7. 不做 skew 时的失败模式

如果所有行、列同时注入：

| Cycle | A 第0行 | A 第1行 | B 第0列 | B 第1列 |
|---:|---|---|---|---|
| 0 | a | c | e | f |
| 1 | b | d | g | h |

最终计算为：

| PE | 实际 accumulator | 正确结果 | 判断 |
|---|---|---|---|
| PE00 | $ae+bg$ | $ae+bg$ | 正确 |
| PE01 | $ah$ | $af+bh$ | 错误 |
| PE10 | $de$ | $ce+dg$ | 错误 |
| PE11 | $cf+dh$ | $cf+dh$ | 正确 |

PE00 和 PE11 位于主对角线上，A、B 的传播距离相同，因此碰巧配对正确。PE01 和 PE10 的两条传播路径不等长，导致同拍到达的操作数属于不同 $k$。

这个例子证明：

> 结果错误不是 MAC 功能错误，而是空间传播延迟没有被边界调度补偿。

## 8. 首次与末次有效 MAC

PE$(i,j)$ 执行第 $k$ 项 MAC 的周期为：

$$
t(i,j,k)=i+j+k
$$

因此：

- 首次有效 MAC：$i+j$；
- 最后一次有效 MAC：$i+j+K-1$；
- 最早开始的是 PE$(0,0)$；
- 最晚完成的是 PE$(N-1,N-1)$。

从 Cycle 0 的第一次 MAC 到最后一次 MAC，共有：

$$
T=K+2N-2
$$

个 cycle。

这里采用“Cycle 0 可以执行第一次 MAC”的编号方式。未来 testbench 和性能计数必须沿用同一约定，避免出现 off-by-one。

在顶层操作协议中，`start` 被采样的上升沿只负责进入 RUN 并建立 `cycle_idx=0`。其后的时钟区间称为 Cycle 0，feeder 在该区间产生首批组合输出；下一个上升沿提交 Cycle 0 的 MAC。因此启动协议额外包含一个接受 `start` 的边沿，但不改变上述计算窗口定义。

## 9. 理想阵列利用率

$N \times N$ 阵列在一次 operation 中具有：

- PE 数：$N^2$；
- 总有效 MAC 数：$N^2K$；
- 统计窗口：$K+2N-2$ 拍；
- 总 PE-cycle：$N^2(K+2N-2)$。

因此阵列窗口利用率为：

$$
U=\frac{N^2K}{N^2(K+2N-2)}=\frac{K}{K+2N-2}
$$

当 $N=2$、$K=2$ 时：

$$
U=\frac{2}{2+4-2}=50\%
$$

该利用率只反映 fill/drain 和空间调度，不包含以下现实因素：

- feeder 无法持续供数；
- memory bandwidth 不足；
- backpressure 或 stall；
- 多轮 operation 之间的空拍；
- 时钟频率随阵列规模变化。

## 10. 数据流不变量

RTL 和验证必须保持：

1. A 每经过一个 PE 恰好向右延迟一拍；
2. B 每经过一个 PE 恰好向下延迟一拍；
3. valid 与对应数据经历完全相同的延迟；
4. A/B 单边有效时仍可独立传播；
5. 只有双 valid 才更新 accumulator；
6. PE$(i,j)$ 只累加属于 $C[i][j]$ 的乘积；
7. 每轮 operation 中，每个 PE 恰好执行 $K$ 次 MAC；
8. 无 stall baseline 中，第 $k$ 项 MAC 出现在第 $i+j+k$ 拍。

当前验证状态：

- 第 1～5 项已由 PE、裸阵列和 feeder 定向测试逐拍覆盖；
- 第 6 项已由端到端参考模型在八种参数配置、872 个 corner/random operation 中覆盖；
- 第 7 项已由层次化 MAC count monitor 直接检查；
- 第 8 项及第 6 项中的“具体 $k$ 身份”已由逐拍 pairing monitor 直接检查；合法 $k$ 窗口内同时检查双 valid 和 A/B 数值，窗口外检查不得出现双 valid。

## 11. 已冻结边界与后续变体

当前 baseline 已确定：

- feeder 直接读取由顶层提供的完整稳定矩阵；
- skew 使用 `cycle_idx` 组合索引；
- $K$ 独立于 $N$；
- 连续 operation 不允许波前重叠；
- 当前无 stall 和 backpressure。

上述 baseline 已在 $N=1$、$N=2$、$N=4$ 以及 $K=1$、$K=2$、$K=3$、$K=4$ 的选定组合中完成回归。该证据覆盖当前参数矩阵，但不等价于对任意 $N/K$ 组合的形式证明。

尚未进入 baseline 的后续问题包括：

- 延迟寄存器链 feeder 是否能降低选择 mux 代价；
- 多轮 operation 是否可以流水重叠；
- 引入 stall 后应冻结全阵列，还是为局部链路增加握手与缓冲；
- memory bandwidth 如何改变本文的理想利用率。
