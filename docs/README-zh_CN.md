# 文档索引与阅读顺序

[English](README.md) | [简体中文](README-zh_CN.md)

入口：[仓库当前状态摘要](../README-zh_CN.md)。当前系统先读 11→12→13→14→16→17，再读 19 的综合实测结果和 15 的验证边界；复习 Core 读 01→02→03；V1 物理证据读 05→06→07→08→09。10 保留 V1 上游抽象，不是当前 Runtime 的完整功能清单。

| 目录 | 职责 |
|---|---|
| core/ | 冻结 V1 数学/时序/微架构及上游软件抽象 |
| wrapper/ | V2 系统、地址与总线契约 |
| software/ | Host Runtime、BFM、调用和复现 |
| verification/ | Core/Wrapper 验证范围与证据 |
| performance/ | 假设、模型、RTL 实测与 co-design |
| implementation/ | generic synthesis、STA、物理实现与局限 |

中英文放在同一主题目录，以 -EN.md / -zh_CN.md 配对，不额外分语言树。保留原 01–10 编号，新增 11–19。

| 编号 | 文档 |
|---|---|
| 01 | [设计意图](core/01_design_intent-zh_CN.md) |
| 02 | [数据流](core/02_dataflow-zh_CN.md) |
| 03 | [微架构](core/03_microarchitecture-zh_CN.md) |
| 04 | [V1 验证](verification/04_verification_plan-zh_CN.md) |
| 05 | [综合与 PPA 流程](implementation/05_synthesis_and_ppa_plan-zh_CN.md) |
| 06 | [综合缩放分析](implementation/06_synthesis_scaling_analysis-zh_CN.md) |
| 07 | [物理实现](implementation/07_physical_implementation_plan-zh_CN.md) |
| 08 | [时钟缩放](implementation/08_clock_sweep_analysis-zh_CN.md) |
| 09 | [Registered Boundary 取舍](implementation/09_registered_boundary_ppa_analysis-zh_CN.md) |
| 10 | [V1 最小软件抽象](core/10_minimal_software_contract-zh_CN.md) |
| 11 | [V2 系统架构](wrapper/11_system_architecture-zh_CN.md) |
| 12 | [寄存器与错误契约](wrapper/12_register_contract-zh_CN.md) |
| 13 | [AXI 子集与仲裁](wrapper/13_axi_protocol-zh_CN.md) |
| 14 | [Runtime 与 BFM](software/14_runtime_bfm-zh_CN.md) |
| 15 | [V2 验证](verification/15_wrapper_verification-zh_CN.md) |
| 16 | [Burst 模型与实测](performance/16_burst_analysis-zh_CN.md) |
| 17 | [打包实验](performance/17_packed_analysis-zh_CN.md) |
| 18 | [Co-design 路线](performance/18_codesign_roadmap-zh_CN.md) |
| 19 | [V2 Burst、packed 与物理结果](performance/19_v2_axi_burst_packed_results-zh_CN.md) |
