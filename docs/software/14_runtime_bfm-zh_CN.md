# C++ Runtime、BFM 与复现入口

[English](14_runtime_bfm-EN.md) | [简体中文](14_runtime_bfm-zh_CN.md)


## 1. 分层与实际能力

`sim/wrapper/matmul_runtime.*` 是上层：检查完整硬件 shape，装载 A/B，START，poll DONE，读回 C，再 ACK。`axi_lite_bfm.*` 是下层 Master：驱动 AXI 握手并推进仿真时钟。这是 Host Runtime + BFM，不是 Linux kernel driver。

`MatmulRuntime` 构造时读取 N/K/位宽并缓存；初始化成本不计入 invocation。输入是 row-major int8 vector，输出为承载 INT18 的 int32 vector。输入不匹配在发出任何事务前抛异常。没有自动 padding、tiling、overflow-risk rejection 或 retry。

运行中的错误不自动 reset、清 sticky errors 或 ACK，保留现场。timeout 后不可盲目重试。正常错误响应消费完再抛异常；BFM 总线 timeout 需要 reset 恢复。

## 2. 共享时钟与采样

`sim/burst/axi_burst_bfm.*` 同时驱动 Lite/Burst 端口，只使用一个 DUT context 与时钟。step 先在低电平 eval 保存本边沿握手与响应，再推进上升沿，最后回到低电平。不能在一份 DUT 上叠加两个独立 ticking BFM。

`burst_write(addr, words, master_gap, response_hold, strobes)` 接收可选逐拍 byte mask；默认仍为 1，保留旧程序含义。VALID 未握手时数据、strobe、WLAST 保持。last_transfer_cycle 记录最后一次 W 握手的绝对周期，不是 B 响应时间。

`sim/burst/main.cpp` 与 `sim/packed/main.cpp` 是独立实验 driver，重复同样的调用流程，未重构旧 Runtime。packed main 复用旧测试 helper，编译时不再同时链接旧 main；软件准备在计时窗口外。

## 3. 周期口径

Lite Runtime 记录 preflight、load、start_poll、readback、ack、total、poll_reads。load 包含 INPUTS_READY 读取，start_poll 包含 START 事务和轮询，不是纯 Core latency。total 等于各阶段之和。reset、能力读取、Host C++ 准备时间不在其中。

这不是 Host CPU 指令级模型。真实软件打包成本应另测时间，不能把 Python/C++ 在仿真主机上的执行耗时直接当成 DUT 周期。

## 4. 复现

仓库根目录有 Verilator、make、C++17 编译器后执行：

```bash
bash scripts/run_wrapper_integration.sh
bash scripts/run_burst_comparison.sh
bash scripts/run_packed_comparison.sh
bash scripts/run_packed_comparison.sh 2 16
bash scripts/run_packed_comparison.sh 3 5
bash scripts/run_packed_comparison.sh 1 5
python3 models/wrapper/burst_load_model.py --self-test --non-load-cycles 38
python3 models/wrapper/packed_load_model.py --check-csv \
  build/wrapper/packed_comparison_n2k17/packed_comparison.csv
```

wrapper_integration 是 SV Top 集成 TB；burst/packed 脚本是 C++ driver。原 Lite Runtime 的源码仍在 sim/wrapper，历史本地编译产物不视为可移植运行入口。V1 regression/synth/physical 命令保留在旧文档中，依赖完整原仓库及固定工具，不在本次文档更新中重新运行。

生成结果在 build/wrapper/，不进 Git；reports/wrapper/ 是手工保存的可审计快照。文档移动不会改变 RTL 编译 filelist。
