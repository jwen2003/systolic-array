#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
verilator_bin="${VERILATOR:-verilator}"

for tool in "${verilator_bin}" make g++; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "Required tool not found: ${tool}" >&2
        exit 1
    fi
done

run_test() {
    local top_module="$1"
    shift
    local build_dir="${repo_root}/build/wrapper/${top_module}"
    local obj_dir="${build_dir}/obj_dir"
    local binary_name="V${top_module}"

    for source_file in "$@"; do
        if [[ ! -f "${source_file}" ]]; then
            echo "Required source file not found: ${source_file}" >&2
            exit 1
        fi
    done

    mkdir -p "${build_dir}"
    echo "[BUILD] ${top_module}"
    "${verilator_bin}" \
        --binary \
        --timing \
        --assert \
        -Wall \
        --top-module "${top_module}" \
        --Mdir "${obj_dir}" \
        -o "${binary_name}" \
        "$@" \
        2>&1 | tee "${build_dir}/compile.log"

    echo "[RUN] ${top_module}"
    "${obj_dir}/${binary_name}" 2>&1 | tee "${build_dir}/simulation.log"
}

run_test tb_axi_lite_slave \
    "${repo_root}/rtl/wrapper/axi_lite_slave.sv" \
    "${repo_root}/tb/wrapper/unit/tb_axi_lite_slave.sv"

run_test tb_axi_burst_write_slave \
    "${repo_root}/rtl/wrapper/axi_burst_write_slave.sv" \
    "${repo_root}/tb/wrapper/unit/tb_axi_burst_write_slave.sv"

run_test tb_systolic_device \
    "${repo_root}/rtl/wrapper/systolic_device.sv" \
    "${repo_root}/tb/wrapper/unit/tb_systolic_device.sv"

run_test tb_systolic_device_packed_decode \
    "${repo_root}/rtl/wrapper/systolic_device.sv" \
    "${repo_root}/tb/wrapper/unit/tb_systolic_device_packed_decode.sv"

echo "Wrapper unit tests passed. Logs: ${repo_root}/build/wrapper/tb_*"
