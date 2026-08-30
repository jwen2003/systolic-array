#!/usr/bin/env python3
"""Validate generic synthesis structure against the frozen architecture."""

import json
import math
import re
import sys
from collections import Counter
from pathlib import Path


CONFIGS = {
    "n1_k1": {"n": 1, "k": 1, "data_w": 8, "acc_w": 18},
    "n2_k2": {"n": 2, "k": 2, "data_w": 8, "acc_w": 18},
    "n4_k4": {"n": 4, "k": 4, "data_w": 8, "acc_w": 18},
}


def binary_parameter(value: str) -> int:
    return int(value, 2)


def load_module(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        design = json.load(handle)
    return design["modules"]["systolic_array_top"]


def cell_width(cell: dict, parameter: str) -> int:
    return binary_parameter(cell["parameters"][parameter])


def analyze(build_root: Path, name: str, config: dict) -> dict:
    n = config["n"]
    k = config["k"]
    data_w = config["data_w"]
    acc_w = config["acc_w"]
    product_w = 2 * data_w
    sign_index = data_w - 1
    config_dir = build_root / name
    module = load_module(config_dir / "pretech.json")
    final_module = load_module(config_dir / "generic_netlist.json")
    cells = module["cells"]

    pe_pattern = re.compile(
        r"^u_array\.gen_row\[\d+\]\.gen_col\[\d+\]\.u_pe\.psum_out$"
    )
    pe_result_nets = {
        netname: net["bits"]
        for netname, net in module["netnames"].items()
        if pe_pattern.match(netname)
    }
    pe_result_markers = len(pe_result_nets)
    pe_result_bit_vectors = {tuple(bits) for bits in pe_result_nets.values()}
    cycle_bits = len(module["netnames"]["u_controller.cycle_idx"]["bits"])
    multipliers = [cell for cell in cells.values() if cell["type"] == "$mul"]
    adders = {
        cell_name: cell
        for cell_name, cell in cells.items()
        if cell["type"] == "$add"
    }
    accumulator_adders = {
        cell_name: cell
        for cell_name, cell in adders.items()
        if cell_width(cell, "A_WIDTH") == acc_w
        and cell_width(cell, "B_WIDTH") == acc_w
        and cell_width(cell, "Y_WIDTH") == acc_w
        and tuple(cell["connections"]["A"]) in pe_result_bit_vectors
    }
    controller_index_adders = {
        cell_name: cell
        for cell_name, cell in adders.items()
        if cell_name not in accumulator_adders
    }
    register_cells = [
        cell
        for cell in cells.values()
        if re.match(r"^\$(?:s?dff|s?dffe)", cell["type"])
    ]
    register_bits = sum(cell_width(cell, "WIDTH") for cell in register_cells)
    primitive_counts = dict(
        sorted(Counter(cell["type"] for cell in final_module["cells"].values()).items())
    )

    expected_pes = n * n
    expected_cycle_bits = max(1, math.ceil(math.log2(k + 2 * n - 2)))
    expected_total_adders = expected_pes + 1
    failures = []
    if pe_result_markers != expected_pes:
        failures.append(
            f"PE result marker count {pe_result_markers}, expected {expected_pes}"
        )
    if cycle_bits != expected_cycle_bits:
        failures.append(
            f"cycle counter width {cycle_bits}, expected {expected_cycle_bits}"
        )
    if len(multipliers) != expected_pes:
        failures.append(
            f"multiplier count {len(multipliers)}, expected {expected_pes}"
        )
    if len(accumulator_adders) != expected_pes:
        failures.append(
            f"accumulator adder count {len(accumulator_adders)}, expected {expected_pes}"
        )
    if len(adders) != expected_total_adders:
        failures.append(
            f"total adder count {len(adders)}, fixed-tool baseline {expected_total_adders}"
        )
    for index, multiplier in enumerate(multipliers):
        params = multiplier["parameters"]
        a_bits = multiplier["connections"]["A"]
        b_bits = multiplier["connections"]["B"]
        a_is_sign_extended = len(a_bits) == product_w and all(
            bit == a_bits[sign_index] for bit in a_bits[data_w:]
        )
        b_is_sign_extended = len(b_bits) == product_w and all(
            bit == b_bits[sign_index] for bit in b_bits[data_w:]
        )
        if (
            binary_parameter(params["A_SIGNED"]) != 1
            or binary_parameter(params["B_SIGNED"]) != 1
            or cell_width(multiplier, "A_WIDTH") != product_w
            or cell_width(multiplier, "B_WIDTH") != product_w
            or cell_width(multiplier, "Y_WIDTH") != product_w
            or not a_is_sign_extended
            or not b_is_sign_extended
        ):
            failures.append(
                f"multiplier {index} is not sign-extended signed "
                f"{data_w}x{data_w} -> {product_w}"
            )

    if not cells or not final_module["cells"]:
        failures.append("top-level design was optimized to an empty cell set")

    log_text = (config_dir / "yosys.log").read_text(encoding="utf-8")
    if "Build succeeded: 0 errors, 0 warnings" not in log_text:
        failures.append("Slang frontend did not report a clean build")
    if log_text.count("Found and reported 0 problems.") != 4:
        failures.append("not all four check passes reported zero problems")
    if re.search(r"%(?:Warning|Error)|Warning:|ERROR:", log_text):
        failures.append("Yosys log contains a warning or error diagnostic")

    if n == 1:
        expected_pipe_widths = {
            "u_array.a_pipe": 2 * data_w,
            "u_array.a_valid_pipe": 2,
            "u_array.b_pipe": 2 * data_w,
            "u_array.b_valid_pipe": 2,
        }
        for netname, width in expected_pipe_widths.items():
            actual = len(module["netnames"][netname]["bits"])
            if actual != width:
                failures.append(f"{netname} width {actual}, expected {width}")

    result = {
        "config": name,
        "parameters": config,
        "expected_product_width": product_w,
        "pe_result_markers": pe_result_markers,
        "cycle_counter_bits": cycle_bits,
        "multipliers": len(multipliers),
        "accumulator_adders": len(accumulator_adders),
        "controller_index_adders": len(controller_index_adders),
        "total_adders": len(adders),
        "fixed_tool_total_adder_baseline": expected_total_adders,
        "register_cells": len(register_cells),
        "register_bits": register_bits,
        "pretech_cells": len(cells),
        "generic_cells": len(final_module["cells"]),
        "techmap_primitives": primitive_counts,
        "failures": failures,
    }
    (config_dir / "structure_summary.json").write_text(
        json.dumps(result, indent=2) + "\n", encoding="utf-8"
    )
    return result


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} BUILD_ROOT", file=sys.stderr)
        return 2

    build_root = Path(sys.argv[1]).resolve()
    failed = False
    results = []
    print(
        "config\tPE_markers\tcycle_bits\tmul\tacc_add\tother_add\t"
        "reg_cells\treg_bits\tpretech\tgeneric"
    )
    for name, config in CONFIGS.items():
        result = analyze(build_root, name, config)
        results.append(result)
        print(
            f"{name}\t{result['pe_result_markers']}\t"
            f"{result['cycle_counter_bits']}\t{result['multipliers']}\t"
            f"{result['accumulator_adders']}\t"
            f"{result['controller_index_adders']}\t"
            f"{result['register_cells']}\t{result['register_bits']}\t"
            f"{result['pretech_cells']}\t{result['generic_cells']}"
        )
        for failure in result["failures"]:
            failed = True
            print(f"ERROR: {name}: {failure}", file=sys.stderr)

    aggregate = {"schema_version": 1, "results": results}
    (build_root / "structure_summary.json").write_text(
        json.dumps(aggregate, indent=2) + "\n", encoding="utf-8"
    )
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())

