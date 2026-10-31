# Burst 装载周期模型

## 当前双语文档 / Maintained bilingual documentation

[中文](../../docs/performance/16_burst_analysis-zh_CN.md) | [English](../../docs/performance/16_burst_analysis-EN.md)

下文保留本目录原始实验说明；当前状态、计时边界与限制以双语报告为准。The notes below retain their original experiment scope; use the report above for current status and boundaries.

H=2 已在当前连续接收 Burst RTL 中核对；slave_gap 仍为假设。packed 模型为 packed_load_model.py，不是本文未打包模型。H=2 is now checked in RTL; slave_gap remains hypothetical.

本目录用于在实现 Burst RTL 前筛选假设。CSV 的每一行都是 `MODEL_PREDICTION`，不是 RTL 仿真结果，也不是实际 CPU 软件性能。

## 运行

在仓库根目录执行（仅 Python 标准库，无需 Verilator）：

```bash
python3 models/wrapper/burst_load_model.py --self-test --non-load-cycles 38
```

默认扫描 N=2/K=17，Burst 最大长度 1/2/4/8/16，Master 拍间空隙 0/1/3，Slave 拍间空隙 0/1，共 30 组。输出位于同目录 `burst_load_predictions.csv`。

## 假设与计时边界

- A/B 各 N*K 个 INT8，每个元素占一个 32-bit 地址槽，一拍传一个元素，不打包。
- A、B 各自分组，不跨 buffer；尾部用实际短 Burst。
- 一次处理一个 Burst；不重叠地址、数据、响应或不同事务。
- 每个 Burst 的数据阶段从首拍可发送的周期开始，直到最后一次 W 握手，首尾均计入。
- `master_gap`：Master 每次成功握手后主动暂停的周期数。
- `slave_gap`：一个假设中的接收端每次握手后不能接收的周期数，不是现有 Device 的实测属性。
- 两种 gap 都只作用于同一 Burst 内；每个 Burst 首拍立即可用；最后一拍后不额外计 gap。
- VALID 已经拉高但未握手时，保持 VALID 及同一元素，直到被接收。
- `overhead_per_burst` 默认 2：数据阶段以外的全部固定成本，包含地址、响应、事务间空隙，尚待 RTL 校准。
- 装载最后增加一次 INPUTS_READY 读取，假设为现有 Lite BFM 的 2 周期。

数据阶段四类计数互斥且完备：`transfer`、`master_only`（0/1）、`slave_only`（1/0）、`both`（0/0）；括号内是 VALID/READY。两端同时等待不应归因给任意一端，也不重复累计。

这个模型采用“握手后各自冷却”的明确策略，因此相邻拍间隔为 `1+max(master_gap,slave_gap)`。真实系统可能有突发、相位、排队等效应，不能仅由这两个参数概括；未来应使用实际握手轨迹校准。

## 结果口径

- `load_cycles` = 四类数据阶段周期之和 + 所有 Burst 的固定开销 + 完整性查询。
- `lite_reference_cycles` = 6*N*K+2，来自当前阻塞 BFM 的 3 周期/写、2 周期/读。此前 N2/K17 RTL 实测为 206 周期；脚本不重新运行 RTL。
- `load_speedup` 只对比该 Lite 参考，不代表真实系统加速。
- 非零 gap 的行是相对固定 Lite 参考的敏感性分析，并非两种接口在相同 Host/Slave 供数约束下的公平对照；后续方案比较需要分别为两侧设置匹配的外部条件。
- 有效输入字节数是 2*N*K，不是地址槽占用的 8*N*K。
- `total_cycles_prediction` 只有显式提供 `--non-load-cycles` 才生成。N2/K17 现有完整调用 244 周期，减去装载 206 后为 38。把 38 加到 Burst 预测上的前提是控制、计算、读回、ACK、轮询相位等其他成本完全不变；未来实现需要重新验证。
- 同频假设下周期可用于延迟比较；没有频率、面积或能耗模型，不能据此形成最终 Pareto Frontier。

## 下一步怎样验证

先选择连续供数条件下的有限 Burst 实现目标，随后记录 AW/W/B 握手轨迹。对照数据拍数、四类等待、非数据开销和总装载周期；差异应解释或修正模型，不能通过忽略空拍让 RTL 结果迁就预测。

Burst 长度 8 与 16 的收益差，既受固定开销影响，也受假设的拍间 gap 是否在新事务重置影响。因此不能只看这张表就决定最大长度或接收结构。
