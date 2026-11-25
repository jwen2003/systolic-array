# V2 双输入 Bank 实验

[English](20_dual_input_bank_experiment-EN.md) | [简体中文](20_dual_input_bank_experiment-zh_CN.md)

## 范围

该实验变体在一个未修改的 systolic Core 前增加两份完整 A/B bank。它不替换单 bank baseline，不增加命令队列，不复制 C 存储，也不自动调度 bank；Host 显式装载并启动目标 bank。`PACKED_ENABLE` 仍是 elaboration-time 参数。

## 地址与命令契约

| 对象 | Bank 0 | Bank 1 |
|---|---:|---:|
| 普通 A | `0x1000` | `0x6000` |
| 普通 B | `0x2000` | `0x7000` |
| Packed A | `0x4000` | `0x8000` |
| Packed B | `0x5000` | `0x9000` |

普通元素仍使用 32-bit slot；packed word 最多包含四个连续 INT8 lane。完整 32-bit 地址比较避免高地址别名，`WSTRB` 独立使能各 packed lane；任何被选中的非法尾部 lane 都会拒绝整拍。受限 Burst descriptor 必须完全位于上述单一窗口中。C 仍是 `0x3000` 的单份只读窗口。

`0x0004` 的 `COMMAND` 使用 bit 0 表示 `START0`、bit 1 表示 `START1`，两者均由 `WSTRB[0]` 使能；保留位忽略。两位同时置位以 `START_NOT_ALLOWED` 拒绝。只有 Core 可用、没有等待 ACK 的结果且目标 bank 两份 written bitmap 完整时才接受 START。判定使用采样沿前状态，不存在“同拍写入补齐后启动”的旁路。

`0x0008` 的 `STATUS` 定义如下：

| Bit | 含义 |
|---:|---|
| 0 | BUSY |
| 1 | sticky DONE，由 ACK 释放 |
| 2 | bank 0 INPUTS_READY |
| 3 | 存在 sticky ERROR |
| 4 | bank 1 INPUTS_READY |
| 5 | active/result bank，仅 bit 6 为 1 时有效 |
| 6 | active/result bank 有效（BUSY 或 DONE） |

## 所有权与生命周期

接受 START 时在 Core 采样寄存后的 start pulse 之前锁存 `active_bank`，并在 RUN 与 DONE 全程保持。RUN/DONE 中拒绝对 active bank 的写入和 A/B 读取；另一 bank 仍可装载和读取。DONE 保持单份 C 结果并阻止任何新 START。ACK 只释放完成 bank，并只清该 bank 的 A/B bitmap，因此已预装的另一 bank 可直接启动。同拍接受 C 读取与 ACK 时，读取返回沿前 DONE 结果。

同步低有效复位会中止任务并清除状态、bitmap、错误和所有权有效位。输入 payload 不要求复位；未写元素回读零。数值类型、符号扩展、累加器回绕、AXI 响应/背压与错误优先级均保持 baseline 契约。

## 周期示例与验证

`N=2, K=2` 定向测试先通过普通 Lite 写装载 bank 0，发出 `START0`，再在 Core busy 时通过 packed Burst 装载 bank 1；实测出现 4 个 `core_busy && burst_active` 周期。DONE 后用独立矩阵结果核对 C，ACK 只清 bank 0，预装 bank 1 无需重载即可启动。反向场景在 bank 1 计算期间用普通 Burst 重装 bank 0。

同一测试还覆盖 active bank 拒写、不完整/busy/DONE 状态拒绝 START、响应背压、C 读取与 ACK 同拍、高地址别名、跨窗口 Burst 拒绝、sticky error 和 RUN 中复位。独立 `N=2, K=3` 测试覆盖 packed 写跨 A 行、多 lane 并行提交、合法部分尾拍、零 strobe，以及非法尾部 lane 导致整拍拒绝。

可从任意目录复现：

```bash
bash /path/to/systolic-array/scripts/run_v2_double_buffer.sh
```

这些结果仅构成功能 RTL 证据；尚未为双 bank 变体建立面积、STA、功耗、post-route equivalence 或系统软件性能结论。
