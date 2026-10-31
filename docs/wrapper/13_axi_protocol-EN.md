# Implemented AXI Subset and Top Arbitration

[English](13_axi_protocol-EN.md) | [简体中文](13_axi_protocol-zh_CN.md)


## 1. Lite: Five Independent Channels

AW is write address, W write data, B write response, AR read address, and R read data/response. A transfer occurs only on an edge with VALID&&READY. A sender must hold VALID and payload until handshake; Slave pending flags do not enforce the Master-side obligation.

The Slave supports one outstanding write and one outstanding read independently. AW/W may arrive in either order and are saved separately. After both are present, the next edge executes one Device attempt and produces B. B/R payload stays stable under backpressure. The next same-kind transaction waits for response consumption; no same-edge response replacement is supported. AWPROT/ARPROT are ignored, not access-control mechanisms.

Device writes use wr_en/addr/data/strb with combinational wr_error. Reads use rd_en/addr with combinational data/error; no Device ready exists. Synchronous-read SRAM needs another adapter. The AR edge captures pre-edge state/data into a held R response.

## 2. Restricted AXI4 Write Burst

| Attribute | Implementation |
|---|---|
| Outstanding | One Burst, single implicit ID |
| Channels | AW/W/B only; no Burst AR/R |
| Transfer | Aligned 32-bit, AWSIZE=2, AWBURST=INCR(1) |
| Length | 1..16 beats, AWLEN=beats-1 |
| Range | Whole descriptor within one A/B window, or one packed alias if enabled |
| WSTRB | Original low byte, packed per-byte lane |
| Receive | AW before W; address/count advance only on W handshake |
| Response | One BRESP per Burst, including final-beat error |

This is not a general AXI4 Slave, read Burst or DMA. Master must not wait for WREADY before issuing AWVALID. Aligned windows are <=4KiB; full-range checks prevent 4KiB crossing and extended address arithmetic detects wrap.

Invalid descriptors drain according to AWLEN without Device attempts. WLAST mismatch suppresses that and subsequent writes while still draining AWLEN. Previous commits are not rolled back. A Master sending too few beats or never finishing can require shared reset; there is no hardware timeout guarantee. Device errors accumulate without automatically discarding every subsequent beat.

## 3. Write Ownership

Lite has idle priority and owns the entry from the first AW OR W handshake until B consumption; partial arrival is reserved. Burst owns AW through B handshake. During Burst, Lite AW/W are gated both internally and externally, preventing hidden capture behind a masked READY.

Lite reads remain independent. No preemption, fairness or hardware timeout is provided; an unfinished request can block the other writer. Shared clock/reset are required. Core never receives wr_grant or AXI backpressure.

## 4. Performance Consequence

Under continuous data without contention, the measured H=2 covers AW and B. This is an implementation result, not AXI-mandated latency. Different arbitration, synchronous storage or outstanding policy requires recalibration.
