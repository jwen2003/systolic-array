#!/usr/bin/env python3
"""Validate and summarize controlled generic-synthesis scaling results."""

import csv, json, math, re, sys
from collections import Counter
from pathlib import Path

BASELINE_ADDERS = {"n1_k1", "n2_k2", "n4_k4"}
SWEEP_BASES = {"n_sweep": "n1_k2", "k_sweep": "n2_k1"}
METRICS = ("pe_result_markers", "multipliers", "accumulator_adders",
           "controller_index_adders", "register_cells", "register_bits",
           "pretech_cells", "generic_cells")


def load_configs(path):
    with path.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    required = {"name", "N", "K", "DATA_W", "ACC_W", "experiment_group"}
    if not rows or set(rows[0]) != required:
        raise ValueError(f"invalid configuration schema: {path}")
    configs, names = [], set()
    for row in rows:
        config = {"name": row["name"], "n": int(row["N"]), "k": int(row["K"]),
                  "data_w": int(row["DATA_W"]), "acc_w": int(row["ACC_W"]),
                  "experiment_groups": row["experiment_group"].split(",")}
        name = config["name"]
        if name in names or name != f"n{config['n']}_k{config['k']}":
            raise ValueError(f"invalid or duplicate configuration: {name}")
        if min(config[key] for key in ("n", "k", "data_w", "acc_w")) < 1:
            raise ValueError(f"non-positive configuration value: {name}")
        names.add(name); configs.append(config)
    return configs


def bparam(value): return int(value, 2)
def width(cell, parameter): return bparam(cell["parameters"][parameter])


def load_top(path):
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)["modules"]["systolic_array_top"]


def analyze(root, config):
    name, n, k = config["name"], config["n"], config["k"]
    data_w, acc_w = config["data_w"], config["acc_w"]
    product_w, sign_index = 2 * data_w, data_w - 1
    directory = root / name
    top, final = load_top(directory / "pretech.json"), load_top(directory / "generic_netlist.json")
    cells = top["cells"]
    pattern = re.compile(r"^u_array\.gen_row\[\d+\]\.gen_col\[\d+\]\.u_pe\.psum_out$")
    marker_vectors = {tuple(net["bits"]) for key, net in top["netnames"].items() if pattern.match(key)}
    multipliers = {key: cell for key, cell in cells.items() if cell["type"] == "$mul"}
    adders = {key: cell for key, cell in cells.items() if cell["type"] == "$add"}
    accumulators = {key: cell for key, cell in adders.items()
                    if width(cell, "A_WIDTH") == acc_w and width(cell, "B_WIDTH") == acc_w
                    and width(cell, "Y_WIDTH") == acc_w
                    and tuple(cell["connections"]["A"]) in marker_vectors}
    others = {key: cell for key, cell in adders.items() if key not in accumulators}
    registers = [cell for cell in cells.values() if re.match(r"^\$(?:s?dff|s?dffe)", cell["type"])]
    reg_bits = sum(width(cell, "WIDTH") for cell in registers)
    primitives = dict(sorted(Counter(cell["type"] for cell in final["cells"].values()).items()))
    cycle_bits = len(top["netnames"]["u_controller.cycle_idx"]["bits"])
    expected, failures = n * n, []
    expected_cycle = max(1, math.ceil(math.log2(k + 2 * n - 2)))
    checks = ((len(marker_vectors), expected, "PE result markers"),
              (len(multipliers), expected, "multipliers"),
              (len(accumulators), expected, "accumulator adders"),
              (cycle_bits, expected_cycle, "cycle counter width"))
    for actual, wanted, label in checks:
        if actual != wanted: failures.append(f"{label} {actual}, expected {wanted}")
    if name in BASELINE_ADDERS and len(adders) != expected + 1:
        failures.append(f"total adders {len(adders)}, fixed-tool baseline {expected + 1}")
    for cell_name, cell in multipliers.items():
        a, b, params = cell["connections"]["A"], cell["connections"]["B"], cell["parameters"]
        extended = (len(a) == product_w and len(b) == product_w
                    and all(bit == a[sign_index] for bit in a[data_w:])
                    and all(bit == b[sign_index] for bit in b[data_w:]))
        valid = (bparam(params["A_SIGNED"]) == bparam(params["B_SIGNED"]) == 1
                 and width(cell, "A_WIDTH") == width(cell, "B_WIDTH") == product_w
                 and width(cell, "Y_WIDTH") == product_w and extended)
        if not valid: failures.append(f"multiplier {cell_name} signed width/extension mismatch")
    if not cells or not final["cells"]: failures.append("top cell set is empty")
    log = (directory / "yosys.log").read_text(encoding="utf-8")
    if "Build succeeded: 0 errors, 0 warnings" not in log: failures.append("Slang build not clean")
    if log.count("Found and reported 0 problems.") != 4: failures.append("four clean checks not found")
    if re.search(r"%(?:Warning|Error)|Warning:|ERROR:", log): failures.append("diagnostic in Yosys log")
    if n == 1:
        for net, wanted in {"u_array.a_pipe": 2 * data_w, "u_array.a_valid_pipe": 2,
                            "u_array.b_pipe": 2 * data_w, "u_array.b_valid_pipe": 2}.items():
            actual = len(top["netnames"][net]["bits"])
            if actual != wanted: failures.append(f"{net} width {actual}, expected {wanted}")
    result = {"config": name, "experiment_groups": config["experiment_groups"],
              "parameters": {key: config[key] for key in ("n", "k", "data_w", "acc_w")},
              "expected_product_width": product_w, "pe_result_markers": len(marker_vectors),
              "cycle_counter_bits": cycle_bits, "multipliers": len(multipliers),
              "accumulator_adders": len(accumulators), "controller_index_adders": len(others),
              "total_adders": len(adders),
              "fixed_tool_total_adder_baseline": expected + 1 if name in BASELINE_ADDERS else None,
              "register_cells": len(registers), "register_bits": reg_bits,
              "pretech_cells": len(cells), "generic_cells": len(final["cells"]),
              "generic_cells_per_n_squared": len(final["cells"]) / expected,
              "register_bits_per_n_squared": reg_bits / expected,
              "techmap_primitives": primitives, "sweep_comparisons": {}, "failures": failures}
    return result


def add_comparisons(results):
    by_name = {item["config"]: item for item in results}
    for group, base_name in SWEEP_BASES.items():
        base = by_name[base_name]
        for item in results:
            if group not in item["experiment_groups"]: continue
            values = {field: {"absolute_change": item[field] - base[field],
                              "ratio": item[field] / base[field] if base[field] else None}
                      for field in METRICS}
            item["sweep_comparisons"][group] = {
                "baseline_config": base_name,
                "n_ratio": item["parameters"]["n"] / base["parameters"]["n"],
                "n_squared_ratio": item["parameters"]["n"] ** 2 / base["parameters"]["n"] ** 2,
                "k_ratio": item["parameters"]["k"] / base["parameters"]["k"], "metrics": values}


def emit_tsv(results):
    types = sorted({kind for item in results for kind in item["techmap_primitives"]})
    columns = ["config", "experiment_groups", "N", "K", "DATA_W", "ACC_W", "PE_markers",
               "cycle_bits", "mul", "acc_add", "other_add", "reg_cells", "reg_bits",
               "pretech", "generic", "generic_per_N2", "reg_bits_per_N2"]
    comparisons = [f"{group}_{metric}_{suffix}" for group in SWEEP_BASES
                   for metric in ("generic", "reg_bits") for suffix in ("delta", "ratio")]
    print("\t".join(columns + [f"primitive:{kind}" for kind in types] + comparisons))
    for item in results:
        p = item["parameters"]
        row = [item["config"], ",".join(item["experiment_groups"]), str(p["n"]), str(p["k"]),
               str(p["data_w"]), str(p["acc_w"]), str(item["pe_result_markers"]),
               str(item["cycle_counter_bits"]), str(item["multipliers"]),
               str(item["accumulator_adders"]), str(item["controller_index_adders"]),
               str(item["register_cells"]), str(item["register_bits"]), str(item["pretech_cells"]),
               str(item["generic_cells"]), f"{item['generic_cells_per_n_squared']:.6f}",
               f"{item['register_bits_per_n_squared']:.6f}"]
        row += [str(item["techmap_primitives"].get(kind, 0)) for kind in types]
        for group in SWEEP_BASES:
            comp = item["sweep_comparisons"].get(group)
            if comp:
                m = comp["metrics"]
                row += [str(m["generic_cells"]["absolute_change"]), f"{m['generic_cells']['ratio']:.6f}",
                        str(m["register_bits"]["absolute_change"]), f"{m['register_bits']['ratio']:.6f}"]
            else: row += ["", "", "", ""]
        print("\t".join(row))


def main():
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} BUILD_ROOT CONFIG_TSV", file=sys.stderr); return 2
    root, source = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    results = [analyze(root, config) for config in load_configs(source)]
    add_comparisons(results)
    for item in results:
        (root / item["config"] / "structure_summary.json").write_text(
            json.dumps(item, indent=2) + "\n", encoding="utf-8")
    aggregate = {"schema_version": 2, "configuration_source": str(source),
                 "sweep_baselines": SWEEP_BASES, "results": results}
    (root / "structure_summary.json").write_text(json.dumps(aggregate, indent=2) + "\n", encoding="utf-8")
    emit_tsv(results)
    for item in results:
        for failure in item["failures"]: print(f"ERROR: {item['config']}: {failure}", file=sys.stderr)
    return 1 if any(item["failures"] for item in results) else 0


if __name__ == "__main__": raise SystemExit(main())
