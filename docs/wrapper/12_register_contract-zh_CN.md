# V2 寄存器、地址与错误契约

[English](12_register_contract-EN.md) | [简体中文](12_register_contract-zh_CN.md)


本文件描述当前 `systolic_device.sv`，取代讨论草案中的地址/bit 分配。所有地址为设备相对 byte offset，接口为 32-bit word，4 字节对齐；系统基址由 Host/Interconnect 处理。

## 1. CSR

| 偏移 | 名称 | 访问 | 定义 |
|---|---|---|---|
| 0x0000 | VERSION | RO | 0x00000200；不是打包能力探测 |
| 0x0004 | COMMAND | WO | bit0 START；仅 WSTRB[0] 有效 |
| 0x0008 | STATUS | RO | bit0 BUSY、bit1 DONE、bit2 INPUTS_READY、bit3 ERROR |
| 0x000C | ACK | WO | bit0=1 且在 DONE 时释放结果并清空 A/B bitmap；其他状态成功无操作 |
| 0x0010 | ERROR_STATUS | RW1C | bits[7:0]，按 WSTRB 生成清除掩码，新错误优先 |
| 0x0020 | HW_N | RO | elaborated N |
| 0x0024 | HW_K | RO | elaborated K |
| 0x0028 | DATA_W | RO | 8 |
| 0x002C | ACC_W | RO | 18 |

COMMAND/ACK 保留位忽略；读取 WO 寄存器报 INVALID_ADDRESS。STATUS.INPUTS_READY 来自两张 per-entry written bitmap 的归约 AND，软件不可直接写。ACK 后必须完整重装 A/B。没有 completion interrupt 或独立 DONE_W1C 寄存器。

## 2. 数据窗口

| 对象 | 地址 | 访问 |
|---|---|---|
| A[i][k] | 0x1000 + 4*(i*K+k) | LOAD 内 RW，只有低 byte 有输入含义 |
| B[k][j] | 0x2000 + 4*(k*N+j) | LOAD 内 RW，只有低 byte 有输入含义 |
| C[i][j] | 0x3000 + 4*(i*N+j) | DONE 内 RO，INT18 符号扩展到 32 位 |
| Packed A | 0x4000 + 4*q | PACKED_ENABLE=1 时 WO，元素 4*q..4*q+3 |
| Packed B | 0x5000 + 4*q | PACKED_ENABLE=1 时 WO，元素 4*q..4*q+3 |

旧 A/B 有效范围各为 4*N*K 字节；C 为 4*N*N 字节，不是整个 4KiB 均可访问。旧输入按 INT8 符号扩展读回，未写条目为零；旧输入高字节写忽略。零 strobe 不更新数据，但地址/权限仍检查。

Packed alias 共用原存储及 bitmap。每个 byte lane 对应一个连续元素，范围按 4*ceil(N*K/4) 字节向上取整，尾部无效 lane 必须屏蔽。开启越界 lane 时整拍拒绝，不提交部分 lane。详细规则见 [打包报告](../performance/17_packed_analysis-zh_CN.md)。PACKED_ENABLE 默认 0，无运行时 capability bit；实验软件必须知道实例参数。

## 3. Sticky error 位

| bit | 名称 | 条件 |
|---|---|---|
| 0 | START_NOT_ALLOWED | 非 LOAD 或 core_busy 时请求 START |
| 1 | INPUT_INCOMPLETE | LOAD 中输入不完整时 START |
| 2 | INVALID_ADDRESS | 未定义地址、读 WO、或打包有效 lane 越界 |
| 3 | INPUT_WRITE_NOT_ALLOWED | 非 LOAD 写 A/B，包括 packed alias |
| 4 | RESULT_NOT_READY | 非 DONE 读 C |
| 5 | MISALIGNED_ACCESS | 地址非 4 字节对齐 |
| 6 | WRITE_TO_READ_ONLY | 写 RO CSR 或 C |
| 7 | INPUT_READ_NOT_ALLOWED | 非 LOAD 读旧 A/B 窗口 |

单个请求先检查对齐；独立读写错误按位 OR。错误寄存器更新为 `(old & ~clear_mask) | new_errors`；同拍新错误不会被 W1C 擦掉。非法访问返回 SLVERR，错误读取数据为零。合法 START 不要求 ERROR_STATUS 为空，但 Runtime preflight 会拒绝已有 sticky error。

## 4. reset、结果与响应

同步低有效 reset 清状态、bitmap、errors、core_start；Core 独立按其 reset 清 psum。输入 payload 不清，未写数据因 bitmap 不可见。reset 中不接收请求；共享 reset 会中止未完成事务。

Core 最后一次 MAC 提交后结果可见；Device 随后捕获 done 进入 DONE。DONE 会持续到 ACK，不会因读取 STATUS/C 自动清除。START、输入读写在 DONE 均不合法；ACK 并不清 sticky errors。BUSY 只表示 RUN，不表示 B/R 通道繁忙。

Burst 描述错误可能在 Slave 处被排空并报错，不进入 Device sticky bits；合法描述下的 Device 错误同时反映在 BRESP 和 ERROR_STATUS。整组事务没有回滚。
