# V2 双输入 Bank 32-bit C Burst Read 实验

[English](21_dual_bank_c_burst_read_experiment-EN.md) | [简体中文](21_dual_bank_c_burst_read_experiment-zh_CN.md)

## 接口契约

`systolic_axi_dual_bank_burst_read_top` 是 `systolic_axi_dual_bank_top` 的独立实验扩展。它保留 Lite 控制、状态及 C 读取、START0/START1、单份结果缓存和 packed A/B Burst 写入，并新增专用 C AR/R 通道；现有 Lite baseline 不被替换或改变。

C 通道只支持单 outstanding、对齐的 32-bit INCR 请求，每笔 1--16 beats（`ARSIZE=2`、`ARBURST=INCR`）。C 窗口仍从 `0x3000` 开始，采用 row-major 顺序，每个 32-bit beat 返回一个符号扩展后的 signed INT18 结果。接受 AR 时，按沿前状态检查完整范围、C 窗口末端、4 KiB 边界、地址溢出、请求类型、长度及结果是否可读。非法请求按 `ARLEN+1` beats 返回零数据和 `SLVERR`，仅在请求的最后一拍置位 `RLAST`。

`RVALID` 不依赖 `RREADY`。背压期间 `RVALID`、`RDATA`、`RRESP` 和 `RLAST` 保持稳定；仅 R 握手推进 beat。无背压时同一 Burst 内连续每拍返回结果。本版只有前一笔最后一个 R 握手后才接受下一笔 AR，因此实测 Burst 边界有一个空拍。

合法 AR 被接受后到最后一个 R 握手之间，单份结果保持被占用，ACK 被拒绝。合法 AR 与 ACK 同拍时 AR 胜出；最后一个 R 握手与 ACK 同拍时仍按沿前 outstanding 状态拒绝 ACK，软件下一拍重试。成功 ACK 前仍禁止下一次 START。独立 A/B Burst 写通道可在 C 返回期间装载非活跃 bank。Lite STATUS 与 C Burst 不共享响应状态，因此 STATUS 查询不会给正在进行的 C Burst 插入气泡。

## 验证与性能

受限 adapter 通过 154 项定向检查，Device ownership 集成测试通过 29 项检查；已有双 bank Device 和 Top 回归也通过。Lite 与 Burst 读回均连续执行 20 组相同 packed 输入，使用相同 STATUS 轮询、ACK 顺序和独立黄金模型。

| N | K | Lite 总周期 | C Burst 总周期 | 节省 | 加速比 | Bursts/op | Beats/op |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 64 | 12,914 | 12,009 | 905 | 1.075360x | 16 | 256 |
| 32 | 32 | 43,634 | 24,434 | 19,200 | 1.785790x | 64 | 1,024 |

N=32/K=32 的首响应延迟为一拍，63 个 Burst 边界各增加一个空拍。20 组任务累计 1,260 拍，恰好解释实测 24,434 与理想连续响应模型预测 23,174 之间的差值。N=16/K=64 的更快读回暴露了 A/B 装载限制：平均 ACK 到下一次 START 增至 201 拍。

复现命令：

```bash
bash scripts/run_v2_dual_bank_c_burst_read.sh all
```

详细证据见[实验报告](../../reports/v2_dual_bank_c_burst_read/summary.md)。当前结果只证明已测试功能与 RTL 周期，不证明完整 AXI4、映射面积、时序收敛、LVS 或 post-route equivalence。
