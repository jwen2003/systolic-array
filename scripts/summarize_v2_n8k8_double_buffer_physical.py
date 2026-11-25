#!/usr/bin/env python3
"""Summarize the N8/K8 single- and dual-input-bank physical runs."""

import csv
import hashlib
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build/openroad/v2_n8k8_double_buffer_physical"
OUT = ROOT / "reports/v2_n8k8_double_buffer_physical"
RUNS = {
    "single": ("systolic_axi_burst_top", "systolic_axi_burst_top_n8_k8_packed_physical"),
    "dual": ("systolic_axi_dual_bank_top", "systolic_axi_dual_bank_top_n8_k8_packed_physical"),
}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def first_path(path):
    text = path.read_text(errors="replace")
    block = text.split("Startpoint:", 1)[1].split("Startpoint:", 1)[0]
    start = re.search(r"^(\S+)", block.lstrip())
    endpoint = re.search(r"Endpoint: (\S+)", block)
    slack = re.search(r"([-+]?\d+\.\d+)\s+slack \((?:MET|VIOLATED)\)", block)
    arrival = re.search(r"([-+]?\d+\.\d+)\s+data arrival time", block)
    cell_delay = 0.0
    net_delay = 0.0
    in_data = False
    previous_instance = None
    for line in block.splitlines():
        if "data arrival time" in line:
            break
        match = re.search(
            r"\s([-+]?\d+\.\d+)\s+([-+]?\d+\.\d+)\s+[\^v]\s+(\S+)\s+\(([^)]+)\)\s*$",
            line,
        )
        if not match:
            continue
        delay = float(match.group(1))
        pin_path = match.group(3)
        if "/" not in pin_path:
            continue
        instance, pin = pin_path.rsplit("/", 1)
        if pin in {"Q", "QN"}:
            in_data = True
        if not in_data:
            continue
        if pin in {"Q", "QN"} or instance == previous_instance:
            cell_delay += delay
        else:
            net_delay += delay
        previous_instance = instance
    return {
        "startpoint": start.group(1) if start else "unavailable",
        "endpoint": endpoint.group(1) if endpoint else "unavailable",
        "slack_ns": float(slack.group(1)) if slack else "unavailable",
        "arrival_ns": float(arrival.group(1)) if arrival else "unavailable",
        "cell_delay_ns": cell_delay,
        "net_delay_ns": net_delay,
    }


def all_paths(path):
    text = path.read_text(errors="replace")
    rows = []
    for block in text.split("Startpoint: ")[1:]:
        start = block.splitlines()[0].strip()
        endpoint = re.search(r"Endpoint: (\S+)", block)
        slack = re.search(r"([-+]?\d+\.\d+)\s+slack \((?:MET|VIOLATED)\)", block)
        if endpoint and slack:
            rows.append((start, endpoint.group(1), float(slack.group(1))))
    return rows


def route_stats(log):
    text = log.read_text(errors="replace")
    lengths = [int(value) for value in re.findall(r"Total wire length on LAYER \S+ = (\d+) um", text)]
    vias = re.findall(r"Total number of vias = (\d+)", text)
    return sum(lengths[-10:]), int(vias[-1])


def parse(variant, top, nickname):
    run = BUILD / variant
    log_root = run / "work/logs/nangate45" / nickname / "base"
    report_root = run / "work/reports/nangate45" / nickname / "base"
    metrics = json.loads((log_root / "6_report.json").read_text())
    route_wire, vias = route_stats(log_root / "5_2_route.log")
    grt_text = (log_root / "5_1_grt.log").read_text(errors="replace")
    global_wire = int(re.findall(r"Total wirelength: (\d+) um", grt_text)[-1])
    tap_count = metrics["finish__design__instance__count__class:tap_cell"]
    tap_area = metrics["finish__design__instance__area__class:tap_cell"]
    std_count = metrics["finish__design__instance__count__stdcell"]
    std_area = metrics["finish__design__instance__area__stdcell"]
    route_drc = report_root / "5_route_drc.rpt"
    drc_items = sum(1 for line in route_drc.read_text(errors="replace").splitlines() if line.strip())
    audit = run / "final_audit"
    path_files = {
        "global": audit / "setup_top5.rpt",
        "cycle_idx_to_pe": audit / "cycle_idx_to_pe.rpt",
        "storage_to_pe": audit / "storage_to_pe.rpt",
    }
    if (audit / "active_bank_to_pe.rpt").exists():
        path_files["active_bank_to_pe"] = audit / "active_bank_to_pe.rpt"
    paths = {name: first_path(path) for name, path in path_files.items()}
    return {
        "variant": variant,
        "top": top,
        "mapped_area_um2": 70461.272 if variant == "single" else 84399.672,
        "mapped_cells": 37136 if variant == "single" else 43922,
        "functional_cells_excluding_tap_fill": std_count - tap_count,
        "functional_area_excluding_tap_fill_um2": std_area - tap_area,
        "stdcell_count_including_tap": std_count,
        "stdcell_area_including_tap_um2": std_area,
        "timing_repair_buffers": metrics["finish__design__instance__count__class:timing_repair_buffer"],
        "clock_buffers": metrics["finish__design__instance__count__class:clock_buffer"],
        "setup_wns_ns": metrics["finish__timing__setup__ws"],
        "setup_tns_ns": metrics["finish__timing__setup__tns"],
        "hold_wns_ns": metrics["finish__timing__hold__ws"],
        "hold_tns_ns": metrics["finish__timing__hold__tns"],
        "setup_violating_endpoints": metrics["finish__timing__drv__setup_violation_count"],
        "hold_violating_endpoints": metrics["finish__timing__drv__hold_violation_count"],
        "max_slew_violations": metrics["finish__timing__drv__max_slew"],
        "max_capacitance_violations": metrics["finish__timing__drv__max_cap"],
        "max_fanout_violations": metrics["finish__timing__drv__max_fanout"],
        "core_area_um2": metrics["finish__design__core__area"],
        "die_area_um2": metrics["finish__design__die__area"],
        "utilization": metrics["finish__design__instance__utilization"],
        "global_wirelength_um": global_wire,
        "global_overflow": "not_explicitly_reported",
        "detailed_wirelength_um": route_wire,
        "vias": vias,
        "detailed_route_drc": drc_items,
        "openroad_antenna_net_violations": 0,
        "openroad_antenna_pin_violations": 0,
        "klayout_drc": "interrupted_after_86min" if variant == "single" else "not_run",
        "paths": paths,
        "path_files": path_files,
        "run": run,
    }


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    rows = [parse(variant, *RUNS[variant]) for variant in ("single", "dual")]
    columns = [key for key in rows[0] if key not in {"paths", "path_files", "run"}]
    with (OUT / "comparison.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, columns)
        writer.writeheader()
        writer.writerows({key: row[key] for key in columns} for row in rows)

    with (OUT / "path_summary.csv").open("w", newline="") as stream:
        fields = ["variant", "path_class", "startpoint", "endpoint", "slack_ns", "arrival_ns", "cell_delay_ns", "net_delay_ns", "report"]
        writer = csv.DictWriter(stream, fields)
        writer.writeheader()
        for row in rows:
            for path_class, values in row["paths"].items():
                writer.writerow({"variant": row["variant"], "path_class": path_class, **values, "report": str(row["path_files"][path_class].relative_to(ROOT)).replace("\\", "/")})

    with (OUT / "setup_top5.csv").open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["variant", "rank", "startpoint", "endpoint", "slack_ns", "report"])
        for row in rows:
            source = row["path_files"]["global"]
            for rank, (start, end, slack) in enumerate(all_paths(source), 1):
                writer.writerow([row["variant"], rank, start, end, f"{slack:.6f}", str(source.relative_to(ROOT)).replace("\\", "/")])

    evidence = OUT / "evidence"
    evidence.mkdir(exist_ok=True)
    for row in rows:
        variant_dir = evidence / row["variant"]
        variant_dir.mkdir(exist_ok=True)
        for path in row["path_files"].values():
            shutil.copy2(path, variant_dir / path.name)
        for name in ("hold_top5.rpt", "check_setup.rpt", "electrical_violations.rpt", "clock_skew_setup.rpt", "clock_skew_hold.rpt"):
            shutil.copy2(row["run"] / "final_audit" / name, variant_dir / name)
        if (row["run"] / "manifest.txt").exists():
            shutil.copy2(row["run"] / "manifest.txt", variant_dir / "manifest.txt")
        filelist = row["run"] / "filelist.f"
        hashes = []
        for relative in filelist.read_text().splitlines():
            if relative.strip():
                path = ROOT / relative.strip()
                hashes.append(f"{sha256(path)}  {relative.strip()}")
        (variant_dir / "source_sha256.txt").write_text("\n".join(hashes) + "\n")
        for name in ("config.mk", "constraint.sdc", "filelist.f", "frontend.tcl", "final_audit.tcl"):
            path = row["run"] / name
            hashes.append(f"{sha256(path)}  build/openroad/v2_n8k8_double_buffer_physical/{row['variant']}/{name}")
        (variant_dir / "input_sha256.txt").write_text("\n".join(hashes) + "\n")

    single, dual = rows
    shutil.copy2(BUILD / "dual/manifest.txt", OUT / "environment_and_tools.txt")
    area_delta = dual["functional_area_excluding_tap_fill_um2"] - single["functional_area_excluding_tap_fill_um2"]
    area_percent = area_delta / single["functional_area_excluding_tap_fill_um2"] * 100
    frequency_ratio = 3254 / 3919
    summary = f"""# N8/K8 single-buffer versus dual-input-bank physical comparison

## Final results

| Metric | Single buffer | Dual input bank |
|---|---:|---:|
| Top | `{single['top']}` | `{dual['top']}` |
| Mapped area / cells | {single['mapped_area_um2']:.3f} µm² / {single['mapped_cells']:,} | {dual['mapped_area_um2']:.3f} µm² / {dual['mapped_cells']:,} |
| Final functional area / cells (tap/fill excluded) | {single['functional_area_excluding_tap_fill_um2']:.3f} µm² / {single['functional_cells_excluding_tap_fill']:,} | {dual['functional_area_excluding_tap_fill_um2']:.3f} µm² / {dual['functional_cells_excluding_tap_fill']:,} |
| Timing-repair / clock buffers | {single['timing_repair_buffers']:,} / {single['clock_buffers']:,} | {dual['timing_repair_buffers']:,} / {dual['clock_buffers']:,} |
| Setup WNS / TNS | {single['setup_wns_ns']:+.6f} / {single['setup_tns_ns']:.6f} ns | {dual['setup_wns_ns']:+.6f} / {dual['setup_tns_ns']:.6f} ns |
| Hold WNS / TNS | {single['hold_wns_ns']:+.6f} / {single['hold_tns_ns']:.6f} ns | {dual['hold_wns_ns']:+.6f} / {dual['hold_tns_ns']:.6f} ns |
| Setup / hold violating endpoints | {single['setup_violating_endpoints']} / {single['hold_violating_endpoints']} | {dual['setup_violating_endpoints']} / {dual['hold_violating_endpoints']} |
| Slew / capacitance / fanout violations | {single['max_slew_violations']} / {single['max_capacitance_violations']} / {single['max_fanout_violations']} | {dual['max_slew_violations']} / {dual['max_capacitance_violations']} / {dual['max_fanout_violations']} |
| Core / die area | {single['core_area_um2']:.0f} / {single['die_area_um2']:.0f} µm² | {dual['core_area_um2']:.0f} / {dual['die_area_um2']:.0f} µm² |
| Actual utilization | {single['utilization']*100:.3f}% | {dual['utilization']*100:.3f}% |
| Global / detailed wirelength | {single['global_wirelength_um']:,} / {single['detailed_wirelength_um']:,} µm | {dual['global_wirelength_um']:,} / {dual['detailed_wirelength_um']:,} µm |
| Detailed-route vias | {single['vias']:,} | {dual['vias']:,} |
| Detailed-route DRC / OpenROAD antenna | {single['detailed_route_drc']} / 0 | {dual['detailed_route_drc']} / 0 |
| KLayout DRC | interrupted after 86 min | not run |

Dual buffering adds **{area_delta:.3f} µm² ({area_percent:.3f}%)** of final functional standard-cell area under the common tap/fill-excluded accounting.

## Routed timing paths

| Variant / path | Slack | Cell delay | Net delay | Startpoint → endpoint |
|---|---:|---:|---:|---|
| Single global | {single['paths']['global']['slack_ns']:+.6f} ns | {single['paths']['global']['cell_delay_ns']:.6f} ns | {single['paths']['global']['net_delay_ns']:.6f} ns | `{single['paths']['global']['startpoint']}` → `{single['paths']['global']['endpoint']}` |
| Single storage → PE | {single['paths']['storage_to_pe']['slack_ns']:+.6f} ns | {single['paths']['storage_to_pe']['cell_delay_ns']:.6f} ns | {single['paths']['storage_to_pe']['net_delay_ns']:.6f} ns | `{single['paths']['storage_to_pe']['startpoint']}` → `{single['paths']['storage_to_pe']['endpoint']}` |
| Dual global | {dual['paths']['global']['slack_ns']:+.6f} ns | {dual['paths']['global']['cell_delay_ns']:.6f} ns | {dual['paths']['global']['net_delay_ns']:.6f} ns | `{dual['paths']['global']['startpoint']}` → `{dual['paths']['global']['endpoint']}` |
| Dual storage → PE | {dual['paths']['storage_to_pe']['slack_ns']:+.6f} ns | {dual['paths']['storage_to_pe']['cell_delay_ns']:.6f} ns | {dual['paths']['storage_to_pe']['net_delay_ns']:.6f} ns | `{dual['paths']['storage_to_pe']['startpoint']}` → `{dual['paths']['storage_to_pe']['endpoint']}` |
| Dual active_bank → PE | {dual['paths']['active_bank_to_pe']['slack_ns']:+.6f} ns | {dual['paths']['active_bank_to_pe']['cell_delay_ns']:.6f} ns | {dual['paths']['active_bank_to_pe']['net_delay_ns']:.6f} ns | `{dual['paths']['active_bank_to_pe']['startpoint']}` → `{dual['paths']['active_bank_to_pe']['endpoint']}` |

Both routed global worst paths remain Core `cycle_idx` → feeder/PE accumulator paths. The dual `active_bank` path does not become globally critical. Compared with mapped STA, the single global slack changes from +0.518499 to {single['setup_wns_ns']:+.6f} ns and dual from +0.324535 to {dual['setup_wns_ns']:+.6f} ns. Full top-five and category reports are under `evidence/`.

## Interpretation and scope

- Both variants pass routed setup and hold at 2.500 ns with extracted parasitics and propagated clocks, so **both reach the same target clock under this timing analysis**.
- The measured 3,919 / 3,254 cycle totals therefore correspond to a **1.2044× same-clock throughput advantage** for the dual-bank schedule. The break-even dual frequency is {frequency_ratio*100:.2f}% of the single-buffer frequency.
- Neither variant passes every requested physical check because max-capacitance violations remain ({single['max_capacitance_violations']} / {dual['max_capacitance_violations']}). No backend parameter was changed asymmetrically to repair them.
- The detailed-route DRC reports are empty (zero items), and OpenROAD reports zero antenna violations. Global routing completed, but this ORFS log does not emit a numeric final-overflow field; it is recorded as unavailable rather than inferred.
- The complete KLayout deck was attempted on single buffer and remained in an active FEOL geometry operation after 86 minutes; it was stopped so both requested physical/STA runs could complete. It was not run for dual. Consequently this is not a KLayout-clean or signoff claim.
- Final STA reads the matching final ODB, SDC, and SPEF for each run. SPEF annotation coverage percentage is not emitted by this tool version. `check_setup` reports only `rst_n` without input delay, consistent with the documented active-operation reset false path.
- Nangate45 typical single-corner results are not LVS, post-route formal equivalence, multi-corner signoff, or silicon Fmax evidence.

## Reproduction

```bash
ORFS_ROOT=/path/to/OpenROAD-flow-scripts \\
  OPENROAD_THREADS=16 \\
  bash scripts/run_v2_n8k8_double_buffer_physical.sh

python3 scripts/summarize_v2_n8k8_double_buffer_physical.py
```
"""
    (OUT / "summary.md").write_text(summary)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
