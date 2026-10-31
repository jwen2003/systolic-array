# AXI 协议实现范围与 Top 仲裁

[English](13_axi_protocol-EN.md) | [简体中文](13_axi_protocol-zh_CN.md)


## 1. Lite：五个独立通道

AW 为写地址、W 为写数据、B 为写响应、AR 为读地址、R 为读数据及响应。每个通道仅在上升沿 VALID&&READY 时传输。发送方声明 VALID 后，未握手前必须保持 VALID 和 payload；Slave 的 pending 并不代替 Master 的这一义务。

本 Slave 独立支持一个 outstanding write 和一个 outstanding read。AW/W 可以任意先后到达，分别保存；两者齐备后的下一边沿执行一次 Device 写入并产生 B。B/R 背压期间保持响应；消费前不接受下一同类事务，不支持同拍替换响应。AWPROT/ARPROT 被忽略，不提供权限隔离。

Device 写接口为 wr_en/addr/data/strb 与组合 wr_error；读接口为 rd_en/addr 与组合 rd_data/error。没有 Device-side ready，不能直接换成同步读 SRAM。AR 握手边沿捕获旧状态的读快照，随后 RVALID 保持它直到 RREADY。

## 2. Burst：受限 AXI4 写子集

| 属性 | 本实现 |
|---|---|
| outstanding | 一次一组，单隐式 ID |
| 通道 | AW/W/B；没有 AR/R Burst |
| 传输 | 32-bit 对齐，AWSIZE=2，AWBURST=INCR(1) |
| 长度 | 1..16 拍，AWLEN=拍数-1 |
| 范围 | 完整 descriptor 必须位于一个 A/B 窗口；打包开启时也允许一个 packed alias |
| WSTRB | 未打包沿用低 byte；打包逐 byte lane |
| 接收 | AW 先接受，然后 W；数据和计数只在 W 握手推进 |
| 响应 | 整组一个 BRESP，包含最后一拍错误 |

这不是通用 AXI4 Slave、Burst 读接口或 DMA。Master 不能等待 WREADY 才发 AWVALID。本设计对齐且窗口<=4KiB，整组范围检查防止跨 4KiB；用扩展位地址计算捕捉 wrap。

非法描述按 AWLEN 排空，不尝试 Device 写。WLAST 与预期末拍不符时抑制本拍及后续写入，仍按 AWLEN 排空；较早成功的拍不回滚。若 Master 少发数据或永远不结束，硬件无超时保证，可能需共享 reset。Device 错误汇总但不会自动丢弃所有后续合法拍。

## 3. 写事务 ownership

空闲时 Lite 优先。Lite 从第一个 AW 或 W 握手开始持有入口，直到 B 握手释放；因此地址/数据只到一半也不会被 Burst 抢占。Burst 从 AW 到 B 握手保留入口。Burst 活跃时 Lite AW/W 在内部与外部同时屏蔽，避免 READY 没有对外可见却在内部捕获请求。

Lite reads 不被写 ownership 阻塞。没有抢占、公平性保证或总线 timeout；一个不完成的请求可以阻塞另一写端。两端必须共享时钟与复位。Core 不接收 wr_grant 或 AXI backpressure。

## 4. 从握手到性能

当前无争用连续数据下，每组开销 H=2（AW 和 B）；不是 AXI 标准要求的固定延迟。更复杂的仲裁、同步 RAM 或 outstanding 策略会改变 H 和数据接收间隔，必须重新测量。
