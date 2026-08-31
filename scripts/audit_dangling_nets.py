#!/usr/bin/env python3
"""Classify OpenROAD RSZ-0104 one-pin nets against the final Verilog netlist."""

import argparse
import json
import re
from collections import Counter
from pathlib import Path


WARNING_RE = re.compile(r"\[WARNING RSZ-0104\] Net (\S+) only has one pin")
CELL_RE = re.compile(r"^\s*(\S+)\s+(\\\S+|\S+)\s*\((.*?)\);", re.MULTILINE | re.DOTALL)
PIN_RE = re.compile(r"\.(\w+)\(([^()]+)\)")


def normalize_net(value: str) -> str:
    return value.strip().rstrip()


def classify(instance: str, cell_type: str, pin: str) -> str:
    name = instance.lower()
    if pin == "QN" and "psum_out" in name:
        return "unused_complementary_accumulator_output"
    if pin == "QN" and ("a_valid_out" in name or "b_valid_out" in name):
        return "unused_complementary_valid_forwarding_output"
    if pin == "QN" and ("a_out[" in name or "b_out[" in name):
        return "unused_complementary_ab_forwarding_output"
    if pin == "QN" and "u_controller" in name:
        return "unused_complementary_controller_output"
    if cell_type == "HA_X1" and pin == "S":
        return "unused_arithmetic_intermediate_output"
    if "clk" in name or cell_type.startswith("CLK"):
        return "clock_related"
    if "rst" in name or "reset" in name:
        return "reset_related"
    if cell_type.startswith(("FILL", "TAP", "TIE", "DECAP")):
        return "physical_only"
    return "other_unclassified"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", required=True, type=Path)
    parser.add_argument("--netlist", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    warnings = WARNING_RE.findall(args.log.read_text(errors="replace"))
    warning_nets = list(dict.fromkeys(warnings))
    if len(warnings) != 92 or len(warning_nets) != 92:
        raise SystemExit(f"expected 92 unique RSZ-0104 nets, got {len(warnings)} warnings and {len(warning_nets)} unique nets")

    netlist = args.netlist.read_text(errors="replace")
    connections = {net: [] for net in warning_nets}
    for match in CELL_RE.finditer(netlist):
        cell_type, instance, body = match.groups()
        for pin, value in PIN_RE.findall(body):
            net = normalize_net(value)
            if net in connections:
                connections[net].append({"cell_type": cell_type, "instance": instance, "pin": pin})

    entries = []
    failures = []
    counts = Counter()
    for net in warning_nets:
        pins = connections[net]
        if len(pins) != 1:
            failures.append(f"{net}: expected exactly one netlist pin, found {len(pins)}")
            category = "other_unclassified"
        else:
            category = classify(pins[0]["instance"], pins[0]["cell_type"], pins[0]["pin"])
        counts[category] += 1
        entries.append({"net": net, "category": category, "connections": pins})

    recognized_benign = {
        "unused_complementary_accumulator_output",
        "unused_complementary_valid_forwarding_output",
        "unused_complementary_ab_forwarding_output",
        "unused_complementary_controller_output",
        "unused_arithmetic_intermediate_output",
        "physical_only",
    }
    summary = {
        "source_warning": "RSZ-0104",
        "warning_count": len(warnings),
        "unique_net_count": len(warning_nets),
        "classification_counts": dict(sorted(counts.items())),
        "functional_critical_dangling_found": any(category not in recognized_benign for category in counts),
        "classification_basis": "unique connected cell pin and hierarchical instance name in 6_final.v",
        "entries": entries,
        "failures": failures,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps({key: summary[key] for key in summary if key not in {"entries"}}, indent=2))
    return 1 if failures or summary["functional_critical_dangling_found"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
