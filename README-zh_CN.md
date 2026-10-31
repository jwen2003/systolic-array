# Systolic Array：计算核心与软件可访问加速器

[English](README.md) | [简体中文](README-zh_CN.md)

项目主线是 RTL/微架构设计：从 output-stationary 阵列的逐拍调度，扩展到 AXI、片上输入存储、命令状态和 C++ 调用，再用模型、验证与性能/物理证据评估取舍。

## 当前版本（2026-10-30）

- **V1 Core 已冻结**：A[N][K]×B[K][N]，N² PE，signed INT8 / INT18 wrap，K 与 N 独立，skew 配对，计算窗口 K+2N-2。
- **V2 Wrapper 已实现并仿真**：Lite 控制/读写、buffer/bitmap、LOAD/RUN/DONE、sticky errors 与 ACK、受限 AXI4 Burst 写和事务仲裁。
- **打包实验已完成 RTL 对照**：可选 packed aliases，每拍最多四个 INT8 并行写；Core 不变。
- C++ 是 Host Runtime/BFM 与实验 driver；不是 Linux 设备驱动。Burst 不是 DMA。

入口：[文档索引](docs/README-zh_CN.md)、本页当前状态摘要、[系统架构](docs/wrapper/11_system_architecture-zh_CN.md)、[寄存器契约](docs/wrapper/12_register_contract-zh_CN.md)。

## 软件到 Core 的闭环

Host 准备 A/B → Lite/Burst 装载 → bitmap 完整 → START → 冻结 Core 计算 → Device 保持 DONE → Lite 读 C → ACK 释放并清空 bitmap。总线背压止于 Wrapper，Core 波前不 stall；C 直接索引 Core psum，无独立结果副本。

模块职责和 ownership 见 [11](docs/wrapper/11_system_architecture-zh_CN.md)；具体 AXI 子集见 [13](docs/wrapper/13_axi_protocol-zh_CN.md)。旧 Runtime 只接受完整硬件 shape，不自动 padding；V1 文档 10 中的更一般逻辑 API 仍是上游抽象。

## 已建立的性能证据

N2/K17、连续供数、相同时钟计数，软件确认就绪口径：

| 方案 | load 周期 | invocation 周期（含 ACK） |
|---|---:|---:|
| Lite on dual Top | 206 | 244 |
| 未打包 Burst L16 | 82 | 120 |
| 并行打包 Burst L16 | 24 | 62 |

packing 末拍提交/最终写响应/软件确认分别为 21/22/24。比较必须用同一终点。旧/新 driver 数值模式不同，当前控制延迟不依赖数值，结果各自通过 golden；严格同输入配对与真实软件准备成本仍待补充。详见 [Burst](docs/performance/16_burst_analysis-zh_CN.md)、[打包](docs/performance/17_packed_analysis-zh_CN.md)。

四种 packed shape 加旧 Burst 回归共 3772 checks；24 行 packed RTL 数据与独立模型一致。检查数包含重复 helper，不等于独立场景数。V1 的 872 operation、843/843 frontend equivalence 与 V2 证据分别记账。

## V1 物理取舍保留

Nangate45 N2/K2 Core 的 400–667 MHz sweep 已完成；400 MHz final cell area 3522.64 µm²，setup WNS +0.720010 ns，hold +0.065023 ns。666.667 MHz 是最高受测通过 target，不是 silicon Fmax。

Registered Boundary 在 667 MHz 降低 area 3.97%、timing-repair buffers 62.5%，但 RUN 从 4 增至 5 拍，同频 non-overlap 吞吐降低 20%；baseline 仍默认。详见 [物理实现](docs/implementation/07_physical_implementation_plan-zh_CN.md)、[变体](docs/implementation/09_registered_boundary_ppa_analysis-zh_CN.md)。这些数字不代表 V2 Wrapper。

## 复现与结构

```bash
bash scripts/run_wrapper_integration.sh
bash scripts/run_burst_comparison.sh
bash scripts/run_packed_comparison.sh
python3 scripts/check_docs.py
```

rtl/core 为冻结核心；rtl/wrapper 为外围；tb/core、tb/wrapper/unit、tb/integration 分别保存 Core、wrapper unit 与集成测试；sim/wrapper、burst、packed 为软件与实验；models/wrapper 保存解析模型；reports/wrapper 保存测量快照；docs 按 core、wrapper、software、verification、performance、implementation 分目录。build 是生成产物。

V1 regression/synthesis/physical 命令、固定工具环境及约束保留于对应文档，需要完整原仓库。此次只更新文档，不重跑历史物理实验。

## 尚未建立与下一步

V2 尚无后端面积/频率、真实 CPU/DDR/PCIe 时间、可信功耗或最终 Pareto。post-synthesis equivalence inconclusive、Kepler CPU SIGILL 限制、post-route 未证明保留；没有商业 signoff 结论。

先复现、掌握模型与契约，再结合软件准备和物理反馈筛候选。DMA/双缓冲按瓶颈触发；WS/OS 和 2D→1D 为后续独立微架构实验，尚未实现。见 [路线](docs/performance/18_codesign_roadmap-zh_CN.md)。

## License

MIT；许可证沿用原仓库 LICENSE 文件。
