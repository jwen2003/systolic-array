#!/usr/bin/env python3
"""Validate and summarize one pinned N2/K2 clock-sweep flow."""

import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path

from check_openroad_results import critical_path_breakdown, load_json, read

EXPECTED_IMAGE = "openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0"
EXPECTED_ORFS = "6101364b2d7909dd797e1e3e7f80695401cfa4e4"
KNOWN_WARNING_CODES = {"IFP-0028", "EST-0027", "PDN-1051", "RSZ-0062", "RSZ-0104", "GRT-0246", "RCX-0514", "GUI-0076"}


def manifest(path: Path) -> dict[str, str]:
    return dict(line.split("=", 1) for line in read(path).splitlines() if "=" in line)


def intval(value: object) -> int:
    if isinstance(value, str):
        return int(value, 2)
    return int(value)


def frontend_structure(path: Path) -> dict[str, int]:
    design = load_json(path)
    top = design["modules"]["systolic_array_top"]
    cells = top["cells"]
    types = Counter(cell["type"] for cell in cells.values())
    register_bits = sum(
        intval(cell["parameters"]["WIDTH"])
        for cell in cells.values()
        if re.match(r"^\$(?:s?dff|s?dffe)", cell["type"])
    )
    accumulators = sum(
        1 for cell in cells.values()
        if cell["type"] == "$add"
        and all(intval(cell["parameters"][key]) == 18 for key in ("A_WIDTH", "B_WIDTH", "Y_WIDTH"))
    )
    return {"multipliers": types["$mul"], "accumulator_adders": accumulators, "register_bits": register_bits}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("run_root", type=Path)
    args = parser.parse_args()
    root = args.run_root.resolve()
    logs = root / "work/logs/nangate45/systolic_array_n2_k2/base"
    reports = root / "work/reports/nangate45/systolic_array_n2_k2/base"
    results = root / "work/results/nangate45/systolic_array_n2_k2/base"
    audit = root / "final_audit"
    failures: list[str] = []

    try:
        meta = manifest(root / "manifest.txt")
        synth = load_json(logs / "1_synth.json")
        floorplan = load_json(logs / "2_1_floorplan.json")
        place = load_json(logs / "3_5_place_dp.json")
        cts = load_json(logs / "4_1_cts.json")
        grt = load_json(logs / "5_1_grt.json")
        drt = load_json(logs / "5_2_route.json")
        finish = load_json(logs / "6_report.json")
        critical = critical_path_breakdown(audit / "critical_path.json")
        setup_report = read(audit / "check_setup.rpt")
        drc_count = int(read(reports / "6_drc_count.rpt").strip())
        structure = frontend_structure(root / "frontend/post_proc.json")
        docker_log = read(root / "docker.log")
        cts_log = read(logs / "4_1_cts.log")
    except (FileNotFoundError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}")
        return 2

    for key, expected in (("image", EXPECTED_IMAGE), ("orfs_commit", EXPECTED_ORFS), ("lec_check", "0")):
        if meta.get(key) != expected:
            failures.append(f"{key} mismatch")
    constraint = root / "constraint.sdc"
    if hashlib.sha256(constraint.read_bytes()).hexdigest() != meta.get("constraint_sha256"):
        failures.append("constraint hash mismatch")
    if f"-period {meta['clock_period_ns']}" not in read(constraint):
        failures.append("generated SDC period mismatch")
    if "Equivalence successfully proven!" not in read(root / "frontend/equivalence.log"):
        failures.append("frontend equivalence not proven")
    if re.search(r"kepler|illegal instruction", docker_log, re.I):
        failures.append("Kepler/SIGILL present")
    warning_codes = sorted(set(re.findall(r"\[WARNING ([A-Z]+-\d+)\]", docker_log)))
    unknown_warning_codes = sorted(set(warning_codes) - KNOWN_WARNING_CODES)
    error_codes = sorted(set(re.findall(r"\[ERROR ([A-Z]+-\d+)\]", docker_log)))
    if unknown_warning_codes:
        failures.append(f"unclassified warning codes: {unknown_warning_codes}")
    if error_codes:
        failures.append(f"tool error codes: {error_codes}")

    required = [results / name for name in ("4_cts.odb", "5_1_grt.odb", "5_2_route.odb", "6_final.odb", "6_final.spef", "6_final.gds")]
    for path in required:
        if not path.is_file() or path.stat().st_size == 0:
            failures.append(f"missing artifact {path.name}")
    unconstrained = re.search(r"There (?:is|are) (\d+) unconstrained", setup_report)
    unconstrained_count = int(unconstrained.group(1)) if unconstrained else 0
    missing_delays = re.findall(r"^  (\S+)\s*$", setup_report, re.M)
    if unconstrained_count or missing_delays != ["rst_n"]:
        failures.append("unexpected unconstrained/missing-delay endpoints")
    congestion = re.search(r"^Total\s+\d+\s+\d+\s+[\d.]+%\s+0\s*/\s*0\s*/\s*(\d+)", read(logs / "5_1_grt.log"), re.M)
    overflow = int(congestion.group(1)) if congestion else None
    if overflow is None:
        failures.append("global overflow not parseable")

    physical_ok = drt["detailedroute__route__drc_errors"] == 0 and drc_count == 0 and overflow == 0
    timing_met = finish["finish__timing__setup__tns"] == 0 and finish["finish__timing__hold__tns"] == 0
    if not physical_ok:
        failures.append("physical checks failed")
    status = "infrastructure_or_tool_failure" if failures else ("flow_completed_timing_met" if timing_met else "flow_completed_timing_violated")
    warning_counts = {stage: data.get(f"{prefix}__flow__warnings__count", 0) for stage, data, prefix in (
        ("synthesis", synth, "synth"), ("floorplan", floorplan, "floorplan"),
        ("placement", place, "detailedplace"), ("cts", cts, "cts"),
        ("global_route", grt, "globalroute"), ("detailed_route", drt, "detailedroute"),
        ("finish", finish, "finish"))}
    summary = {
        "configuration": {key: meta[key] for key in ("name", "clock_period_ns", "nominal_frequency_mhz", "N", "K", "DATA_W", "ACC_W")},
        "traceability": {key: meta[key] for key in ("git_commit", "git_dirty", "git_status_porcelain", "orfs_commit", "image", "image_id", "openroad_version", "yosys_version", "opensta_version", "constraint_sha256")},
        "equivalence": {"frontend": "proven", "post_synthesis": "inconclusive_tool_scalability", "kepler_stage_lec": "disabled_due_to_cpu_sigill", "post_route": "not_proven"},
        "mapping": {"standard_cells": synth["synth__design__instance__count__stdcell"], "library_cell_area_um2": synth["synth__design__instance__area__stdcell"], **structure},
        "floorplan": {"core_area_um2": floorplan["floorplan__design__core__area"], "die_area_um2": floorplan["floorplan__design__die__area"]},
        "placement": {"instances": place["detailedplace__design__instance__count"], "design_area_um2": place["detailedplace__design__instance__area"], "utilization": place["detailedplace__design__instance__utilization"], "estimated_wirelength_um": place["detailedplace__route__wirelength__estimated"], "violations": place["detailedplace__design__violations"]},
        "cts": {"instances": cts["cts__design__instance__count"], "area_um2": cts["cts__design__instance__area"], "setup_skew_ns": cts["cts__clock__skew__setup"], "hold_skew_ns": cts["cts__clock__skew__hold"], "clock_sinks": int(re.search(r"Total number of sinks: (\d+)", cts_log).group(1)), "clock_levels": int(re.search(r"Maximum number of buffers in the clock path: (\d+)", cts_log).group(1)) + 1, "created_clock_buffers": int(re.search(r"Created (\d+) clock buffers", cts_log).group(1)), "reported_setup_fix_buffers": cts["cts__design__instance__count__setup_buffer"], "reported_hold_fix_buffers": cts["cts__design__instance__count__hold_buffer"], "cell_growth_from_placement": cts["cts__design__instance__count"] - place["detailedplace__design__instance__count"]},
        "routing": {"global_wirelength_um": grt["globalroute__global_route__wirelength"], "global_overflow": overflow, "detailed_wirelength_um": drt["detailedroute__route__wirelength"], "vias": drt["detailedroute__route__vias"], "detailed_route_drc": drt["detailedroute__route__drc_errors"], "klayout_drc": drc_count, "antenna_violating_nets": drt["detailedroute__antenna__violating__nets"], "antenna_violating_pins": drt["detailedroute__antenna__violating__pins"], "gds_generated": (results / "6_final.gds").is_file()},
        "final": {"functional_standard_cells": finish["finish__design__instance__count__stdcell"], "functional_standard_cell_area_um2": finish["finish__design__instance__area__stdcell"], "all_instances_including_tap_fill": finish["finish__design__instance__count"], "timing_repair_buffers": finish["finish__design__instance__count__class:timing_repair_buffer"], "clock_buffers": finish["finish__design__instance__count__class:clock_buffer"], "clock_inverters": finish["finish__design__instance__count__class:clock_inverter"], "setup_wns_ns": finish["finish__timing__setup__ws"], "setup_tns_ns": finish["finish__timing__setup__tns"], "hold_wns_ns": finish["finish__timing__hold__ws"], "hold_tns_ns": finish["finish__timing__hold__tns"], "unconstrained_endpoints": unconstrained_count, "violating_setup_endpoints": finish["finish__timing__drv__setup_violation_count"], "violating_hold_endpoints": finish["finish__timing__drv__hold_violation_count"]},
        "critical_path": critical,
        "warnings": {"stage_counts": warning_counts, "codes": warning_codes, "unclassified_codes": unknown_warning_codes},
        "errors": {"codes": error_codes},
        "status": {"flow_status": status, "timing_met": timing_met, "physical_checks_passed": physical_ok, "comparable": not failures},
        "failures": failures,
    }
    startpoint = critical["startpoint"]
    if startpoint.startswith(("a_matrix[", "b_matrix[")):
        summary["critical_path"]["major_logic_stages"] = "matrix input -> feeder/control -> boundary PE accumulator"
    elif "cycle_idx" in startpoint:
        summary["critical_path"]["major_logic_stages"] = "cycle_idx -> feeder/control -> boundary PE accumulator"
    else:
        summary["critical_path"]["major_logic_stages"] = "other_unclassified"
        summary["failures"].append("critical path stage classification failed")
        summary["status"]["flow_status"] = "infrastructure_or_tool_failure"
        summary["status"]["comparable"] = False
    (root / "clock_sweep_result.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
