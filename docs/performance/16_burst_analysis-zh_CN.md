# Lite 与 Burst 装载模型及实测

[English](16_burst_analysis-EN.md) | [简体中文](16_burst_analysis-zh_CN.md)


## 1. 问题与控制变量

假设：一次地址描述和响应服务多个数据拍，可以减少小矩阵装载的事务成本。固定 N=2、K=17、INT8/INT18、相同输入和 Core、控制/轮询/读回流程、连续供数及同一时钟；每个 INT8 仍占一个 32-bit 槽，不打包。

Lite baseline 在 dual-port Top 上运行，不能据此测得新增 Burst 端口面积。当前 Slave 限制与仲裁见 [AXI 范围](../wrapper/13_axi_protocol-zh_CN.md)。Burst 不是 DMA。

## 2. 独立模型

令 D=2*N*K，L 为最大拍数，B=2*ceil(N*K/L)，A/B 各自分组且允许尾部短 Burst。无争用时每组非数据开销 H=2，最后确认 INPUTS_READY 的读取 R=2：

$$T_{load}=D+BH+R$$

模型在 RTL 实现前提出 H=2 假设，RTL 随后核对数据阶段与总周期。H 不是 AXI 标准保证，不同实现必须重新校准。源文件为 models/wrapper/burst_load_model.py，预测 CSV 不是 RTL 数据。

## 3. 连续供数实测

| 路径/最大长度 | confirmed load | 完整调用 |
|---|---:|---:|
| Lite | 206 | 244 |
| Burst 1 | 206 | 244 |
| Burst 2 | 138 | 176 |
| Burst 4 | 106 | 144 |
| Burst 8 | 90 | 128 |
| Burst 16 | 82 | 120 |

单位为 DUT 周期。每配置执行两次独立数据任务，Core 结果均通过参考模型。原始快照：[burst_comparison.csv](../../reports/wrapper/burst_comparison.csv)。完整调用从 preflight STATUS 到 ACK 响应，confirmed load 从首个装载事务到最后一次 ready 查询响应。非 load 的 38 周期在该配置下相同，不能外推至不同 N/K 或轮询策略。

## 4. 拍间停顿与归因

BFM gap 只在同一 Burst 内成功握手后插入；首拍立即准备、末拍之后不加 gap。slave_gap 是早期模型的假设参数，当前连续接收硬件实验未实现这项可调停顿。

数据阶段逐周期分类：transfer=VALID/READY 1/1；master_only=0/1；slave_only=1/0；both=0/0。四者互斥，不能把两端同时等待重复计入。当前 slave_gap=0 时：

$$T_{load}=D+(D-B)G+2B+2$$

G=3 可能使较长 Burst 更慢，因为组内空隙数 D-B 增加。这只证明该激励规则的结果，不证明真实 Master 应选短 Burst。如果每份数据准备成本也跨事务存在，或能与 AW/B 重叠，必须改模型。非零 gap 行仅是敏感性分析，不能与没有同类准备开销的 Lite 行直接公平比较。

## 5. 当前结论

[已建立事实] 连续供数、无写争用下 L16 是受测点中周期最少的参考配置，装载 82、调用 120。独立模型与 30 行 Burst 样本一致。

[待验证假设] 增加 packing 后是否仍能每拍接收、是否损害频率/面积，以及 Host 是否能持续供数。下一对照见 [打包实验](17_packed_analysis-zh_CN.md)。没有 DDR、CPU、PCIe、功耗或最终 Pareto 结论。
