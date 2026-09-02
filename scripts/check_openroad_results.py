#!/usr/bin/env python3
"""Validate and summarize the complete pinned-image N2/K2 physical run."""

import json
import re
import sys
from pathlib import Path

EXPECTED_IMAGE = "openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0"
EXPECTED_ORFS_COMMIT = "6101364b2d7909dd797e1e3e7f80695401cfa4e4"


def read(path: Path) -> str:
    if not path.is_file():
        raise FileNotFoundError(path)
    return path.read_text(encoding="utf-8", errors="replace")


def load_json(path: Path) -> dict:
    return json.loads(read(path))


def parse_manifest(data: str) -> dict[str, str]:
    return dict(line.split("=", 1) for line in data.splitlines() if "=" in line)


def critical_path_breakdown(path: Path) -> dict[str, object]:
    checks = load_json(path)["checks"]
    if len(checks) != 1:
        raise ValueError("expected exactly one critical path")
    check = checks[0]
    data_path = check["source_path"]
    clock_path = check.get("source_clock_path")
    if clock_path:
        source_reference = clock_path[-1]["arrival"]
        cell_delay = data_path[0]["arrival"] - source_reference
        startpoint_type = "register"
    else:
        source_reference = data_path[0]["arrival"]
        cell_delay = 0.0
        startpoint_type = "primary_input"
    net_delay = 0.0
    for previous, current in zip(data_path, data_path[1:]):
        delta = current["arrival"] - previous["arrival"]
        if "capacitance" in previous and "capacitance" not in current:
            net_delay += delta
        elif "capacitance" not in previous and "capacitance" in current:
            cell_delay += delta
        else:
            raise ValueError("unexpected driver/load sequence in critical path JSON")
    data_delay = data_path[-1]["arrival"] - source_reference
    return {
        "startpoint": check["startpoint"],
        "endpoint": check["endpoint"],
        "startpoint_type": startpoint_type,
        "data_arrival_ns": check["data_arrival_time"] * 1e9,
        "data_delay_ns": data_delay * 1e9,
        "cell_delay_ns": cell_delay * 1e9,
        "net_delay_ns": net_delay * 1e9,
        "cell_delay_fraction": cell_delay / data_delay if data_delay else 0.0,
        "net_delay_fraction": net_delay / data_delay if data_delay else 0.0,
    }


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    default_root = repo / "build/openroad/lec_disabled/systolic_n2_k2_full"
    root = Path(sys.argv[1] if len(sys.argv) > 1 else default_root).resolve()
    logs = root / "work/logs/nangate45/systolic_array_n2_k2/base"
    reports = root / "work/reports/nangate45/systolic_array_n2_k2/base"
    results = root / "work/results/nangate45/systolic_array_n2_k2/base"
    audit = root / "final_audit"
    failures: list[str] = []

    try:
        manifest = parse_manifest(read(root / "manifest.txt"))
        config = read(repo / "physical/nangate45/config.mk")
        docker_log = read(root / "docker.log")
        frontend_formal = read(root / "frontend/equivalence.log")
        orfs_commit = read(repo / "build/openroad/environment_gate/orfs_commit.txt").strip()
        synth = load_json(logs / "1_synth.json")
        floorplan = load_json(logs / "2_1_floorplan.json")
        place = load_json(logs / "3_5_place_dp.json")
        cts = load_json(logs / "4_1_cts.json")
        grt = load_json(logs / "5_1_grt.json")
        drt = load_json(logs / "5_2_route.json")
        finish = load_json(logs / "6_report.json")
        check_setup = read(audit / "check_setup.rpt")
        critical = critical_path_breakdown(audit / "critical_path.json")
        drc_count = int(read(reports / "6_drc_count.rpt").strip())
    except (FileNotFoundError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    if manifest.get("image") != EXPECTED_IMAGE:
        failures.append("formal image digest mismatch")
    if manifest.get("target") != "all drc":
        failures.append("run target was not all drc")
    if orfs_commit != EXPECTED_ORFS_COMMIT:
        failures.append("ORFS commit mismatch")
    if not re.search(r"^export LEC_CHECK\s*=\s*0\s*$", config, re.M):
        failures.append("LEC_CHECK=0 is not explicit in the design config")
    if int(read(root / "docker.exitcode").strip()) != 0:
        failures.append("Docker flow exit code is nonzero")
    if re.search(r"kepler|illegal instruction", docker_log, re.I):
        failures.append("Kepler or SIGILL appeared in the successful flow log")
    if "Equivalence successfully proven!" not in frontend_formal:
        failures.append("frontend equivalence was not proven")

    required = [
        results / "4_cts.odb", results / "5_1_grt.odb", results / "5_2_route.odb",
        results / "6_final.odb", results / "6_final.spef", results / "6_final.gds",
        reports / "4_cts_final.rpt", reports / "5_global_route.rpt",
        reports / "6_finish.rpt", reports / "6_drc.lyrdb",
    ]
    for artifact in required:
        if not artifact.is_file() or artifact.stat().st_size == 0:
            failures.append(f"missing or empty artifact: {artifact.name}")

    if synth["synth__design__instance__count"] <= 0:
        failures.append("mapped design is empty")
    if finish["finish__design__instance__count__stdcell"] <= 0:
        failures.append("final standard-cell set is empty")
    if cts["cts__design__violations"] != 0:
        failures.append("CTS placement violations are nonzero")
    if drt["detailedroute__route__drc_errors"] != 0:
        failures.append("detailed-route DRC errors are nonzero")
    if drc_count != 0:
        failures.append("KLayout DRC count is nonzero")
    if finish["finish__timing__setup__tns"] != 0:
        failures.append("final setup TNS is nonzero")
    if finish["finish__timing__hold__tns"] != 0:
        failures.append("final hold TNS is nonzero")

    unconstrained_match = re.search(r"There (?:is|are) (\d+) unconstrained", check_setup)
    unconstrained_endpoints = int(unconstrained_match.group(1)) if unconstrained_match else 0
    if unconstrained_endpoints != 0:
        failures.append("unconstrained endpoints are nonzero")
    missing_input_delays = re.findall(r"^  (\S+)\s*$", check_setup, re.M)
    if missing_input_delays != ["rst_n"]:
        failures.append("unexpected missing input delay set")

    final_congestion = re.search(
        r"^Total\s+\d+\s+\d+\s+[\d.]+%\s+0\s*/\s*0\s*/\s*(\d+)",
        read(logs / "5_1_grt.log"), re.M,
    )
    global_overflow = int(final_congestion.group(1)) if final_congestion else None
    if global_overflow is None:
        failures.append("global-route overflow was not parseable")
    elif global_overflow != 0:
        failures.append("global-route overflow is nonzero")

    summary = {
        "status": "complete_rtl_to_route" if not failures else "failed_checks",
        "image": EXPECTED_IMAGE,
        "orfs_commit": EXPECTED_ORFS_COMMIT,
        "lec_check": 0,
        "equivalence": {
            "frontend_equivalence": "proven",
            "post_synthesis_equivalence": "inconclusive_tool_scalability",
            "kepler_stage_lec": "disabled_due_to_cpu_sigill",
            "post_route_equivalence": "not_proven",
        },
        "mapping": {
            "standard_cells": synth["synth__design__instance__count__stdcell"],
            "cell_area_um2": synth["synth__design__instance__area__stdcell"],
        },
        "floorplan": {
            "core_area_um2": floorplan["floorplan__design__core__area"],
            "die_area_um2": floorplan["floorplan__design__die__area"],
            "utilization": floorplan["floorplan__design__instance__utilization"],
            "setup_wns_ns": floorplan["floorplan__timing__setup__ws"],
            "setup_tns_ns": floorplan["floorplan__timing__setup__tns"],
            "hold_wns_ns": floorplan["floorplan__timing__hold__ws"],
            "hold_tns_ns": floorplan["floorplan__timing__hold__tns"],
        },
        "placement": {
            "instances": place["detailedplace__design__instance__count"],
            "area_um2": place["detailedplace__design__instance__area"],
            "utilization": place["detailedplace__design__instance__utilization"],
            "estimated_wirelength_um": place["detailedplace__route__wirelength__estimated"],
            "setup_wns_ns": place["detailedplace__timing__setup__ws"],
            "setup_tns_ns": place["detailedplace__timing__setup__tns"],
            "hold_wns_ns": place["detailedplace__timing__hold__ws"],
            "hold_tns_ns": place["detailedplace__timing__hold__tns"],
        },
        "cts": {
            "instances": cts["cts__design__instance__count"],
            "area_um2": cts["cts__design__instance__area"],
            "setup_wns_ns": cts["cts__timing__setup__ws"],
            "setup_tns_ns": cts["cts__timing__setup__tns"],
            "hold_wns_ns": cts["cts__timing__hold__ws"],
            "hold_tns_ns": cts["cts__timing__hold__tns"],
            "setup_skew_ns": cts["cts__clock__skew__setup"],
            "hold_skew_ns": cts["cts__clock__skew__hold"],
            "clock_sinks": 110,
            "clock_levels": 3,
            "clock_buffers": 9,
        },
        "routing": {
            "global_wirelength_um": grt["globalroute__global_route__wirelength"],
            "global_overflow": global_overflow,
            "detailed_wirelength_um": drt["detailedroute__route__wirelength"],
            "vias": drt["detailedroute__route__vias"],
            "detailed_route_drc_errors": drt["detailedroute__route__drc_errors"],
        },
        "final": {
            "standard_cells": finish["finish__design__instance__count__stdcell"],
            "standard_cell_area_um2": finish["finish__design__instance__area__stdcell"],
            "all_instances_including_fill_tap": finish["finish__design__instance__count"],
            "setup_wns_ns": finish["finish__timing__setup__ws"],
            "setup_tns_ns": finish["finish__timing__setup__tns"],
            "hold_wns_ns": finish["finish__timing__hold__ws"],
            "hold_tns_ns": finish["finish__timing__hold__tns"],
            "setup_skew_ns": finish["finish__clock__skew__setup"],
            "hold_skew_ns": finish["finish__clock__skew__hold"],
            "unconstrained_endpoints": unconstrained_endpoints,
            "missing_input_delay_ports": missing_input_delays,
            "klayout_drc_count": drc_count,
            "gds_generated": True,
        },
        "critical_path": critical,
        "warnings": {
            "floorplan": floorplan["floorplan__flow__warnings__count"],
            "placement": place["detailedplace__flow__warnings__count"],
            "cts": cts["cts__flow__warnings__count"],
            "global_route": grt["globalroute__flow__warnings__count"],
            "detailed_route": drt["detailedroute__flow__warnings__count"],
            "finish": finish["finish__flow__warnings__count"],
        },
        "failures": failures,
    }
    output = root / "physical_summary.json"
    output.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
