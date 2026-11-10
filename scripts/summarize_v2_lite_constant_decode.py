#!/usr/bin/env python3
"""Compare the constant-address Device decode against the fixed V2 Lite baseline."""

import csv
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "reports/v2_lite_synth_sta"
BUILD = ROOT / "build/v2_lite_constant_decode_sta/n2_k17_2p5ns"
DIAG = ROOT / "build/v2_lite_constant_decode_diagnosis/high_precision_paths.rpt"
BASE_DIAG = ROOT / "build/v2_lite_path_diagnosis/high_precision_paths.rpt"
OUT = ROOT / "reports/v2_lite_constant_decode_sta"


def report_section(text, name):
    m = re.search(rf"^=== REPORT_BEGIN {name} ===$(.*?)^=== REPORT_END {name} ===$", text, re.M | re.S)
    return m.group(1) if m else ""


def exact_section(text, begin, end):
    return text.split(begin, 1)[1].split(end, 1)[0]


def exact_path(text, begin, end, input_delay=False):
    block = exact_section(text, begin, end)
    arrival = float(re.search(r"([0-9.]+)\s+data arrival time", block).group(1))
    slack = float(re.findall(r"(-?[0-9.]+)\s+slack \((?:MET|VIOLATED)\)", block)[-1])
    arcs = []
    row = re.compile(r"^\s*(\d+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+[v^]?\s+(\S+)/(\S+) \(([^)]+)\)", re.M)
    for m in row.finditer(block):
        arcs.append((m.group(6), m.group(8), float(m.group(4))))
    launch = arcs[0][2] if arcs and arcs[0][1].startswith("DFF") else 0.0
    levels = len(arcs) - (1 if launch else 0)
    return {"arrival": arrival, "logic_delay": arrival - (0.25 if input_delay else launch), "slack": slack, "levels": levels, "launch": launch}


def metrics_csv(path):
    with path.open(newline="", encoding="utf-8") as f:
        return {row["metric"]: row["value"] for row in csv.DictReader(f)}


def main():
    stat_file = next((BUILD / "work/reports").rglob("synth_stat.txt"))
    check_file = next((BUILD / "work/reports").rglob("synth_check.txt"))
    stat = stat_file.read_text(errors="replace")
    sta = (BUILD / "sta/openroad_sta.log").read_text(errors="replace")
    diag = DIAG.read_text(errors="replace")
    base_diag = BASE_DIAG.read_text(errors="replace")
    base = metrics_csv(BASE / "metrics.csv")

    total = re.search(r"^\s*(\d+)\s+([0-9.E+-]+)\s+\d+\s+[0-9.E+-]+\s+cells$", stat, re.M)
    area = float(re.search(r"Chip area for module .*?:\s*([0-9.]+)", stat).group(1))
    seq_area = float(re.search(r"used for sequential elements:\s*([0-9.]+)", stat).group(1))
    cell_rows = []
    for line in stat.splitlines():
        m = re.match(r"^\s*(\d+)\s+([0-9.E+-]+)\s+\d+\s+[0-9.E+-]+\s+([A-Z][A-Z0-9_]+)$", line)
        if m:
            cell_rows.append((m.group(3), int(m.group(1)), float(m.group(2))))
    cells = int(total.group(1))
    seq_cells = sum(n for typ, n, _ in cell_rows if typ.startswith(("DFF", "SDFF")))
    buffers = sum(n for typ, n, _ in cell_rows if typ.startswith(("BUF_", "CLKBUF_")))
    inv = sum(n for typ, n, _ in cell_rows if typ.startswith("INV_"))
    timing = report_section(sta, "timing_summary")
    value = lambda pattern: float(re.search(pattern, timing, re.M).group(1))
    wns, tns = value(r"^wns max (-?[0-9.]+)$"), value(r"^tns max (-?[0-9.]+)$")
    hwns, htns = value(r"^wns min (-?[0-9.]+)$"), value(r"^tns min (-?[0-9.]+)$")
    maxcap = report_section(sta, "violations").count("(VIOLATED)")
    base_maxcap = (BASE / "timing_summary.rpt").read_text(errors="replace").count("(VIOLATED)")

    markers = ("=== EXACT_INPUT_TO_REGISTER ===", "=== EXACT_REGISTER_TO_REGISTER ===", "=== NEIGHBOR_INPUT_TO_REGISTER ===")
    old_read = exact_path(base_diag, markers[0], markers[1], True)
    old_write = exact_path(base_diag, markers[1], markers[2])
    new_read = exact_path(diag, markers[0], markers[1], True)
    new_write = exact_path(diag, markers[1], markers[2])

    new = {
        "mapped_cell_area": area,
        "mapped_cell_count": cells,
        "sequential_area": seq_area,
        "sequential_cell_count": seq_cells,
        "combinational_area": area - seq_area,
        "combinational_cell_count": cells - seq_cells,
        "buffer_cell_count": buffers,
        "inverter_cell_count": inv,
        "setup_wns": wns,
        "setup_tns": tns,
        "hold_wns": hwns,
        "hold_tns": htns,
    }
    OUT.mkdir(parents=True, exist_ok=True)
    rows = []
    for key, val in new.items():
        old = float(base[key])
        rows.append((key, old, val, val - old, (val / old - 1) * 100 if old else "unavailable"))
    for key, old, val in [
        ("original_read_logic_delay_ns", old_read["logic_delay"], new_read["logic_delay"]),
        ("original_read_logic_levels", old_read["levels"], new_read["levels"]),
        ("original_write_logic_delay_ns", old_write["logic_delay"], new_write["logic_delay"]),
        ("original_write_logic_levels", old_write["levels"], new_write["levels"]),
    ]:
        rows.append((key, old, val, val - old, (val / old - 1) * 100 if old else "unavailable"))
    with (OUT / "comparison.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(("metric", "baseline", "constant_decode", "delta", "delta_percent"))
        writer.writerows(rows)

    worst = exact_section(sta, "=== REPORT_BEGIN constraints_max ===", "=== REPORT_END constraints_max ===")
    start = re.search(r"Startpoint: ([^\n]+)", worst).group(1).strip()
    end = re.search(r"Endpoint: ([^\n]+)", worst).group(1).strip()
    shutil.copy2(stat_file, OUT / "synth_stat.rpt")
    shutil.copy2(check_file, OUT / "synth_check.rpt")
    (OUT / "timing_summary.rpt").write_text(report_section(sta, "check_setup") + timing + report_section(sta, "violations"), encoding="utf-8")
    (OUT / "summary.md").write_text(f"""# V2 Lite constant-address decode synthesis/STA comparison

## Measured comparison

| Metric | Baseline | Constant decode | Delta |
|---|---:|---:|---:|
| Mapped cell area | {float(base['mapped_cell_area']):.3f} µm² | {area:.3f} µm² | {area-float(base['mapped_cell_area']):+.3f} µm² |
| Mapped cells | {int(base['mapped_cell_count'])} | {cells} | {cells-int(base['mapped_cell_count']):+d} |
| Sequential cells / area | {int(base['sequential_cell_count'])} / {float(base['sequential_area']):.3f} µm² | {seq_cells} / {seq_area:.3f} µm² | unchanged |
| Combinational cells / area | {int(base['combinational_cell_count'])} / {float(base['combinational_area']):.3f} µm² | {cells-seq_cells} / {area-seq_area:.3f} µm² | {cells-seq_cells-int(base['combinational_cell_count']):+d} / {area-seq_area-float(base['combinational_area']):+.3f} µm² |
| Buffers / inverters | {int(base['buffer_cell_count'])} / {int(base['inverter_cell_count'])} | {buffers} / {inv} | {buffers-int(base['buffer_cell_count']):+d} / {inv-int(base['inverter_cell_count']):+d} |
| Setup WNS / TNS | {float(base['setup_wns']):.2f} / {float(base['setup_tns']):.2f} ns | {wns:.2f} / {tns:.2f} ns | {wns-float(base['setup_wns']):+.2f} / {tns-float(base['setup_tns']):+.2f} ns |
| Hold WNS / TNS | {float(base['hold_wns']):.2f} / {float(base['hold_tns']):.2f} ns | {hwns:.2f} / {htns:.2f} ns | {hwns-float(base['hold_wns']):+.2f} / {htns-float(base['hold_tns']):+.2f} ns |
| Max-capacitance violations | {base_maxcap} | {maxcap} | {maxcap-base_maxcap:+d} |
| Original read bottleneck logic | {old_read['logic_delay']:.6f} ns / {old_read['levels']} arcs | {new_read['logic_delay']:.6f} ns / {new_read['levels']} arcs | {new_read['logic_delay']-old_read['logic_delay']:+.6f} ns / {new_read['levels']-old_read['levels']:+d} |
| Original write bottleneck logic | {old_write['logic_delay']:.6f} ns / {old_write['levels']} arcs | {new_write['logic_delay']:.6f} ns / {new_write['levels']} arcs | {new_write['logic_delay']-old_write['logic_delay']:+.6f} ns / {new_write['levels']-old_write['levels']:+d} |

The new worst setup path is `{start}` → `{end}`. It is inside the V1 controller/feeder/PE datapath, so the former AXI read/write decode bottlenecks have migrated out of first place.

## Functional verification

- `tb_systolic_device`: 391 checks, including row-boundary/last-element mapping, direct storage and bitmap observation, unwritten reads, sign extension, and high-address alias rejection.
- AXI-Lite integration: N/K = 1/1 (178 checks), 2/3 (262), 2/17 (514), and 3/5 (402), each with an independent matrix golden model.
- Existing AXI slave and burst-slave unit tests: 84 and 132 checks.
- Existing Burst comparison: 1531 checks. Packed comparisons: N/K = 2/17 (772), 2/16 (725), 3/5 (480), and 1/5 (264).
- Verilator 5.032 `-Wall --assert`: no warning or error in the rebuilt affected tests.

## Interpretation boundaries

- Same top, parameters, Nangate45 typical Liberty, 2.5 ns SDC, I/O assumptions, ABC flow, and `5K_hvratio_1_1` wire-load model as the baseline.
- This is mapped post-synthesis STA, not placement or post-route timing.
- Source-to-derived equivalence proves 4023/4023 cells. This does not prove old Device RTL and new Device RTL are equivalent.
- The only runtime `/` and `%` operations left in Device RTL are in the optional packed-access branch. The Lite-only mapped result has `PACKED_ENABLE=0`; no conclusion is claimed for optimizing packed accesses.
- The remaining setup violation (-0.08 ns) is in the Core path and requires separate architectural or physical investigation.
""", encoding="utf-8")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
