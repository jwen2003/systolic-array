# Systolic Array：计算核心与软件可访问加速器

[English](README.md) | [简体中文](README-zh_CN.md)

项目主线是 RTL/微架构设计：从 output-stationary 阵列的逐拍调度，扩展到 AXI、片上输入存储、命令状态和 C++ 调用，再用模型、验证与性能/物理证据评估取舍。

## 当前版本（2026-11-09）

- **V1 Core 已冻结**：A[N][K]×B[K][N]，N² PE，signed INT8 / INT18 wrap，K 与 N 独立，skew 配对，计算窗口 K+2N-2。
- **V2 Wrapper 已实现并仿真**：Lite 控制/读写、buffer/bitmap、LOAD/RUN/DONE、sticky errors 与 ACK、受限 AXI4 Burst 写和事务仲裁。
- **V2 实现已有实测闭环**：普通与 packed 窗口完成常量地址译码，Burst 长度及 packed/unpacked 周期完成受控对照，packed0/packed1 已在 Nangate45 2.500 ns 下完成 RTL-to-GDS；Core 保持不变。
- C++ 是 Host Runtime/BFM 与实验 driver；不是 Linux 设备驱动。Burst 不是 DMA。

入口：[文档索引](docs/README-zh_CN.md)、本页当前状态摘要、[系统架构](docs/wrapper/11_system_architecture-zh_CN.md)、[寄存器契约](docs/wrapper/12_register_contract-zh_CN.md)。

## 软件到 Core 的闭环

Host 准备 A/B → Lite/Burst 装载 → bitmap 完整 → START → 冻结 Core 计算 → Device 保持 DONE → Lite 读 C → ACK 释放并清空 bitmap。总线背压止于 Wrapper，Core 波前不 stall；C 直接索引 Core psum，无独立结果副本。

模块职责和 ownership 见 [11](docs/wrapper/11_system_architecture-zh_CN.md)；具体 AXI 子集见 [13](docs/wrapper/13_axi_protocol-zh_CN.md)。旧 Runtime 只接受完整硬件 shape，不自动 padding；V1 文档 10 中的更一般逻辑 API 仍是上游抽象。

## 已建立的 V2 证据

N2/K17 下，unpacked Burst 最大长度 1/2/4/8/16 的端到端周期分别为 239/171/139/123/115 拍，A/B 纯写入为 204/136/104/88/80 拍；在当前连续供数 BFM 下符合 `W beats + 2 × A/B 写事务数`。

输入供给间隔实验进一步表明：当相邻元素之间有 0/1/3/7 个空拍时，L1/L16 端到端周期分别为 239/115、239/171、305/305、573/573；在已测的 g=3 和 g=7 点，数据等待完全覆盖事务切换开销。结论仅适用于当前单 outstanding BFM 调度，g=2 未测；详见 [V2 结果章节](docs/performance/19_v2_axi_burst_packed_results-zh_CN.md#8-输入供给间隔实验)。

受控 packed 对照在同一个 `PACKED_ENABLE=1` Burst Top 上运行，两组最大长度均为 16。Unpacked 为 6 笔事务/68 个 W beat，packed 为 2 笔/18 beat；纯写入 80→22 拍，含 READY 装载 82→24，端到端 115→57（2.0175×），含 ACK 的可重复任务 118→60。START→DONE 保持 20 拍。

| 物理对照 | 最终功能标准单元面积 | Setup WNS | Hold WNS |
|---|---:|---:|---:|
| 同批 Lite | 11,041.972 µm² | +0.161062 ns | +0.0128362 ns |
| 同批 unpacked Burst | 12,159.914 µm²（+10.12%） | +0.172356 ns | +0.0123354 ns |
| 当前 Burst，`PACKED_ENABLE=0` | 12,002.412 µm² | +0.115657 ns | +0.004894 ns |
| 当前 Burst，`PACKED_ENABLE=1` | 12,924.984 µm²（+7.687%） | +0.149201 ns | +0.008039 ns |

面积排除 filler/tap。Packed 两组均为 Nangate45 typical、2.500 ns、提取寄生和 propagated-clock 结果；修复后的 packed1 电气违规、overflow、detailed-route DRC、OpenROAD antenna 与 KLayout DRC item 均为 0。完整证据与复现见 [V2 结果章节](docs/performance/19_v2_axi_burst_packed_results-zh_CN.md)；[Burst](docs/performance/16_burst_analysis-zh_CN.md)和[打包](docs/performance/17_packed_analysis-zh_CN.md)保留早期模型与实验历史。

功能回归、source-to-derived equivalence 和物理检查的证明范围不同；LVS 与 post-route formal equivalence 仍未证明。

## V1 物理取舍保留

Nangate45 N2/K2 Core 的 400–667 MHz sweep 已完成；400 MHz final cell area 3522.64 µm²，setup WNS +0.720010 ns，hold +0.065023 ns。666.667 MHz 是最高受测通过 target，不是 silicon Fmax。

Registered Boundary 在 667 MHz 降低 area 3.97%、timing-repair buffers 62.5%，但 RUN 从 4 增至 5 拍，同频 non-overlap 吞吐降低 20%；baseline 仍默认。详见 [物理实现](docs/implementation/07_physical_implementation_plan-zh_CN.md)、[变体](docs/implementation/09_registered_boundary_ppa_analysis-zh_CN.md)。这些数字不代表 V2 Wrapper。

## 复现与结构

```bash
bash scripts/run_wrapper_integration.sh
bash scripts/run_burst_comparison.sh
bash scripts/run_packed_comparison.sh
bash scripts/run_v2_packed_performance.sh
python3 scripts/check_docs.py
```

rtl/core 为冻结核心；rtl/wrapper 为外围；tb/core、tb/wrapper/unit、tb/integration 分别保存 Core、wrapper unit 与集成测试；sim/wrapper、burst、packed 为软件与实验；models/wrapper 保存解析模型；reports/wrapper 保存测量快照；docs 按 core、wrapper、software、verification、performance、implementation 分目录。build 是生成产物。

V1 regression/synthesis/physical 命令、固定工具环境及约束保留于对应文档，需要完整原仓库。此次只更新文档，不重跑历史物理实验。

## 尚未建立与下一步

V2 已有单 corner 映射与布线后证据，但尚无真实 CPU/DDR/PCIe 时间、可信功耗、multi-corner signoff、LVS、post-route formal proof 或最终 Pareto。Kepler CPU SIGILL 限制与 post-route 未证明继续保留；没有商业 signoff 结论。

当前顺序是 sticky DONE 轮询间隔、双缓冲、DMA，完成接口/调度实验后再进入 OS vs. WS 与 2D→1D 独立微架构比较。见 [路线](docs/performance/18_codesign_roadmap-zh_CN.md)。

## License

MIT；许可证沿用原仓库 LICENSE 文件。
