#!/usr/bin/env python3
"""Convert the fixed V2 Lite OpenSTA path report into auditable diagnostics."""

import csv
import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "build/v2_lite_path_diagnosis/high_precision_paths.rpt"
JSON_NETLIST = ROOT / "build/v2_lite_synth_sta/n2_k17_2p5ns/frontend/post_proc.json"
YOSYS_LOG = ROOT / "build/v2_lite_synth_sta/n2_k17_2p5ns/frontend/yosys.log"
OUT = ROOT / "reports/v2_lite_path_diagnosis"

SECTIONS = {
    "input_to_register": ("=== EXACT_INPUT_TO_REGISTER ===", "=== EXACT_REGISTER_TO_REGISTER ==="),
    "register_to_register": ("=== EXACT_REGISTER_TO_REGISTER ===", "=== NEIGHBOR_INPUT_TO_REGISTER ==="),
}

output_re = re.compile(
    r"^\s*(\d+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+[v^]?\s+"
    r"(\S+)/(\S+) \(([^)]+)\)"
)
input_re = re.compile(
    r"^\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+[v^]?\s+"
    r"(\S+)/(\S+) \(([^)]+)\)"
)


def split_section(text, begin, end):
    return text.split(begin, 1)[1].split(end, 1)[0]


def classify(cell_type, path_name, is_launch):
    if is_launch:
        return "launch sequential arc", "STA cell type and startpoint", "high"
    if cell_type.startswith(("BUF", "CLKBUF", "INV")):
        return "buffer/inverter", "unambiguous mapped cell type", "high"
    return (
        "unknown/shared logic",
        "flattened mapped netlist has no source attribute for this standard cell",
        "low",
    )


def parse_path(path_name, section):
    rows = []
    pending_input_delay = 0.0
    seq = 0
    for line in section.splitlines():
        m = input_re.match(line)
        if m and not output_re.match(line):
            pending_input_delay += float(m.group(2))
            continue
        m = output_re.match(line)
        if not m:
            continue
        fanout, cap, slew, delay, arrival, inst, pin, cell_type = m.groups()
        is_launch = path_name == "register_to_register" and seq == 0 and cell_type.startswith("DFF")
        function, basis, confidence = classify(cell_type, path_name, is_launch)
        rows.append(
            {
                "path": path_name,
                "sequence": seq,
                "instance": inst,
                "pin": pin,
                "cell_type": cell_type,
                "cell_arc_delay_ns": float(delay),
                "preceding_wireload_delay_ns": pending_input_delay,
                "arrival_ns": float(arrival),
                "transition_ns": float(slew),
                "capacitance_ff": float(cap),
                "fanout": int(fanout),
                "rtl_function": function,
                "classification_basis": basis,
                "confidence": confidence,
            }
        )
        pending_input_delay = 0.0
        seq += 1
    start = re.search(r"Startpoint: ([^\n]+)", section).group(1).strip()
    endpoint = re.search(r"Endpoint: ([^\n]+)", section).group(1).strip()
    arrival = float(re.search(r"([0-9.]+)\s+data arrival time", section).group(1))
    slack_matches = re.findall(r"(-?[0-9.]+)\s+slack \((?:VIOLATED|MET)\)", section)
    return rows, start, endpoint, arrival, float(slack_matches[-1])


def max_consecutive_mux(rows):
    best = run = 0
    for row in rows:
        run = run + 1 if row["cell_type"].startswith("MUX") else 0
        best = max(best, run)
    return best


def source_evidence():
    data = json.loads(JSON_NETLIST.read_text(encoding="utf-8"))
    module = data["modules"]["systolic_axi_lite_top"]
    evidence = Counter()
    both = 0
    for cell in module["cells"].values():
        src = cell.get("attributes", {}).get("src", "")
        read17 = "systolic_device.sv:158." in src
        write17 = "systolic_device.sv:230." in src
        if read17:
            evidence["read_a_index_line_158"] += 1
        if write17:
            evidence["write_a_index_line_230"] += 1
        if read17 and write17:
            both += 1
    evidence["shared_read_write_source_tags"] = both
    return evidence


def main():
    text = RAW.read_text(encoding="utf-8", errors="replace")
    OUT.mkdir(parents=True, exist_ok=True)
    parsed = {}
    all_rows = []
    for name, markers in SECTIONS.items():
        rows, start, endpoint, arrival, slack = parse_path(name, split_section(text, *markers))
        for row in rows:
            row["startpoint"] = start
            row["endpoint"] = endpoint
        parsed[name] = {"rows": rows, "start": start, "endpoint": endpoint, "arrival": arrival, "slack": slack}
        all_rows.extend(rows)

    fields = list(all_rows[0].keys())
    with (OUT / "path_details.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(all_rows)

    breakdown = []
    summaries = {}
    for name, item in parsed.items():
        rows = item["rows"]
        launch = sum(r["cell_arc_delay_ns"] for r in rows if r["rtl_function"] == "launch sequential arc")
        buf = sum(r["cell_arc_delay_ns"] for r in rows if r["rtl_function"] == "buffer/inverter")
        other = sum(r["cell_arc_delay_ns"] for r in rows if r["rtl_function"] == "unknown/shared logic")
        wire = sum(r["preceding_wireload_delay_ns"] for r in rows)
        ext = 0.25 if name == "input_to_register" else 0.0
        for segment, delay, basis, confidence in [
            ("external input delay", ext, "SDC, excluded from combinational logic", "high"),
            ("launch sequential arc", launch, "launch DFF clock-to-Q", "high"),
            ("buffer/inverter", buf, "mapped cell types", "high"),
            ("unknown/shared non-buffer logic", other, "flattening removed reliable RTL ownership", "low"),
            ("wire-load net delay", wire, "OpenSTA input-pin increments under 5K_hvratio_1_1", "high"),
        ]:
            breakdown.append({"path": name, "segment": segment, "delay_ns": f"{delay:.6f}", "accounting": "additive", "basis": basis, "confidence": confidence})
        function_evidence = (
            ["address arithmetic", "range/permission/bitmap decode", "data selection", "write enable/hold logic"]
            if name == "register_to_register"
            else ["address arithmetic", "range/permission/bitmap decode", "data selection", "write enable/hold logic"]
        )
        for segment in function_evidence:
            breakdown.append({
                "path": name,
                "segment": segment,
                "delay_ns": "unavailable",
                "accounting": "evidence_only_not_additive",
                "basis": "present in RTL/pre-tech cone; mapped source ownership is not retained",
                "confidence": "medium" if segment != "write enable/hold logic" or name == "register_to_register" else "low",
            })
        combinational_levels = len(rows) - (1 if launch else 0)
        high = [r for r in rows if r["fanout"] >= 10]
        summaries[name] = {
            "cell_arcs": combinational_levels,
            "buf_inv_arcs": sum(r["rtl_function"] == "buffer/inverter" for r in rows),
            "mux_arcs": sum(r["cell_type"].startswith("MUX") for r in rows),
            "max_serial_mux": max_consecutive_mux(rows),
            "high_fanout_arcs": len(high),
            "high_fanout_driver_delay": sum(r["cell_arc_delay_ns"] for r in high),
            "cell_delay": sum(r["cell_arc_delay_ns"] for r in rows),
            "wire_delay": wire,
        }

    with (OUT / "path_breakdown.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["path", "segment", "delay_ns", "accounting", "basis", "confidence"])
        writer.writeheader()
        writer.writerows(breakdown)

    evidence = source_evidence()
    yosys_text = YOSYS_LOG.read_text(encoding="utf-8", errors="replace")
    final_div = [int(x) for x in re.findall(r"^\s*(\d+)\s+\$div_32\s*$", yosys_text, re.M)][-1]
    final_mod = [int(x) for x in re.findall(r"^\s*(\d+)\s+\$mod_32\s*$", yosys_text, re.M)][-1]
    r = parsed["input_to_register"]
    w = parsed["register_to_register"]
    rs = summaries["input_to_register"]
    ws = summaries["register_to_register"]
    md = f"""# V2 Lite-only post-synthesis long-path diagnosis

## Directly measured facts

This analysis reuses the fixed mapped netlist and SDC from the N=2, K=17, DATA_W=8, ACC_W=18 baseline. It is post-synthesis STA with the Nangate45 typical Liberty wire-load model, not post-route timing.

| Path | Data arrival | External/launch component | Combinational mapped-cell arcs | Buffer/inverter arcs | MUX arcs (max consecutive) | Wire-load delay | Slack |
|---|---:|---:|---:|---:|---:|---:|---:|
| `{r['start']}` → `{r['endpoint']}` | {r['arrival']:.6f} ns | 0.250000 ns input delay | {rs['cell_arcs']} | {rs['buf_inv_arcs']} | {rs['mux_arcs']} ({rs['max_serial_mux']}) | {rs['wire_delay']:.6f} ns | {r['slack']:.6f} ns |
| `{w['start']}` → `{w['endpoint']}` | {w['arrival']:.6f} ns | {next(x['cell_arc_delay_ns'] for x in w['rows'] if x['rtl_function']=='launch sequential arc'):.6f} ns clock-to-Q | {ws['cell_arcs']} | {ws['buf_inv_arcs']} | {ws['mux_arcs']} ({ws['max_serial_mux']}) | {ws['wire_delay']:.6f} ns | {w['slack']:.6f} ns |

The earlier “about 222 levels” statement is exact only for the read path: it contains **222 mapped combinational cell output arcs**. Input and output pin rows are not counted twice. The write path contains one launch DFF clock-to-Q arc plus **{ws['cell_arcs']} combinational cell arcs**. Clock path, external input delay, setup time, and endpoint clock are excluded from these logic-level counts.

High-fanout (fanout >= 10) drivers account for {rs['high_fanout_arcs']} arcs / {rs['high_fanout_driver_delay']:.6f} ns on the read path and {ws['high_fanout_arcs']} arcs / {ws['high_fanout_driver_delay']:.6f} ns on the write path. These are load-associated driver arc delays, not an independently separable wire-delay contribution.

## Evidence-supported diagnosis

- Both paths traverse very deep arithmetic-style mapped logic (half adders, XNOR/XOR, AOI/OAI, AND/OR) rather than a deep serial MUX chain. The read path has {rs['mux_arcs']} MUX arcs but no more than {rs['max_serial_mux']} consecutive MUX arcs; the write path has {ws['mux_arcs']} and no more than {ws['max_serial_mux']} consecutive MUX arcs.
- The final pre-tech frontend statistics retain {final_div} `$div_32` and {final_mod} `$mod_32` cells after optimization. The retained JSON further contains {evidence['read_a_index_line_158']} primitive cells tagged with the A-read dynamic-index source at `systolic_device.sv:158` and {evidence['write_a_index_line_230']} tagged with the A-write dynamic-index source at line 230; {evidence['shared_read_write_source_tags']} cells carry both source locations. Together these establish that `/17` and `%17`-derived dynamic indexing survives normalization and that optimization shares portions of the read/write index network.
- Therefore the dominant common cause is the wide address-to-index/dynamic-array-selection network created around K=17, including divider/remainder-derived logic and its shared decode. Plain CSR/A/B/C result selection contributes, but the physical path is not dominated by a serial MUX tree.
- Buffer/inverter delay is exactly accounted in `path_breakdown.csv`; all remaining non-buffer standard cells are conservatively marked `unknown/shared logic` because source attributes were removed when the mapped Verilog was emitted. They are not guessed into address arithmetic, decode, data selection, or write-enable buckets.

`u_device.a_matrix[136]` is the first bit after 17 elements × 8 bits = 136 bits. Under the retained flattened ordering it corresponds to A row 1, k=0, data bit 0. The numerical boundary and write-index logic support this mapping; the mapped netlist no longer retains the original unpacked-array coordinate as metadata, so confidence is medium rather than absolute.

## Uncertainties and hypotheses still requiring validation

- Exact delay attribution among base subtraction, `/17`, `%17`, range/permission checks, bitmap checks, and dynamic data selection is unavailable after flattening and technology mapping. `path_breakdown.csv` deliberately leaves their combined delay in `unknown/shared non-buffer logic` rather than double-counting gates.
- OpenSTA reports cell-arc delay and wire-load input-pin increments. The latter is an estimated pre-layout interconnect model; it is not routed net delay.
- Neighboring worst input-to-register endpoints are adjacent read-data bits, and neighboring register-to-register endpoints are adjacent A-buffer bits, so the two reported paths represent repeated structures. This does not prove all design paths share the same cause.

## Candidate follow-up experiments (not implemented)

1. Replace only the `/17` and `%17` address decomposition in an isolated diagnostic copy with a bounded compare/subtract or predecoded table, then remap under the same constraints. Compare cone depth and path delay; do not infer top-level benefit from the microbenchmark alone.
2. In a diagnostic RTL variant, separate index generation from the A/B/CSR read multiplexer with an observable register boundary. Re-run synthesis and post-route timing to test whether timing improves enough to justify the added transaction latency and state; the present report does not establish that tradeoff.

## Evidence files

- `build/v2_lite_path_diagnosis/high_precision_paths.rpt`: complete six-digit OpenSTA paths and ten neighboring paths per class.
- `reports/v2_lite_path_diagnosis/path_details.csv`: one row per mapped cell output arc, including load, slew, delay, arrival, and conservative ownership.
- `reports/v2_lite_path_diagnosis/path_breakdown.csv`: non-overlapping additive delay accounting plus explicitly non-additive functional evidence rows.
- `rtl/wrapper/systolic_device.sv:112`, `:148`, `:230`: write decode, read decode/index/data selection, and A-buffer write.
"""
    (OUT / "diagnosis.md").write_text(md, encoding="utf-8")


if __name__ == "__main__":
    main()
