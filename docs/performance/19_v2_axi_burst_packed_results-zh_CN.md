# Systolic Array V2：AXI Burst 与 Packed 实验结果

[English](19_v2_axi_burst_packed_results-EN.md) | [简体中文](19_v2_axi_burst_packed_results-zh_CN.md)

本文汇总 V2 Wrapper 截至 packed/unpacked 受控周期对照的已完成成果。V2 在冻结的 output-stationary Core 外加入矩阵输入存储、written bitmap、命令/状态以及 AXI-Lite 和受限 AXI 写突发入口。本文不替代 V1 Core 的验证、综合、物理实现与 Registered Boundary 结论。

## 1. 实验配置与计时边界

主实验固定 `N=2`、`K=17`、`DATA_W=8`、`ACC_W=18`。A、B 各有 34 个 INT8 元素，C 有 4 个结果。RTL 周期由 Verilator BFM 实测：单 outstanding、无额外请求间隔、响应端立即 READY，各模式均执行输入装载、READY 检查、START、DONE 轮询、C 读回和 ACK。

端到端周期从首次输入请求发起计至最后一个 C 响应接收；ACK 单列。Device 接受 START 到 DONE 为 20 拍，22 拍轮询窗口与计算重叠，不能重复相加。物理结果使用 Nangate45 typical（1.10 V、25 °C）、2.500 ns active-operation 约束、布线后提取寄生与 propagated clock。

当前接口是受限实现，不代表完整 AXI4、DMA、CPU 或 DDR 系统性能。

## 2. 普通 A/B/C 窗口的常量译码

旧 Device 对字节地址执行运行时行列换算并动态索引矩阵。优化后，对每个固定坐标在 elaboration 时生成完整地址常量：

- A：`A_BASE + 4*(r*K+k)`；
- B：`B_BASE + 4*(k*N+c)`；
- C：`C_BASE + 4*(r*N+c)`。

写侧用完整地址命中固定坐标和固定 bitmap 位；读侧由互斥命中项构成 one-hot OR，保持未写读零、权限、符号扩展、错误优先级以及高位地址不别名。普通 `0x1000`/`0x2000` 窗口每个 32-bit slot 仍只承载一个 INT8。

| Lite 映射综合指标 | 旧动态索引 | 常量地址译码 | 变化 |
|---|---:|---:|---:|
| Mapped cell area | 24,493.280 µm² | 10,928.078 µm² | −13,565.202 µm²（−55.38%） |
| Mapped cells | 14,823 | 5,165 | −9,658 |
| 原读瓶颈组合延迟 | 10.870170 ns | 0.606711 ns | −10.263459 ns |
| 原写瓶颈组合延迟 | 10.777412 ns | 0.720582 ns | −10.056830 ns |

优化后全局最差 setup 路径迁移回 Core 的 `cycle_idx → feeder/PE → accumulator`。这些是 Nangate45 映射后、理想时钟和 wire-load 模型下的综合后 STA 结果，不是布线后时序。详见 [`reports/v2_lite_constant_decode_sta/`](../../reports/v2_lite_constant_decode_sta/)。

## 3. Lite、单 beat Burst 与 Burst 长度扫描

长度扫描使用当前 Burst RTL 的 unpacked 窗口。最大长度是运行时 `AxLEN`，所有长度共享同一个 Burst 硬件与网表；未按长度裁剪硬件。A、B 各有 34 个元素，尾部允许短 burst。

| 最大长度（beats） | A/B 输入写事务 | W beats | A/B 纯写入（拍） | 端到端（拍） |
|---:|---:|---:|---:|---:|
| 1 | 68 | 68 | 204 | 239 |
| 2 | 34 | 68 | 136 | 171 |
| 4 | 18 | 68 | 104 | 139 |
| 8 | 10 | 68 | 88 | 123 |
| 16 | 6 | 68 | 80 | 115 |

在当前连续供数 BFM 与 Slave 下：

$$
T_{write}=N_{W\ beat}+2N_{A/B\ transactions}
$$

每笔事务的两拍固定成本对应 AW 建立与 B 响应。长度增大后事务成本被摊薄，但 W beat、计算、轮询和读回等固定成本不变，因此收益递减。Lite 与 Burst 单 beat 使用相同控制策略时均为 239 拍；这只证明当前 BFM/Slave 的受控结果，不是 AXI 标准的一般周期保证。CSV 的总写事务列还包含 START 和 ACK，表中只列 A/B 输入写事务。

原始周期与握手记录位于 [`reports/v2_lite_vs_burst/`](../../reports/v2_lite_vs_burst/)。

## 4. Lite 与 Burst 的同批物理成本

为避免把不同 frontend 或阶段的面积混算，Lite 与 Burst 使用统一 frontend、工具、corner、约束、floorplan 原则和完整检查 fresh 重跑。Burst 数据为 unpacked、`PACKED_ENABLE=0`。

| 指标 | Lite | Burst | Burst 相对 Lite |
|---|---:|---:|---:|
| Mapped area / cells | 10,655.960 µm² / 5,020 | 11,545.730 µm² / 5,553 | +8.350% / +533 |
| 最终功能标准单元面积 / cells | 11,041.972 µm² / 5,398 | 12,159.914 µm² / 6,221 | +10.124% / +823 |
| Setup WNS | +0.161062 ns | +0.172356 ns | 两者通过 |
| Hold WNS | +0.0128362 ns | +0.0123354 ns | 两者通过 |
| Global overflow | 0 | 0 | 无新增 overflow |
| Detailed-route / OpenROAD antenna / KLayout DRC | 0 / 0 / 0 | 0 / 0 / 0 | 两者 clean |

最终功能标准单元面积包含逻辑、时钟和时序修复单元，排除 filler 与 tap。Burst 相对 Lite 增加约 10.12%，该硬件成本与后文 packed0/packed1 的同 Top 对照必须分开。详见 [`reports/v2_burst_physical/`](../../reports/v2_burst_physical/)。

## 5. Packed 常量 word 地址与 byte-lane 译码

Packed aliases 位于 `0x4000`/`0x5000`。每个 32-bit word 最多承载四个连续 INT8 元素。对固定线性元素编号 $p$，elaboration 时确定 word 编号 $\lfloor p/4\rfloor$、lane $p\bmod4$、完整 word 地址、矩阵坐标和 bitmap 位。运行时仅检查地址命中、权限/错误门控及 `WSTRB[lane]`，同 word 的合法 lanes 可在同一拍独立更新。

`N=2`、`K=17` 时，A packed word 4 跨行：lane 0 是 `A[0][16]`，lane 1 是 `A[1][0]`。尾 word 若 `WSTRB` 选中非法 lane，沿用既有契约整拍拒绝，矩阵和 bitmap 均无副作用。普通 unpacked 窗口语义不变。

| `PACKED_ENABLE=1` 映射综合指标 | 旧动态索引 | 常量 word/lane 译码 | 变化 |
|---|---:|---:|---:|
| Mapped area | 47,206.488 µm² | 12,109.118 µm² | −35,097.370 µm²（−74.35%） |
| Mapped cells | 32,701 | 5,889 | −26,812 |
| Setup WNS | −11.434590 ns | 报告为 0 ns | 瓶颈移出 packed 写路径 |
| Packed 地址到矩阵代表路径 | 约 282 个组合单元 | 13 个组合单元 | 端点不完全相同 |

新 frontend 网表中 packed 路径的运行时 `$div`/`$mod` 模板为 0；代表性 packed 地址到矩阵路径 slack 为 +1.674469 ns，bitmap 路径为 +1.692279 ns。全局关键路径回到 Core，但这不表示 packed 支持没有面积成本。详见 [`reports/v2_packed_constant_decode_synth_sta/`](../../reports/v2_packed_constant_decode_synth_sta/)。

## 6. 当前 RTL 的 packed0/packed1 物理对照

两组都使用优化后的 Burst Top、相同 Core、2.500 ns 约束和相同物理检查。每组按自身面积建立 floorplan；面积百分比只在这一配对内计算。

| 指标 | `PACKED_ENABLE=0` | `PACKED_ENABLE=1`（天线修复后） | 增量 |
|---|---:|---:|---:|
| Mapped area / cells | 11,372.032 µm² / 5,542 | 12,109.118 µm² / 5,889 | +737.086 µm² / +347 |
| 最终功能标准单元面积 / cells | 12,002.412 µm² / 6,216 | 12,924.984 µm² / 6,821 | +922.572 µm²（+7.687%） / +605 |
| Timing-repair / clock buffers | 800 / 191 | 1,066 / 191 | +266 / 0 |
| Setup WNS / TNS | +0.115657 / 0 ns | +0.149201 / 0 ns | 两者通过 |
| Hold WNS / TNS | +0.004894 / 0 ns | +0.008039 / 0 ns | 两者通过 |
| Slew / cap / fanout violations | 0 / 0 / 0 | 0 / 0 / 0 | clean |
| Global overflow | 0 | 0 | clean |
| Detailed-route / OpenROAD antenna / KLayout DRC | 0 / 0 / 0 | 0 / 0 / 0 | clean |

两组全局最差路径均为 Core `cycle_idx → feeder/PE → accumulator`。packed1 布线后 `current_addr → matrix` 与 `current_addr → bitmap` 路径 slack 分别为 +1.448011 ns、+1.502475 ns。

packed1 默认 run 有一个 KLayout `METAL6_ANTENNA` item：`s_axi_araddr[4]` 到既有输入 buffer 的长金属段，ratio 331.413333、阈值 300。修复将该 buffer 固定到靠近 IO 的合法 site，不改变 RTL、逻辑连接或时序例外。fresh 修复 run 的 KLayout item、OpenROAD antenna 和 detailed-route DRC 均为 0。

这些结果是 Nangate45 typical 单 corner、提取寄生和 propagated-clock 条件下的测量，不是商业 signoff 或 silicon Fmax。详见 [`reports/v2_packed_physical/`](../../reports/v2_packed_physical/)。

## 7. Packed 与 unpacked 的受控周期对照

两种模式共用同一个以 `PACKED_ENABLE=1` elaboration 的 `systolic_axi_burst_top` 实例、同一数据、BFM、golden model、最大 burst 长度 16 和事件计数代码；每种模式开始前 reset。唯一变量是 A/B 写窗口与 payload packing。

| 模式 | 每个矩阵的 burst | A/B 事务 / W beats | 纯写入 / 含 READY 装载 | START→DONE / C 读回 | 端到端 / 含 ACK |
|---|---|---:|---:|---:|---:|
| Unpacked | 16+16+2 beats | 6 / 68 | 80 / 82 | 20 / 8 | 115 / 118 |
| Packed | 9 beats，尾拍 `WSTRB=0x3` | 2 / 18 | 22 / 24 | 20 / 8 | 57 / 60 |

端到端由 115 降至 57 拍，实测加速为 $115/57=2.0175\times$。58 拍节省中，50 拍来自少传 50 个 W beat，另外 8 拍来自少 4 笔事务、每笔两拍固定成本。START→DONE 始终为 20 拍；22 拍轮询与计算重叠。

两组 C 的四个元素均通过独立 signed matmul golden，并直接比较两组结果。所有事务返回 `OKAY`。旧 packed 回归的 62 拍从两拍 preflight status read 之前计时并包含 ACK；去掉 preflight 后与本次 60 拍 repeat-task 口径一致。详见 [`reports/v2_packed_performance/`](../../reports/v2_packed_performance/)。

## 8. 验证与证明边界

- 功能回归证明已执行激励下的协议、地址、bitmap、副作用与矩阵结果：包括跨行 packed word、单/多 lane、尾拍 partial/zero/illegal strobe、高位地址别名、ACK/reload、固定 seed backpressure 及独立 golden。它不是形式等价证明。
- Source-to-derived frontend equivalence 证明各自源 RTL 与各自派生 Verilog：Lite 4,023/4,023；unpacked Burst 4,401/4,401；packed0 4,614/4,614；packed1 5,173/5,173。它不证明 old/new RTL 互相等价，也不证明映射后或布线后等价。
- 物理检查证明本次 GDS/ODB 对应 run 中已执行的 STA、电气、overflow、detailed-route DRC、OpenROAD antenna 与 KLayout DRC 结果。DRC clean 不等于 LVS 或 formal equivalence。
- Kepler stage LEC 仍因 CPU SIGILL 关闭；post-route formal equivalence 和 LVS 尚未验证。
- 所有 PPA 数字仅适用于 Nangate45 typical 单 corner、给定参数和 active-operation 约束。没有可信功耗、multi-corner signoff 或真实 CPU/DDR/PCIe 性能结论。

## 9. 复现入口

以下命令从仓库根目录执行；物理流程需要已记录的 `ORFS_ROOT` 与 `OSS_CAD_SUITE_ROOT` 环境。

```bash
bash scripts/run_v2_lite_constant_decode_sta.sh
bash scripts/run_v2_lite_vs_burst.sh
OPENROAD_THREADS=16 bash scripts/run_v2_burst_physical.sh
OPENROAD_THREADS=16 bash scripts/run_v2_lite_comparable_physical.sh
bash scripts/run_v2_packed_synth_sta.sh
PACKED_ENABLE=1 OPENROAD_THREADS=16 bash scripts/run_v2_packed_physical.sh
PACKED_ENABLE=0 OPENROAD_THREADS=16 bash scripts/run_v2_packed_physical.sh
PACKED_ENABLE=1 PHYSICAL_RUN=antenna_input_buffer_fix OPENROAD_THREADS=16 bash scripts/run_v2_packed_physical.sh
python3 scripts/summarize_v2_packed_physical.py
bash scripts/run_v2_packed_performance.sh
```

本章止于 V2 接口装载、功能验证、综合/STA、物理实现和受控 RTL 周期测量。Packed 不等于 DMA。当前后续顺序为 sticky DONE 轮询间隔、双缓冲和 DMA，之后才进入 OS vs. WS；真实软件/内存系统、功耗、LVS 与 post-route formal 仍属于后续独立工作。
