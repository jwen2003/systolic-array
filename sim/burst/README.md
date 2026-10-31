# Lite / Burst 双端口集成与实测

## 当前双语文档 / Maintained bilingual documentation

[中文](../../docs/performance/16_burst_analysis-zh_CN.md) | [English](../../docs/performance/16_burst_analysis-EN.md)

下文保留本目录原始实验说明；当前状态、计时边界与限制以双语报告为准。The notes below retain their original experiment scope; use the report above for current status and boundaries.

## 文件与运行

新增 `rtl/wrapper/systolic_axi_burst_top.sv`，保留原来的 Lite-only Top、BFM 和 Runtime。
`sim/burst/axi_burst_bfm.hpp/.cpp` 对新 Top 的 Lite 与 Burst 两个端口使用同一个时钟/context。
`sim/burst/main.cpp` 是独立实验程序，重复装载、START、轮询、读回、ACK 流程，不是对旧 Runtime 的替换。

在仓库根目录运行，需要本机已有 Verilator、make 和支持 C++17 的编译器：

```bash
bash scripts/run_burst_comparison.sh
```

脚本固定 N=2/K=17，日志和新生成的 `burst_comparison.csv` 均位于 `build/wrapper/burst_comparison/`。
包内 `reports/wrapper/burst_comparison.csv` 是本次实际运行的结果快照；脚本不自动覆盖它。

## 接口和仲裁契约

- Lite 端口维持原有地址图，既能控制/读取，也能逐元素写 A/B。
- 新增 `s_burst_*` 为之前定义的受限 AXI4 写通路，只能向 A/B 写入，不提供读通路或通用 AXI4 能力。
- Burst 32-bit 对齐、INCR、每次 1..16 拍；每拍低 8 位一个 INT8，未打包，无 DMA、无双缓冲。
- 两端都是 device-relative byte offset；不是未经转换的系统物理地址。
- Device 仍只有一个写入口；Lite 从首个 AW 或 W 握手保留到 B 握手，Burst 从 AW 握手保留到 B 握手。
- 空闲时两侧同时请求，Lite 优先；不抢占，不保证公平。Host 必须完成已经开始的事务，否则另一写端口会等待，必要时共享复位。
- Burst 存续期间，Lite 的 AW/W 都不握手，也不在内部偷偷捕获；Lite 读取独立，可以读取状态。LOAD 期间并发读取 A/B 是逐字的当前状态视图，不保证整个 buffer 快照。
- `wr_grant` 由 Top 的 Burst ownership 驱动。Core 完全不接收总线 backpressure。
- 错误响应与状态不自动清除。无回滚；非法 Burst 描述由 Slave 排空并响应错误，不一定进入 Device sticky error。合法描述触发的 Device 权限错误会汇总到 B，并由 Device 记录 sticky error。

## C++ BFM

- `reset()`：共享同步复位，初始化两个 Master 接口。
- `axi_read/axi_write()`：阻塞 Lite 访问，行为和原 BFM 一致。
- `burst_write(addr, words, master_gap, response_hold)`：阻塞一次 Burst，数据传完后接收一个 B 响应。
- `step()`：先在低电平 eval 并保存握手/响应，再推进上升沿，最后回到低电平。公开用于同时请求两个端口的定向测试。
- 超时后禁止继续访问，须共享 reset；普通错误响应已被消费后才抛异常。
- Master gap 只在同 Burst 内前一拍成功后插入，不会在未握手时撤销 VALID 或改变 payload。每个 Burst 首拍立即供数，不跨 Burst 保留 gap。

## 比较和测量边界

同一组输入分别用 Lite、Burst 长度 1/2/4/8/16 装载，Burst 再分别插入 0/1/3 个 Master 空拍。
每种设置连续执行两次任务，不在两次之间复位，使用 signed INT8 数据和 INT18 回绕参考结果。
不同设置开始前复位，复位与能力读取不计入 invocation。

CSV 中 `measured_load` 包含 A/B 的全部写事务与一次 INPUTS_READY 读取。
`measured_total` 从调用前 STATUS 检查开始，直到 ACK 写响应结束；调用后的核验读取不计入。
控制与读回继续使用相同的阻塞 Lite 策略，不加入真实 CPU 软件运行时间。

Burst 数据阶段恰好从 AW 接受后的首个周期开始，到最后一拍 W 握手结束。四种计数互斥：transfer、master_only、slave_only、both。
CSV 为节省列数以 `burst_beats` 表示 transfer；Lite 行的这些 Burst 专属计数为 0，不代表 Lite 没有数据传输。
非数据开销可从 `measured_load - 2 - data_cycles` 计算；本实现的无争用实验测得每个 Burst 为 2 周期，分别为 AW 和 B 握手。

在这组受控输入下预测式为：

```
M = 2 * ceil(N*K/L)
predicted_load = 2*N*K + (2*N*K-M)*master_gap + 2*M + 2
```

此处不是把 RTL 数据阶段当黑箱改写预测式：之前独立 Python 模型已使用相同的 H=2、slave_gap=0 假设。本程序还检查数据阶段的计数和总周期；更复杂的接收延迟与争用场景需要另行校准，不能沿用固定 H。

## 结论的范围

只在 gap=0 下将 Lite 与 Burst 作理想连续供数对照。非零 gap 是 Host 供数敏感性实验，不能当作相同外部供数条件下两种接口的公平比较。
该结果是 RTL 周期测量，不是后端时序、面积或真实平台端到端时间，尚不能据此形成最终 Pareto Frontier。
Lite 行是在 dual-port Top 上测得，复现原基线的 206/244 周期；同一 Top 比较无法量化新增端口的面积代价。
