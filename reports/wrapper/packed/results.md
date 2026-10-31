# Packed parallel-write RTL results — 2026-10-30

Measured with Verilator 5.048 (pip distribution), --assert -Wall, no warnings
or errors. Toolchain paths/workarounds for the distribution are local environment
settings, not requirements of the portable repository script.

## N2/K17, max Burst length 16, continuous prepared data

| Metric | Unpacked | Packed |
|---|---:|---:|
| INT8 elements | 68 | 68 |
| Data beats | 68 | 18 |
| Burst transactions | 6 | 2 |
| Final data commit | 79 | 21 |
| All write responses consumed | 80 | 22 |
| Host confirmed INPUTS_READY | 82 | 24 |
| Full invocation incl. ACK | 120 | 62 |

The unpacked 79/80 boundary values follow its already-verified immediate write
path and H=2 protocol; old CSV directly records confirmed-load=82 and total=120.
Packed BFM explicitly timestamps final W handshake. Do not compare packed=22
with unpacked=82, because they use different end points. Matched confirmed load
is reduced 70.73%; full invocation is reduced 48.33% (same-clock RTL cycles).
No PPA, measured CPU packing cost, real memory bandwidth, or end-to-end CPU time.

## Regression

| Configuration | Tail valid bytes/matrix | Self-checks |
|---|---:|---:|
| N2 K17 | 2 | 772 |
| N2 K16 | 4 | 725 |
| N3 K5 | 3 | 480 |
| N1 K5 | 1 | 264 |
| PACKED_ENABLE=0 old full Burst benchmark | not packed | 1531 |

Total: 3772 checks PASS. Independent analytical script agrees with all 24
packed measured rows (including beat count, Burst count and three timing ends).
Golden matmul independently sums signed bytes and wraps to INT18. These checks
are not a formal proof or exhaustive protocol/shape coverage.

The three lengths measured for N2/K17 give:

| Packed max length | Responses consumed | Confirmed load | Full invocation |
|---|---:|---:|---:|
| 1 | 54 | 56 | 94 |
| 4 | 30 | 32 | 70 |
| 16 | 22 | 24 | 62 |

Each setting has two measured operations with different data; per-element A/B
readback checks use an untimed separate replay so they do not inflate timing.

## Next decision

Parallel packing works in this RTL/register-buffer organization and stimulus.
Before selecting a physical Pareto candidate, measure area/timing at a common
constraint, then compare Ncycles/f. Test software preparation separately for
prepacked weights vs per-invocation dynamic inputs. Serial unpacking/FIFO remains
a modeled alternative, not an implemented/measured competitor in this package.
