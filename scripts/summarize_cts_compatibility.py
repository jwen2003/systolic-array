#!/usr/bin/env python3
"""Summarize immutable-image CTS compatibility evidence."""

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "openroad" / "compatibility"


def text(path: Path) -> str:
    if not path.is_file():
        raise SystemExit(f"missing evidence: {path}")
    return path.read_text(encoding="utf-8", errors="replace")


def exit_code(path: Path) -> int:
    return int(text(path).strip())


def tool_versions(system_log: Path) -> dict[str, str]:
    data = text(system_log)
    section = data.split("\nTOOLS\n", maxsplit=1)
    if len(section) != 2:
        raise SystemExit(f"tool versions not found: {system_log}")
    tool_text = section[1]
    openroad = re.search(r"^(26Q\d[^\n]*)$", tool_text, re.M)
    yosys = re.search(r"^(Yosys [^\n]*)$", tool_text, re.M)
    opensta = re.search(r"^(\d+\.\d+\.\d+)$", tool_text, re.M)
    if not all((openroad, yosys, opensta)):
        raise SystemExit(f"one or more tool versions not found: {system_log}")
    return {
        "openroad": openroad.group(1).strip(),
        "yosys": yosys.group(1).strip(),
        "opensta": opensta.group(1).strip(),
    }


def image_metadata(path: Path) -> dict[str, object]:
    record = json.loads(text(path))[0]
    return {
        "image_id": record["Id"],
        "repo_digests": record.get("RepoDigests", []),
        "created": record["Created"],
        "architecture": record["Architecture"],
        "os": record["Os"],
    }


baseline_digest = "sha256:d995618be9f2bcdfa5538b885123463070dfbf178bea1818716d4652fe0fa380"
candidates = [
    {
        "name": "candidate_1_exact_orfs_commit",
        "tag": "26Q3-345-g6101364b2",
        "digest": "sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0",
        "directory": "candidate_1",
        "basis": "official image tag exactly matches git describe of the fixed ORFS commit",
    },
    {
        "name": "candidate_2_pre_kepler_update",
        "tag": "26Q3-266-g1a48ddd62",
        "digest": "sha256:2e22028b36fd7a1cc6952f0f864527b88e42577acb1068fa0e34d373e61dec47",
        "directory": "candidate_2",
        "basis": "nearest official 26Q3 image before the 2026-08-06 Kepler update",
    },
]

records = [
    {
        "name": "failed_latest_baseline",
        "repository": "openroad/orfs",
        "tag_used_for_probe": "latest",
        "digest": baseline_digest,
        "tool_versions": tool_versions(BUILD / "failed_digest/system/container_system.txt"),
        "official_design": "nangate45/gcd",
        "official_design_cts_pass": False,
        "official_design_exit_code": exit_code(
            BUILD / "failed_digest/official_gcd_cts/docker.exitcode"
        ),
        "systolic_cts_pass": False,
        "systolic_thread_counts_tested": [16, 1],
        "failure_command": (
            "/OpenROAD-flow-scripts/tools/install/kepler-formal/bin/kepler-formal "
            "--config <objects>/4_rsz_lec_test.yml"
        ),
        "signal": "SIGILL",
        "direct_process_exit_code": 132,
        "flow_exit_code": 2,
        "final_disposition": "rejected: Kepler Formal is incompatible with host CPU",
    }
]

for candidate in candidates:
    base = BUILD / candidate["directory"]
    records.append(
        {
            "name": candidate["name"],
            "repository": "openroad/orfs",
            "tag": candidate["tag"],
            "digest": candidate["digest"],
            "selection_basis": candidate["basis"],
            "image": image_metadata(base / "image_inspect.json"),
            "tool_versions": tool_versions(base / "system/container_system.txt"),
            "official_design": "nangate45/gcd",
            "official_design_cts_pass": False,
            "official_design_exit_code": exit_code(
                base / "official_gcd_cts/docker.exitcode"
            ),
            "systolic_cts_pass": None,
            "systolic_status": "not run because official design gate failed",
            "failure_command": (
                "/OpenROAD-flow-scripts/tools/install/kepler-formal/bin/kepler-formal "
                "--config <objects>/4_rsz_lec_test.yml"
            ),
            "signal": "SIGILL",
            "direct_process_exit_code": 132,
            "flow_exit_code": 2,
            "thread_count": 16,
            "final_disposition": "rejected at official-design CTS gate",
        }
    )

summary = {
    "orfs_commit": "6101364b2d7909dd797e1e3e7f80695401cfa4e4",
    "orfs_git_describe": "26Q3-345-g6101364b2",
    "host_cpu": "AMD Ryzen 7 7730U",
    "host_cpu_has_avx2": True,
    "host_cpu_has_avx512": False,
    "root_cause_scope": "Kepler Formal subprocess startup, after CTS repair_timing",
    "compatible_image_found": False,
    "images": records,
    "next_step": (
        "build an x86-64-v3-or-lower compatible official tool image or submit the "
        "GCD/kepler --help minimal reproducer to the OpenROAD project"
    ),
}

output = BUILD / "compatibility_summary.json"
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
print(output)
