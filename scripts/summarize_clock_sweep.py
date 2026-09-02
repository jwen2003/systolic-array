#!/usr/bin/env python3
"""Aggregate validated clock-sweep JSON results into JSON and TSV."""

import csv
import json
from pathlib import Path


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    build = repo / "build/openroad/clock_sweep"
    configs = list(csv.DictReader((repo / "physical/nangate45/clock_sweep.tsv").open(), delimiter="\t"))
    results = []
    for config in configs:
        path = build / config["name"] / "clock_sweep_result.json"
        result = json.loads(path.read_text())
        if result["status"]["comparable"] is not True or result["failures"]:
            raise SystemExit(f"invalid result: {config['name']}")
        if result["configuration"] != {key: config[key] for key in result["configuration"]}:
            raise SystemExit(f"configuration mismatch: {config['name']}")
        results.append(result)

    baseline = results[0]
    expected = {"setup_wns_ns": 0.72001, "hold_wns_ns": 0.0650233,
                "functional_standard_cells": 2068, "functional_standard_cell_area_um2": 3522.64}
    baseline_matches = all(baseline["final"][key] == value for key, value in expected.items())
    if not baseline_matches:
        raise SystemExit("fresh 400 MHz baseline does not reproduce committed metrics")

    summary = {
        "experiment": "N2/K2 post-route clock sweep",
        "baseline_reproduced": baseline_matches,
        "all_flows_completed": len(results) == 5,
        "highest_tested_timing_met_mhz": max(float(r["configuration"]["nominal_frequency_mhz"]) for r in results if r["status"]["timing_met"]),
        "first_tested_timing_failure_mhz": next((float(r["configuration"]["nominal_frequency_mhz"]) for r in results if not r["status"]["timing_met"]), None),
        "results": results,
    }
    (build / "clock_sweep_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    columns = ["name", "period_ns", "frequency_mhz", "status", "setup_wns_ns", "setup_tns_ns", "hold_wns_ns", "hold_tns_ns", "mapped_cells", "mapped_area_um2", "placement_cells", "placement_area_um2", "cts_cells", "final_cells", "final_area_um2", "timing_repair_buffers", "final_clock_buffers", "global_wirelength_um", "global_overflow", "detailed_wirelength_um", "vias", "detailed_drc", "klayout_drc", "critical_startpoint", "critical_endpoint", "data_delay_ns", "cell_delay_fraction", "net_delay_fraction"]
    with (build / "clock_sweep_summary.tsv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=columns, delimiter="\t")
        writer.writeheader()
        for r in results:
            c, m, p, cts, route, f, cp = r["configuration"], r["mapping"], r["placement"], r["cts"], r["routing"], r["final"], r["critical_path"]
            writer.writerow(dict(zip(columns, [c["name"], c["clock_period_ns"], c["nominal_frequency_mhz"], r["status"]["flow_status"], f["setup_wns_ns"], f["setup_tns_ns"], f["hold_wns_ns"], f["hold_tns_ns"], m["standard_cells"], m["library_cell_area_um2"], p["instances"], p["design_area_um2"], cts["instances"], f["functional_standard_cells"], f["functional_standard_cell_area_um2"], f["timing_repair_buffers"], f["clock_buffers"], route["global_wirelength_um"], route["global_overflow"], route["detailed_wirelength_um"], route["vias"], route["detailed_route_drc"], route["klayout_drc"], cp["startpoint"], cp["endpoint"], cp["data_delay_ns"], cp["cell_delay_fraction"], cp["net_delay_fraction"]])))
    print(json.dumps({key: value for key, value in summary.items() if key != "results"}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
