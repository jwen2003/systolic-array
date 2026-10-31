# INT8 打包、并行写入与周期对照

[English](17_packed_analysis-EN.md) | [简体中文](17_packed_analysis-zh_CN.md)


## 1. 假设与控制变量

未打包每拍携带一个 INT8，打包每个 32-bit word 最多携带四个 INT8。若 Device 同拍更新四个有效元素与 bitmap，则数据拍数及事务数量均减少。固定 N/K、输入值与精度、Core、最大 Burst 拍数、连续供数、控制/轮询/读回、同一时钟；准备好的软件数据不计打包耗时。无 FIFO、DMA、双缓冲或任务重叠。

串行拆分每周期只写一个元素；FIFO 只能吸收短期突发，不能长期把 1 元素/周期提升为 4 元素/周期。串行方案目前仅为分析对照，没有实现 RTL，不报告其面积/实测周期。

## 2. 地址与有效字节

PACKED_ENABLE 默认 0，由新脚本设为 1，Device/Burst Slave 均启用。0x4000/0x5000 是旧 A/B 的写 alias，不是额外存储。packed aliases 可由 Lite 或 Burst 写入，读回使用 LOAD 中的旧窗口。没有 capability CSR 探测打包开关。

对 byte lane l：p=(addr-packed_base)+l；WDATA[8*l+:8] 写入展平元素 p。A 用 [p/K][p%K]，B 用 [p/N][p%N]。lane0 是最低 8 位。软件先按 uint8 取字节，再移位组合，避免负数扩展污染其他 lane。按 row-major 连续打包，跨行不 padding。

N2/K17 时，每个矩阵 34 个元素：8 个满拍和 1 个尾拍，A/B 各 9 拍，尾拍 WSTRB=0011。对应 packed 窗口各占 36 个可寻址字节，但只有 34 个有效元素及 bitmap bits。

稀疏 strobe 只更新对应 lane，0 strobe 仍做地址/权限检查。尾拍开启 p>=N*K 的 lane 返回 INVALID_ADDRESS，整拍不提交。描述范围必须落入一个取整后的窗口；描述错误在 Slave 排空。之前已成功的拍没有回滚，最后拍错误也计入 BRESP。

## 3. Buffer 实现

当前使用寄存数组，非重叠 lane 在同一边沿分别更新，不需要另存一份矩阵。它不证明四写端口 SRAM 或 BRAM 推断。将来映射 RAM 必须重新评估 word width、banking、全矩阵读接口、译码与时序。新增窗口占用地址空间及控制逻辑，不等于 Buffer 容量翻倍。

## 4. 模型与三个终点

令 W=ceil(N*K/4)、D=2W、B=2*ceil(W/L)。连续 W、无仲裁等待且每组 AW/B 各一周期：

| 指标 | 周期 |
|---|---|
| 最后数据提交 | D+2B-1 |
| 最终写响应消费 | D+2B |
| 软件确认 INPUTS_READY | D+2B+2 |

N2/K17/L16 预测为 21/22/24。讨论中最早的“22 周期装载”实际对应事务结束，不能与旧 CSV 包含确认读取的 82 直接比较。BFM 记录最后一次 W 握手时间戳；因为 Device 无待写 FIFO 且即时提交，它对应最后数据提交。真正就绪与软件观察就绪不是同一时间点。

## 5. 实测结果

| 指标 | 未打包 L16 | 打包 L16 |
|---|---:|---:|
| 数据拍数 | 68 | 18 |
| Burst 数量 | 6 | 2 |
| 末拍提交 | 79 | 21 |
| 写响应结束 | 80 | 22 |
| 软件确认就绪 | 82 | 24 |
| 完整调用含 ACK | 120 | 62 |

打包时间戳/响应/确认由 BFM 记录；未打包 79/80 从已验证的即时写入和 H=2 推出，旧 CSV 直接保存 82/120。confirmed load 降低 70.73%，完整调用降低 48.33%，只表示同频 RTL 周期收益。

| 打包最大长度 | 写响应结束 | confirmed load | 完整调用 |
|---|---:|---:|---:|
| 1 | 54 | 56 | 94 |
| 4 | 30 | 32 | 70 |
| 16 | 22 | 24 | 62 |

每种长度两次任务使用不同数据。额外旧窗口逐元素读回使用不计时 replay，不使 invocation 膨胀。四种 shape 的尾拍验证与检查数见 [验证矩阵](../verification/15_wrapper_verification-zh_CN.md)。模型与 24 行 RTL 数据一致。

证据：[打包 CSV](../../reports/wrapper/packed/n2k17_packed_comparison.csv)、[未打包参考](../../reports/wrapper/packed/n2k17_unpacked_reference.csv)、[原始结果摘要](../../reports/wrapper/packed/results.md)。

## 6. 复现与结论边界

```bash
bash scripts/run_packed_comparison.sh
bash scripts/run_packed_comparison.sh 2 16
bash scripts/run_packed_comparison.sh 3 5
bash scripts/run_packed_comparison.sh 1 5
python3 models/wrapper/packed_load_model.py --check-csv \
  build/wrapper/packed_comparison_n2k17/packed_comparison.csv
```

输出在 build/wrapper/packed_comparison_nNkK/，快照在 reports/wrapper/packed/。需要 Verilator、make、C++17，编译 --assert -Wall。

[已建立事实] 当前寄存 Buffer 连续接收路径把减少拍数转换为输入就绪与调用周期收益。

[待验证假设] 新硬件的面积/可实现频率、真实 CPU 现场打包时间、预打包权重复用与更复杂供数条件的收益。尚不能称为最终 Pareto、实际平台加速或能耗优化。


**当前对照限制：**实验设计要求相同输入，但现有旧/新 driver 路径使用不同数值模式；shape、精度、供数和调用策略一致。当前控制延迟与数值无关，golden 分别验证；严格相同 A/B 的跨路径配对重放尚待补充，不据此比较活动功耗。
