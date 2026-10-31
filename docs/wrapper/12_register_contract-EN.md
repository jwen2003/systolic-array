# V2 Register, Address and Error Contract

[English](12_register_contract-EN.md) | [简体中文](12_register_contract-zh_CN.md)


This file describes actual `systolic_device.sv`, superseding draft address/bit assignments. Addresses are device-relative byte offsets; accesses use aligned 32-bit words. Host/Interconnect handles the system base.

## 1. CSR

| Offset | Name | Access | Definition |
|---|---|---|---|
| 0x0000 | VERSION | RO | 0x00000200; not packed-capability discovery |
| 0x0004 | COMMAND | WO | bit0 START; qualified by WSTRB[0] |
| 0x0008 | STATUS | RO | bit0 BUSY, bit1 DONE, bit2 INPUTS_READY, bit3 ERROR |
| 0x000C | ACK | WO | bit0=1 in DONE releases result and clears both maps; no-op elsewhere |
| 0x0010 | ERROR_STATUS | RW1C | bits[7:0], byte-strobe-qualified clearing, new errors win |
| 0x0020 | HW_N | RO | Elaborated N |
| 0x0024 | HW_K | RO | Elaborated K |
| 0x0028 | DATA_W | RO | 8 |
| 0x002C | ACC_W | RO | 18 |

Reserved COMMAND/ACK bits are ignored. Reading a WO register errors. INPUTS_READY is the reduction AND of both per-entry maps, never a software-writable flag. Reload all inputs after ACK. No completion interrupt or separate DONE_W1C register exists.

## 2. Data Windows

| Object | Address | Access |
|---|---|---|
| A[i][k] | 0x1000 + 4*(i*K+k) | RW in LOAD; only low byte carries input |
| B[k][j] | 0x2000 + 4*(k*N+j) | RW in LOAD; only low byte carries input |
| C[i][j] | 0x3000 + 4*(i*N+j) | RO in DONE; sign-extended INT18 |
| Packed A | 0x4000 + 4*q | WO if PACKED_ENABLE=1, elements 4*q..4*q+3 |
| Packed B | 0x5000 + 4*q | WO if PACKED_ENABLE=1, elements 4*q..4*q+3 |

Old A/B ranges each span 4*N*K bytes and C spans 4*N*N, not the entire 4KiB region. Old inputs read sign-extended INT8, unwritten entries zero. Upper input-write bytes are ignored. Zero strobes suppress payload updates but not address/permission checks.

Packed aliases share original storage/maps. Each lane represents a consecutive element, with rounded window size 4*ceil(N*K/4). Invalid tail lanes must be masked. An asserted out-of-range lane rejects the whole beat, with no partial lane commit. See [packing report](../performance/17_packed_analysis-EN.md). PACKED_ENABLE defaults to 0, with no runtime capability bit; software must know the elaborated setting.

## 3. Sticky Error Bits

| bit | Name | Condition |
|---|---|---|
| 0 | START_NOT_ALLOWED | START outside LOAD or while core_busy |
| 1 | INPUT_INCOMPLETE | START in LOAD with incomplete maps |
| 2 | INVALID_ADDRESS | Undefined address, read WO, or enabled packed lane out of range |
| 3 | INPUT_WRITE_NOT_ALLOWED | A/B write outside LOAD, including packed aliases |
| 4 | RESULT_NOT_READY | C read outside DONE |
| 5 | MISALIGNED_ACCESS | Not word aligned |
| 6 | WRITE_TO_READ_ONLY | Write RO CSR or C |
| 7 | INPUT_READ_NOT_ALLOWED | Old A/B read outside LOAD |

Alignment is checked first within a request; independent read/write error bits are ORed. Error state updates as `(old & ~clear_mask) | new_errors`. New errors survive simultaneous W1C. Illegal accesses return SLVERR, with zero data on error reads. Hardware START does not require empty error state, but Runtime preflight rejects sticky errors.

## 4. Reset, Results and Responses

Synchronous active-low reset clears task state, maps, errors and core_start; Core resets psum under its own contract. Input payload is not cleared but hidden by invalid maps. Shared reset blocks acceptance and aborts pending transactions.

Results become valid after the final Core MAC; Device subsequently captures done and enters DONE. DONE persists until ACK, not until a STATUS/C read. START and input reads/writes are forbidden in DONE. ACK does not clear sticky errors. BUSY means RUN, not a busy AXI response channel.

A bad Burst descriptor can be drained and rejected in Slave without a Device sticky error. Device errors from a valid descriptor appear in both BRESP and ERROR_STATUS. There is no transaction rollback.
