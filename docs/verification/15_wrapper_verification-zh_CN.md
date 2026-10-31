# V2 验证矩阵与证据边界

[English](15_wrapper_verification-EN.md) | [简体中文](15_wrapper_verification-zh_CN.md)


## 1. 分层目标

| 层次 | 主要证据 |
|---|---|
| Lite Slave unit TB | AW/W 任意顺序、WSTRB、读写错误、B/R 背压、响应保持和 reset |
| Device unit TB | 地址/权限、bitmap、两轮任务、错误 OR/W1C、结果生命周期 |
| Lite Top integration TB | Slave→Device→Core 完整链路 |
| C++ Lite Runtime | shape 拒绝、软件装载/调用/读回与周期阶段求和 |
| 双端口 Burst driver | 写 ownership、partial AW/W 保留、描述拒绝、held response、两轮计算 |
| 打包 driver | 逐 lane 有效、跨行、旧窗口读回、尾拍、缺失 bitmap、INT18 wrap 与周期模型 |

历史 Lite Slave 84 项、Burst Slave 132 项 unit checks 是阶段记录，不与下表直接相加，以免把重复测试当成独立覆盖。V1 的 872 个 operation 也不是 V2 的协议覆盖数字。

## 2. 本轮可复现记录

| 当前 runner/配置 | 自检 | 证据文件 |
|---|---:|---|
| run_burst_comparison，PACKED_ENABLE=0 | 1531 | build/wrapper/burst_comparison/simulation.log |
| packed N2/K17 | 772 | reports/wrapper/packed/n2k17_simulation.log |
| packed N2/K16 | 725 | reports/wrapper/packed/n2k16_simulation.log |
| packed N3/K5 | 480 | reports/wrapper/packed/n3k5_simulation.log |
| packed N1/K5 | 264 | reports/wrapper/packed/n1k5_simulation.log |

上述合计 3772 checks，均 PASS，编译 --assert -Wall 无 warning/error。它们包含共享 helper 和重复断言，不是 3772 个独立测试场景。四个 packed 配置覆盖尾拍 1/2/3/4 个有效字节。独立 Python 模型核对 24 行 packed RTL CSV。

旧 Burst driver 有 32 次计时 operation（Lite 2 次，5 lengths×3 gaps×2=30 次 Burst）。每个 packed 配置有 8 次计时 operation（旧 L16 两次、新三种长度各两次），另有不计时读回 replay 和定向测试；不把它们混为性能样本数。

## 3. 打包正确性方法

新窗口写、旧窗口读，逐项比较全部 A/B。数据含负数与相邻可区分值，检查跨行映射和符号扩展。稀疏 WSTRB 验证 lane0=0 时高 lane 仍可写；被屏蔽有效 lane 保留旧值。漏写末元素必须保持 INPUTS_READY=0 并拒绝 START；补齐后可启动。

尾部越界 strobe 使整拍拒绝；合法旧值不受损。描述越界由 Slave 排空而不触碰 Device。RUN/DONE 禁止输入写，C 在 DONE 保持。最终 C 用独立数学 dot product 与 modulo 2^18 比较。检查不通过就不能采信性能结果。

## 4. 证明范围

未完成 formal AXI proof、任意 shape 穷尽验证、CDC、同步 RAM 接口、随机 memory-system 流量或真实 CPU/DDR 负载。packed path 连续接收是当前设计目标，没有人为注入其 WREADY 停顿；B 保持、双写仲裁和默认路径回归不等于所有 packed 背压情形均已穷尽。

V1 formal/physical 缺口原样保留，见 [V1 验证](04_verification_plan-zh_CN.md)。所有“已通过”数字来自已有报告；本次只改文档，不把文档检查宣称为重新跑过 RTL。
