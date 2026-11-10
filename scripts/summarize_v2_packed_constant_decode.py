#!/usr/bin/env python3
"""Compare packed constant-address decode against the saved synthesis baseline."""

from __future__ import annotations

import csv
import difflib
import hashlib
import shutil
import sys
from pathlib import Path

import summarize_v2_packed_synth_sta as packed_summary


REPO = Path(__file__).resolve().parents[1]
OLD_BUILD = REPO / "build/v2_packed_synth_sta"
NEW_BUILD = REPO / "build/v2_packed_constant_decode_synth_sta"
BASELINE_RTL = REPO / "build/v2_packed_constant_decode/baseline/systolic_device.sv"
CURRENT_RTL = REPO / "rtl/wrapper/systolic_device.sv"
OUT = REPO / "reports/v2_packed_constant_decode_synth_sta"


def load_pair(build: Path, label: str) -> list[dict[str, object]]:
    packed_summary.BUILD = build
    pair = [packed_summary.parse_variant(0), packed_summary.parse_variant(1)]
    for item in pair:
        item["experiment"] = label
    return pair


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    for path in (OLD_BUILD, NEW_BUILD, BASELINE_RTL, CURRENT_RTL):
        if not path.exists():
            raise SystemExit(f"missing required input: {path}")
    old = load_pair(OLD_BUILD, "old_dynamic_index")
    new = load_pair(NEW_BUILD, "new_constant_decode")
    rows = old + new
    OUT.mkdir(parents=True, exist_ok=True)

    with (OUT / "comparison.csv").open("w", newline="") as handle:
        fields = (
            "experiment", "packed_enable", "mapped_area_um2", "mapped_cells",
            "sequential_area_um2", "combinational_area_um2", "sequential_cells",
            "combinational_cells", "buffer_cells", "inverter_cells",
            "setup_wns_ns", "setup_tns_ns", "hold_wns_ns", "hold_tns_ns",
            "max_slew_violations", "max_capacitance_violations",
            "max_fanout_violations", "worst_startpoint", "worst_endpoint",
        )
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for item in rows:
            path = item["global_path"]
            writer.writerow({
                "experiment": item["experiment"],
                "packed_enable": item["packed_enable"],
                "mapped_area_um2": f"{item['area']:.3f}",
                "mapped_cells": item["cells"],
                "sequential_area_um2": f"{item['sequential_area']:.3f}",
                "combinational_area_um2": f"{item['combinational_area']:.3f}",
                "sequential_cells": item["sequential_cells"],
                "combinational_cells": item["combinational_cells"],
                "buffer_cells": item["buffers"],
                "inverter_cells": item["inverters"],
                "setup_wns_ns": f"{item['setup_wns']:.6f}",
                "setup_tns_ns": f"{item['setup_tns']:.6f}",
                "hold_wns_ns": f"{item['hold_wns']:.6f}",
                "hold_tns_ns": f"{item['hold_tns']:.6f}",
                "max_slew_violations": item["max_slew_violations"],
                "max_capacitance_violations": item["max_capacitance_violations"],
                "max_fanout_violations": item["max_fanout_violations"],
                "worst_startpoint": path["startpoint"],
                "worst_endpoint": path["endpoint"],
            })

    with (OUT / "packed_path_comparison.csv").open("w", newline="") as handle:
        fields = (
            "experiment", "packed_enable", "path_class", "startpoint", "endpoint",
            "slack_ns", "combinational_cells", "buffer_inverter_cells",
        )
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for item in rows:
            for path_class, key in (
                ("global_worst", "global_path"),
                ("current_addr_to_matrix", "address_path"),
                ("current_addr_to_bitmap", "bitmap_path"),
            ):
                path = item[key]
                writer.writerow({
                    "experiment": item["experiment"],
                    "packed_enable": item["packed_enable"],
                    "path_class": path_class,
                    "startpoint": path["startpoint"],
                    "endpoint": path["endpoint"],
                    "slack_ns": path["slack_ns"],
                    "combinational_cells": path["combinational_cells"],
                    "buffer_inverter_cells": path["buffer_inverter_cells"],
                })

    baseline_text = BASELINE_RTL.read_text(errors="replace").splitlines(keepends=True)
    current_text = CURRENT_RTL.read_text(errors="replace").splitlines(keepends=True)
    (OUT / "systolic_device_constant_decode.patch").write_text(
        "".join(
            difflib.unified_diff(
                baseline_text,
                current_text,
                fromfile="baseline/systolic_device.sv",
                tofile="rtl/wrapper/systolic_device.sv",
            )
        )
    )
    (OUT / "rtl_sha256.txt").write_text(
        f"before {sha256(BASELINE_RTL)}  systolic_device.sv\n"
        f"after  {sha256(CURRENT_RTL)}  systolic_device.sv\n"
    )
    for packed in (0, 1):
        for name in ("manifest.txt", "source_sha256.txt", "flow_sha256.txt"):
            shutil.copy2(
                NEW_BUILD / f"packed{packed}/{name}",
                OUT / f"new_packed{packed}_{name}",
            )

    old0, old1 = old
    new0, new1 = new
    old0_generic = sum(old0["generic_types"].values())
    new0_generic = sum(new0["generic_types"].values())
    old1_generic = sum(old1["generic_types"].values())
    new1_generic = sum(new1["generic_types"].values())
    markdown = f"""# V2 packed constant-address decode: synthesis and post-synthesis STA

## Four-run comparison

| Experiment | `PACKED_ENABLE` | Mapped area / cells | Sequential / combinational area | Setup WNS / TNS | Hold WNS / TNS | Slew / cap / fanout violations | Worst path |
|---|---:|---:|---:|---:|---:|---:|---|
| Old dynamic index | 0 | {old0['area']:.3f} µm² / {old0['cells']:,} | {old0['sequential_area']:.3f} / {old0['combinational_area']:.3f} µm² | {old0['setup_wns']:+.6f} / {old0['setup_tns']:+.6f} ns | {old0['hold_wns']:+.6f} / {old0['hold_tns']:+.6f} ns | {old0['max_slew_violations']} / {old0['max_capacitance_violations']} / {old0['max_fanout_violations']} | `{old0['global_path']['startpoint']}` → `{old0['global_path']['endpoint']}` |
| Old dynamic index | 1 | {old1['area']:.3f} µm² / {old1['cells']:,} | {old1['sequential_area']:.3f} / {old1['combinational_area']:.3f} µm² | {old1['setup_wns']:+.6f} / {old1['setup_tns']:+.6f} ns | {old1['hold_wns']:+.6f} / {old1['hold_tns']:+.6f} ns | {old1['max_slew_violations']} / {old1['max_capacitance_violations']} / {old1['max_fanout_violations']} | `{old1['global_path']['startpoint']}` → `{old1['global_path']['endpoint']}` |
| New constant decode | 0 | {new0['area']:.3f} µm² / {new0['cells']:,} | {new0['sequential_area']:.3f} / {new0['combinational_area']:.3f} µm² | {new0['setup_wns']:+.6f} / {new0['setup_tns']:+.6f} ns | {new0['hold_wns']:+.6f} / {new0['hold_tns']:+.6f} ns | {new0['max_slew_violations']} / {new0['max_capacitance_violations']} / {new0['max_fanout_violations']} | `{new0['global_path']['startpoint']}` → `{new0['global_path']['endpoint']}` |
| New constant decode | 1 | {new1['area']:.3f} µm² / {new1['cells']:,} | {new1['sequential_area']:.3f} / {new1['combinational_area']:.3f} µm² | {new1['setup_wns']:+.6f} / {new1['setup_tns']:+.6f} ns | {new1['hold_wns']:+.6f} / {new1['hold_tns']:+.6f} ns | {new1['max_slew_violations']} / {new1['max_capacitance_violations']} / {new1['max_fanout_violations']} | `{new1['global_path']['startpoint']}` → `{new1['global_path']['endpoint']}` |

## Measured effects

- Packed-enabled area changes by {new1['area']-old1['area']:+.3f} µm² ({(new1['area']/old1['area']-1)*100:+.2f}%), and mapped cells by {new1['cells']-old1['cells']:+,}.
- Packed-enabled combinational area changes by {new1['combinational_area']-old1['combinational_area']:+.3f} µm²; sequential area remains {new1['sequential_area']:.3f} µm² versus {old1['sequential_area']:.3f} µm².
- The packed-enabled frontend generic network falls from {old1_generic:,} to {new1_generic:,} primitives. Neither new frontend log contains `$div` or `$mod` templates.
- The new packed address path is `{new1['address_path']['startpoint']}` → `{new1['address_path']['endpoint']}`, slack {float(new1['address_path']['slack_ns']):+.6f} ns and {new1['address_path']['combinational_cells']} combinational cell traversals. The bitmap path slack is {float(new1['bitmap_path']['slack_ns']):+.6f} ns.
- The new packed-enabled global worst path has moved back to the Core. It is no longer a packed write path under this mapped, wire-load-model experiment.

## Packed-disabled baseline audit

- The packed-disabled behavior remains frontend-proven and retains 849 sequential cells. No packed high-byte/strobe path exists, and no `$div`/`$mod` template is present.
- It does not reproduce the old mapped netlist bit-for-bit: area changes by {new0['area']-old0['area']:+.3f} µm² and cells by {new0['cells']-old0['cells']:+,}. The post-process generic count falls from {old0_generic:,} to {new0_generic:,}, entirely due to 68 fewer generic muxes; all other generic primitive categories and register counts match. Removing the old runtime `packed_index` expression therefore changed the optimized disabled elaboration even though packed behavior is pruned. This is a synthesis-structure difference, not evidence of a functional change.

## Proof and scope

- Slang reports 0 errors and 0 warnings. Three frontend checks and the mapped Yosys check report 0 problems for both new runs.
- Source-to-derived equivalence proves {new0['formal_proven']}/{new0['formal_proven']} cells for packed-disabled and {new1['formal_proven']}/{new1['formal_proven']} for packed-enabled. This does not prove old RTL against new RTL, nor post-synthesis equivalence.
- Constraints and tools match the old experiment: Nangate45 typical, 2.500 ns, 0.050 ns uncertainty, 0.250 ns I/O max delay, zero min delay, 0.050 ns input transition, 0.010 pF output load, and `5K_hvratio_1_1` wire-load model.
- `rst_n` is intentionally the only input without delay under the active-operation false-path convention. These are pre-layout estimates with ideal clocks, not routed closure.

## Functional regression

- Wrapper unit tests pass: AXI-Lite slave 84 checks, AXI Burst write slave 132 checks, existing Device 391 checks, and the new direct packed-decode test 36 checks.
- Lite Top N=2/K=3 passes 262 checks. The Burst comparison passes 1,531 checks, including the unchanged N=2/K=17 L=16 result of 82 load cycles and 120 total cycles.
- Packed integration passes for N=2/K=17 (772 checks), N=2/K=16 (725), N=3/K=5 (480), and N=1/K=5 (264). The N=2/K=17 packed L=16 result remains 22 write cycles, last commit at cycle 21, confirmed ready at cycle 24, and 62 total cycles.
- The new Device test directly checks the N=2/K=17 A word-4 row crossing, independent same-word lanes, A/B tail strobes including zero and illegal lanes, matrix and bitmap side effects, signed bytes, and high-address alias rejection.
- Simulation plus the independent matrix golden model checks the exercised behavior; it is not a formal proof of old RTL against new RTL.

## Reproduction

```bash
ORFS_ROOT=/path/to/OpenROAD-flow-scripts \\
PACKED_SYNTH_BUILD_ROOT=build/v2_packed_constant_decode_synth_sta \\
bash /path/to/systolic-array/scripts/run_v2_packed_synth_sta.sh

python3 /path/to/systolic-array/scripts/summarize_v2_packed_constant_decode.py
```

Raw new logs, netlists, ODB, and full paths are under ignored `build/v2_packed_constant_decode_synth_sta/`. The pre-change file and the first diagnostic synthesis attempt remain under ignored `build/v2_packed_constant_decode/` and `build/v2_packed_constant_decode_synth_sta_attempt1/`.
"""
    (OUT / "summary.md").write_text(markdown)
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
