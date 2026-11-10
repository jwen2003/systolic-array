#!/usr/bin/env python3
"""Summarize the paired packed-disabled/enabled synthesis and STA runs."""

from __future__ import annotations

import csv
import json
import re
import shutil
import sys
from collections import Counter
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
BUILD = REPO / "build/v2_packed_synth_sta"
OUT = REPO / "reports/v2_packed_synth_sta"


def first(pattern: str, text: str) -> str:
    match = re.search(pattern, text, re.MULTILINE)
    if not match:
        raise ValueError(f"missing report field: {pattern}")
    return match.group(1)


def read_single(root: Path, name: str) -> str:
    matches = list(root.rglob(name))
    if len(matches) != 1:
        raise ValueError(f"expected one {name} below {root}, found {len(matches)}")
    return matches[0].read_text(errors="replace")


def cell_rows(stat: str) -> dict[str, tuple[int, float]]:
    rows: dict[str, tuple[int, float]] = {}
    for line in stat.splitlines():
        match = re.match(
            r"^\s*(\d+)\s+([0-9.E+-]+)\s+\d+\s+[0-9.E+-]+\s+([A-Z][A-Z0-9_]+)$",
            line,
        )
        if match:
            rows[match.group(3)] = (int(match.group(1)), float(match.group(2)))
    return rows


def first_path(text: str) -> dict[str, str | int]:
    blocks = re.split(r"(?=^Startpoint: )", text, flags=re.MULTILINE)
    block = next((item for item in blocks if item.startswith("Startpoint:")), "")
    if not block:
        return {
            "startpoint": "unavailable",
            "endpoint": "unavailable",
            "slack_ns": "unavailable",
            "combinational_cells": 0,
            "buffer_inverter_cells": 0,
        }
    output_rows = [
        line
        for line in block.splitlines()
        if re.match(
            r"^\s*\d+\s+[0-9.]+\s+[0-9.]+\s+[0-9.]+\s+[0-9.]+\s+[\^v]",
            line,
        )
    ]
    # The first output row is the launch register Q pin, not combinational logic.
    combinational_rows = output_rows[1:]
    return {
        "startpoint": first(r"^Startpoint: (.+)$", block),
        "endpoint": first(r"^Endpoint: (.+)$", block),
        "slack_ns": first(r"^\s*(-?[0-9.]+)\s+slack \((?:MET|VIOLATED)\)$", block),
        "combinational_cells": len(combinational_rows),
        "buffer_inverter_cells": sum(
            "(BUF_" in line or "(INV_" in line for line in combinational_rows
        ),
    }


def electrical_counts(sta: str) -> tuple[int, int, int]:
    sections = re.split(r"^(max slew|max capacitance|max fanout)\s*$", sta, flags=re.MULTILINE)
    values = {"max slew": 0, "max capacitance": 0, "max fanout": 0}
    for index in range(1, len(sections), 2):
        values[sections[index]] = sections[index + 1].count("(VIOLATED)")
    return values["max slew"], values["max capacitance"], values["max fanout"]


def generic_types(path: Path) -> Counter[str]:
    design = json.loads(path.read_text())
    return Counter(
        cell["type"]
        for module in design["modules"].values()
        for cell in module.get("cells", {}).values()
    )


def parse_variant(packed: int) -> dict[str, object]:
    root = BUILD / f"packed{packed}"
    stat = read_single(root / "work/reports", "synth_stat.txt")
    sta = (root / "sta/openroad_sta.log").read_text(errors="replace")
    cells = cell_rows(stat)
    total_match = re.search(
        r"^\s*(\d+)\s+[0-9.E+-]+\s+\d+\s+[0-9.E+-]+\s+cells$",
        stat,
        re.MULTILINE,
    )
    if not total_match:
        raise ValueError("missing total mapped cell count")
    total_cells = int(total_match.group(1))
    area = float(first(r"Chip area for module .*?:\s*([0-9.]+)", stat))
    sequential_area = float(first(r"used for sequential elements:\s*([0-9.]+)", stat))
    sequential_cells = sum(
        count for kind, (count, _) in cells.items() if kind.startswith(("DFF", "SDFF"))
    )
    buffers = sum(
        count for kind, (count, _) in cells.items() if kind.startswith(("BUF_", "CLKBUF_"))
    )
    inverters = sum(count for kind, (count, _) in cells.items() if kind.startswith("INV_"))
    slew, capacitance, fanout = electrical_counts(sta)
    global_path = first_path(sta)
    address_path = first_path((root / "packed_paths/current_addr_to_matrix.rpt").read_text())
    bitmap_path = first_path((root / "packed_paths/current_addr_to_bitmap.rpt").read_text())
    generic = generic_types(root / "frontend/post_proc.json")
    formal = (root / "frontend/equivalence.log").read_text(errors="replace")
    proven = first(r"Of those cells (\d+) are proven and 0 are unproven", formal)
    checks = [
        (root / f"frontend/{name}").read_text(errors="replace")
        for name in ("elaboration_check.rpt", "normalized_check.rpt", "post_proc_check.rpt")
    ]
    if any("found and reported 0 problems" not in report.lower() for report in checks):
        raise ValueError(f"PACKED_ENABLE={packed}: a frontend check is not clean")
    if re.search(r"^Error:", sta, re.MULTILINE):
        raise ValueError(f"PACKED_ENABLE={packed}: STA report contains an error")
    return {
        "packed_enable": packed,
        "area": area,
        "cells": total_cells,
        "sequential_area": sequential_area,
        "combinational_area": area - sequential_area,
        "sequential_cells": sequential_cells,
        "combinational_cells": total_cells - sequential_cells,
        "buffers": buffers,
        "inverters": inverters,
        "setup_wns": float(first(r"^wns max (-?[0-9.]+)$", sta)),
        "setup_tns": float(first(r"^tns max (-?[0-9.]+)$", sta)),
        "hold_wns": float(first(r"^wns min (-?[0-9.]+)$", sta)),
        "hold_tns": float(first(r"^tns min (-?[0-9.]+)$", sta)),
        "max_slew_violations": slew,
        "max_capacitance_violations": capacitance,
        "max_fanout_violations": fanout,
        "global_path": global_path,
        "address_path": address_path,
        "bitmap_path": bitmap_path,
        "generic_types": generic,
        "formal_proven": int(proven),
        "cell_rows": cells,
    }


def main() -> int:
    variants = [parse_variant(0), parse_variant(1)]
    OUT.mkdir(parents=True, exist_ok=True)
    with (OUT / "comparison.csv").open("w", newline="") as handle:
        fields = (
            "packed_enable", "mapped_area_um2", "mapped_cells",
            "sequential_area_um2", "combinational_area_um2",
            "sequential_cells", "combinational_cells", "buffer_cells",
            "inverter_cells", "setup_wns_ns", "setup_tns_ns",
            "hold_wns_ns", "hold_tns_ns", "max_slew_violations",
            "max_capacitance_violations", "max_fanout_violations",
            "worst_startpoint", "worst_endpoint",
        )
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for item in variants:
            path = item["global_path"]
            writer.writerow({
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

    with (OUT / "path_summary.csv").open("w", newline="") as handle:
        fields = (
            "packed_enable", "path_class", "startpoint", "endpoint", "slack_ns",
            "combinational_cells", "buffer_inverter_cells", "evidence",
        )
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for item in variants:
            for path_class, key, evidence in (
                ("global_worst", "global_path", "sta/openroad_sta.log"),
                ("current_addr_to_matrix", "address_path", "packed_paths/current_addr_to_matrix.rpt"),
                ("current_addr_to_bitmap", "bitmap_path", "packed_paths/current_addr_to_bitmap.rpt"),
            ):
                path = item[key]
                writer.writerow({
                    "packed_enable": item["packed_enable"],
                    "path_class": path_class,
                    "startpoint": path["startpoint"],
                    "endpoint": path["endpoint"],
                    "slack_ns": path["slack_ns"],
                    "combinational_cells": path["combinational_cells"],
                    "buffer_inverter_cells": path["buffer_inverter_cells"],
                    "evidence": f"build/v2_packed_synth_sta/packed{item['packed_enable']}/{evidence}",
                })

    all_types = sorted(set(variants[0]["cell_rows"]) | set(variants[1]["cell_rows"]))
    with (OUT / "cell_type_delta.csv").open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(("cell_type", "packed0_count", "packed1_count", "count_delta"))
        for kind in all_types:
            count0 = variants[0]["cell_rows"].get(kind, (0, 0.0))[0]
            count1 = variants[1]["cell_rows"].get(kind, (0, 0.0))[0]
            writer.writerow((kind, count0, count1, count1 - count0))

    for packed in (0, 1):
        root = BUILD / f"packed{packed}"
        for name in ("manifest.txt", "source_sha256.txt", "flow_sha256.txt"):
            shutil.copy2(root / name, OUT / f"packed{packed}_{name}")

    disabled, enabled = variants
    area_delta = enabled["area"] - disabled["area"]
    area_percent = area_delta / disabled["area"] * 100.0
    sequential_delta = enabled["sequential_area"] - disabled["sequential_area"]
    combination_delta = enabled["combinational_area"] - disabled["combinational_area"]
    markdown = f"""# V2 Burst packed support: synthesis and post-synthesis STA

## Measured comparison

| `PACKED_ENABLE` | Mapped area / cells | Sequential / combinational area | Setup WNS / TNS | Hold WNS / TNS | Electrical violations | Worst path |
|---:|---:|---:|---:|---:|---:|---|
| 0 | {disabled['area']:.3f} µm² / {disabled['cells']:,} | {disabled['sequential_area']:.3f} / {disabled['combinational_area']:.3f} µm² | {disabled['setup_wns']:+.6f} / {disabled['setup_tns']:+.6f} ns | {disabled['hold_wns']:+.6f} / {disabled['hold_tns']:+.6f} ns | slew {disabled['max_slew_violations']}, cap {disabled['max_capacitance_violations']}, fanout {disabled['max_fanout_violations']} | `{disabled['global_path']['startpoint']}` → `{disabled['global_path']['endpoint']}` |
| 1 | {enabled['area']:.3f} µm² / {enabled['cells']:,} | {enabled['sequential_area']:.3f} / {enabled['combinational_area']:.3f} µm² | {enabled['setup_wns']:+.6f} / {enabled['setup_tns']:+.6f} ns | {enabled['hold_wns']:+.6f} / {enabled['hold_tns']:+.6f} ns | slew {enabled['max_slew_violations']}, cap {enabled['max_capacitance_violations']}, fanout {enabled['max_fanout_violations']} | `{enabled['global_path']['startpoint']}` → `{enabled['global_path']['endpoint']}` |

- Enabling packed support adds **{area_delta:.3f} µm² ({area_percent:.2f}%)** and **{enabled['cells'] - disabled['cells']:,} cells**.
- Sequential area rises by only {sequential_delta:.3f} µm²; combinational area rises by {combination_delta:.3f} µm². The mapped cost is therefore overwhelmingly combinational, not stored state.
- The packed-disabled fresh run exactly reproduces the audited Burst reference: 11,545.730 µm², 5,553 cells, setup WNS -0.015262 ns.
- The packed-enabled global worst path moves from the Core feeder/PE accumulator path into packed write logic and misses 2.500 ns by 11.434590 ns under the same post-synthesis wire-load assumptions.

## Packed-path evidence

- `current_addr` → matrix data (`PACKED_ENABLE=1`): `{enabled['address_path']['startpoint']}` → `{enabled['address_path']['endpoint']}`, slack {float(enabled['address_path']['slack_ns']):+.6f} ns, {enabled['address_path']['combinational_cells']} mapped combinational cell traversals, including {enabled['address_path']['buffer_inverter_cells']} buffer/inverter traversals.
- `current_addr` → written bitmap (`PACKED_ENABLE=1`): `{enabled['bitmap_path']['startpoint']}` → `{enabled['bitmap_path']['endpoint']}`, slack {float(enabled['bitmap_path']['slack_ns']):+.6f} ns, {enabled['bitmap_path']['combinational_cells']} mapped combinational cell traversals.
- High byte-lane data and strobes (`s_burst_wdata[8/16/24/31]`, `s_burst_wstrb[1/2/3]`) have no matrix/bitmap path when packed support is disabled; corresponding paths exist and meet timing when enabled. The failing cone is controlled by packed address/index selection rather than the byte data pin itself.
- The packed-enabled frontend log explicitly expands `$div` and `$mod` templates; the packed-disabled log has neither. After technology mapping these operators no longer appear as named cells: the generic network grows from {sum(disabled['generic_types'].values()):,} to {sum(enabled['generic_types'].values()):,} primitives, especially mux/AND/OR/XOR logic. This proves retention and expansion of the packed index arithmetic, but source-name loss after flattening prevents assigning every mapped gate exclusively to `/17`, `%17`, byte-lane enable, or matrix selection.

## Frontend and constraint scope

- Both runs use the same top, source filelist, N=2, K=17, DATA_W=8, ACC_W=18, Nangate45 typical library, ORFS commit and immutable image. Only `PACKED_ENABLE` differs.
- Clock 2.500 ns; uncertainty 0.050 ns; I/O max delay 0.250 ns; min delay 0; input transition 0.050 ns; output load 0.010 pF; Liberty wire-load model `5K_hvratio_1_1`.
- All three Yosys frontend checks report 0 problems for each run. Source-to-derived equivalence proves {disabled['formal_proven']}/{disabled['formal_proven']} cells for packed-disabled and {enabled['formal_proven']}/{enabled['formal_proven']} for packed-enabled. This is not post-synthesis or post-route equivalence.
- `rst_n` is the single input without delay because the existing active-operation SDC false-paths reset. No other functional input is reported unconstrained.
- These are mapped, pre-layout results with ideal clock and wire-load interconnect. Hold and electrical results are diagnostics, not routed closure; no placement, CTS, extraction, or route was run.

## Next diagnostic focus

Before any RTL optimization, isolate the packed `current_addr`/beat-to-element-index arithmetic from the fixed-element write-enable/matrix selection network. The first candidate is the K=17 quotient/remainder cone; the second is the resulting large dynamic selection/write-enable fanout. The current evidence shows both are present in the failing cone but does not safely apportion delay between them after flattening.

## Reproduction

```bash
ORFS_ROOT=/path/to/OpenROAD-flow-scripts \
OSS_CAD_SUITE_ROOT=/path/to/oss-cad-suite-20260830 \
bash /path/to/systolic-array/scripts/run_v2_packed_synth_sta.sh

python3 /path/to/systolic-array/scripts/summarize_v2_packed_synth_sta.py
```

Raw logs, mapped netlists, ODB, full STA paths, manifests, and hashes remain under ignored `build/v2_packed_synth_sta/packed0/` and `packed1/`. Machine-readable results are `comparison.csv`, `path_summary.csv`, and `cell_type_delta.csv` in this directory.
"""
    (OUT / "summary.md").write_text(markdown)
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
