# Systolic Array MVP: Synthesis and PPA Plan

[English](05_synthesis_and_ppa_plan-EN.md) | [简体中文](05_synthesis_and_ppa_plan-zh_CN.md)

## 1. Document Status

- Second revision: the `read_slang` generic-synthesis flow is established and passes three configurations.
- The five baseline RTL files under `rtl/` remain frozen and were not changed for tool compatibility.
- `N/K=1/1`, `2/2`, and `4/4` complete generic synthesis, structural checks, netlist generation, and statistics.
- Without Liberty, SDC, or physical implementation, all numbers are generic structural statistics or logic-size proxies—not ASIC area, frequency, power, or a physical critical path.

## 2. Established Environment Facts

### 2.1 Frontend Probe

The system tool was:

```text
Yosys 0.52 (git sha1 fee39a3284c90249e1d9684cf6944ffbbcbb8f90)
```

`yosys -p "help read_slang"` reported no such command; `yosys -m slang -p "help read_slang"` could not load `slang.so`; and `command -v sv2v` returned nothing.

### 2.2 Built-in Frontend Reproducer

```text
yosys -p "read_verilog -sv rtl/systolic_pe.sv rtl/systolic_array.sv rtl/input_feeder.sv rtl/systolic_controller.sv rtl/systolic_array_top.sv; hierarchy -top systolic_array_top"
```

After reading `systolic_pe.sv`, built-in `read_verilog -sv` stopped at:

```text
rtl/systolic_array.sv:12: ERROR: syntax error, unexpected '[', expecting ',' or '=' or ')'
```

Line 12 is the unpacked-array port `a_left [N-1:0]`. This frontend limitation is not a reason to flatten interfaces or rewrite the baseline.

## 3. Selected Frontend and Installation

The authorized solution uses the official Linux x64 OSS CAD Suite `2026-08-30` archive:

```text
oss-cad-suite-linux-x64-20260830.tgz
SHA-256: 54ffdd32d9126ee0473a204a6b4ab98d9938c9f47013a42fe73d0822eae21dc7
```

It is a local user installation addressed through `$OSS_CAD_SUITE_ROOT`; it does not replace `/usr/bin/yosys`, use `sudo`, or modify `.bashrc`. The selected executable is:

```text
$OSS_CAD_SUITE_ROOT/bin/yosys
Yosys 0.68+136 (git sha1 c30457480-dirty, Release, Clang /usr/bin/clang++ 21.1.8)
```

`read_slang` reads the original five RTL files with top `systolic_array_top` and parameters `N`, `K`, `DATA_W=8`, and `ACC_W=18`. Minimal frontend validation reports 0 errors, 0 warnings, and 0 problems from `hierarchy -check` and `check`. Neither `sv2v` nor built-in `read_verilog -sv` is used.

## 4. Generic-Synthesis Configurations and Results

| Configuration | `N` | `K` | `DATA_W` | `ACC_W` | Derived `CYCLE_W` |
|---|---:|---:|---:|---:|---:|
| unit | 1 | 1 | 8 | 18 | 1 |
| base | 2 | 2 | 8 | 18 | 2 |
| scale | 4 | 4 | 8 | 18 | 4 |

The fixed sequence is frontend/elaboration, `hierarchy -check`, `proc`, `opt`, `check`, `memory`, `opt`, `techmap`, `opt`, and `stat`. Each `build/synth/<config>/` directory contains the complete log, `stat`, `post_proc.v`, generic Verilog and JSON netlists, pre-tech JSON, configuration, and tool version. `post_proc.v` is correctly named because it is written after `proc` and the first `opt`. `build/` is ignored by Git.

### 4.1 Traceability and Fresh Builds

All configurations first run and pass structural checks under `build/synth/.run.XXXXXX/`. Only full success publishes the fixed `n1_k1`, `n2_k2`, and `n4_k4` directories. Failed temporary results never replace formal outputs. Cleanup is restricted to a validated repository-local `build/synth` root and a validated current-run prefix.

Each `config.txt` records UTC time, Git commit and complete porcelain status, absolute Yosys path and version, OSS CAD Suite root, parameters, actual synthesis Tcl path, and output directory. A dirty worktree does not block synthesis, but its state is recorded.

### 4.2 Pre-Tech Word-Level Structure

| Configuration | PE result marker | Signed multiplier | Accumulator adder | Controller/index adder | Register cells | Register bits | Total cells |
|---|---:|---:|---:|---:|---:|---:|---:|
| `n1_k1` | 1 | 1 | 1 | 1 | 4 | 21 | 30 |
| `n2_k2` | 4 | 4 | 4 | 1 | 13 | 110 | 75 |
| `n4_k4` | 16 | 16 | 16 | 1 | 55 | 498 | 231 |

The PE result marker counts hierarchical `u_pe.psum_out` netnames in pre-tech JSON; it is not a flattened PE module-cell count. It is combined with $N^2$ multipliers, $N^2$ accumulator adders, and nonempty pre-tech/final cell sets as evidence that PE structure remains.

Accumulator adders are classified by connection: A must connect to the corresponding `u_pe.psum_out` `ACC_W` vector, and A/B/Y widths must equal `ACC_W`. All three configurations have exactly $N^2$ accumulator adders. Remaining `$add` cells are reported separately. Total `$add = N^2+1` is a strict regression baseline only for this pinned tool version, not a cross-version architectural invariant.

For `DATA_W=8`, Slang sign-extends each signed multiplier operand to $2\times DATA_W=16$ bits and preserves a full 16-bit product. The checker derives product width and sign index from configuration and validates widths, signed parameters, and every replicated sign bit. Register statistics reflect optimized observable state; unobserved terminal forwarding may be removed.

### 4.3 Generic Techmap Primitives

| Configuration | AND | MUX | NOT | OR | SDFFE | SDFF | XOR | Total cells |
|---|---:|---:|---:|---:|---:|---:|---:|
| `n1_k1` | 342 | 88 | 2 | 116 | 19 | 2 | 264 | 833 |
| `n2_k2` | 1373 | 310 | 12 | 474 | 74 | 36 | 1058 | 3337 |
| `n4_k4` | 5485 | 1162 | 36 | 1887 | 292 | 206 | 4234 | 13302 |

Counts are generated from `generic_netlist.json` into per-configuration and aggregate `structure_summary.json`; they are not hard-coded. They reproduce the pre-hardening results and are logic-size proxies, not standard-cell counts or area.

## 5. Structural Checks

- PE result markers are 1, 4, and 16 and are not used alone as instance proof.
- Multipliers and connection-classified accumulator adders equal $N^2$.
- Controller counter widths are 1, 2, and 4 bits.
- Four `check` stages report 0 problems per configuration, with no latch, undriven, multiple-driver, or combinational-loop diagnostic.
- The top is nonempty; each PE retains a signed 8×8 product sign-extended into an 18-bit accumulator.
- `N=1` retains one PE, one accumulator, and complete A/B pipe netnames; unobservable terminal registers may be optimized.
- Slang reports 0 errors and 0 warnings; logs contain no Yosys warning/error diagnostic.

`set -euo pipefail`, Yosys/checker exit codes, and `tee` under pipefail preserve strict failure semantics.

## 6. Verification After Frontend Processing

The flow confirms an empty `git diff -- rtl`, runs `git diff --check`, and reruns the unified regression. The historical text referred to six configurations; the current baseline runner now covers eight configurations and 872 corner/random operations. `read_slang` reads the original baseline directly. Successful Yosys exit alone is not semantic verification.

## 7. PPA Facts Not Established by Generic Synthesis

Generic synthesis does not establish mapped standard-cell area, achievable Fmax, setup/hold margin, dynamic or leakage power, wire delay, buffering, routed critical paths, congestion, clock trees, or parasitics. Those require a target process and PVT, Liberty, SDC, wire/load or physical implementation, optimization goals, and representative activity for power.

Subsequent Nangate45 physical results are documented separately in [Physical Implementation and PPA Analysis](07_physical_implementation_plan-EN.md); they do not retroactively change the meaning of these generic statistics.
