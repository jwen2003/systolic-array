# V2 Dual-Input-Bank Experiment

[English](20_dual_input_bank_experiment-EN.md) | [简体中文](20_dual_input_bank_experiment-zh_CN.md)

## Scope

This experimental variant adds two complete A/B banks to one unchanged systolic Core. It does not replace the single-bank baseline, add command queuing, duplicate C storage, or schedule banks automatically. The host explicitly loads and starts a bank. `PACKED_ENABLE` retains its elaboration-time meaning.

## Address and command contract

| Object | Bank 0 | Bank 1 |
|---|---:|---:|
| Normal A | `0x1000` | `0x6000` |
| Normal B | `0x2000` | `0x7000` |
| Packed A | `0x4000` | `0x8000` |
| Packed B | `0x5000` | `0x9000` |

Each normal element remains a 32-bit slot; packed words contain up to four consecutive INT8 lanes. Full 32-bit address comparisons prevent high-address aliases. `WSTRB` independently qualifies packed lanes. An asserted invalid tail lane rejects the whole beat. Restricted Burst descriptors must stay wholly inside one listed window. C remains the single read-only window at `0x3000`.

`COMMAND` at `0x0004` uses bit 0 for `START0` and bit 1 for `START1`; `WSTRB[0]` qualifies both. Reserved bits are ignored. Setting both start bits is rejected with `START_NOT_ALLOWED`. A start is accepted only when the Core is available, no result awaits ACK, and both written maps of the selected bank are complete. Decisions use pre-edge state: a write cannot complete a map and start it through a same-edge bypass.

`STATUS` at `0x0008` is:

| Bit | Meaning |
|---:|---|
| 0 | BUSY |
| 1 | sticky DONE, released by ACK |
| 2 | bank 0 INPUTS_READY |
| 3 | sticky ERROR present |
| 4 | bank 1 INPUTS_READY |
| 5 | active/result bank; meaningful only when bit 6 is set |
| 6 | active/result bank valid (BUSY or DONE) |

## Ownership and lifecycle

Accepted START latches `active_bank` before the Core samples the registered start pulse. That selection remains stable through RUN and DONE. Writes and A/B reads to the active bank are rejected in RUN and DONE; the other bank remains loadable and readable. DONE keeps the single C result stable and blocks every new START. ACK releases only the completed bank and clears only that bank's A/B maps, so a preloaded peer bank can start immediately. A C read accepted on the same edge as ACK observes the pre-edge DONE result.

Synchronous active-low reset aborts work and clears state, maps, errors, and ownership validity. Payload storage need not reset; unwritten entries read as zero. Numeric types, sign extension, accumulator wraparound, AXI response/backpressure behavior, and error priority are unchanged from the baseline contract.

## Cycle example and verification

The directed `N=2, K=2` test loads bank 0 through normal Lite writes, starts `START0`, and loads bank 1 through packed Burst writes while the Core is busy. It measured four cycles with `core_busy && burst_active`. After DONE, C is checked against an independent matrix result, ACK clears only bank 0, and preloaded bank 1 starts without reload. The reverse direction reloads bank 0 with normal Burst writes during bank 1 execution.

The same test covers active-bank rejection, incomplete/busy/DONE start rejection, response backpressure, simultaneous C read and ACK, high-address aliases, cross-window Burst rejection, sticky errors, and reset during RUN. A separate `N=2, K=3` test covers packed writes crossing an A row, parallel lanes, legal partial tails, zero strobes, and whole-beat rejection for an invalid tail lane.

Reproduce from any directory:

```bash
bash /path/to/systolic-array/scripts/run_v2_double_buffer.sh
```

This is functional RTL evidence only. No area, STA, power, post-route equivalence, or system-software performance conclusion is established for the dual-bank variant.
