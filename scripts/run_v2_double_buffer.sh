#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
run_test() {
  local top="$1" tb="$2"
  local build_dir="${repo_root}/build/wrapper/${top}"
  mkdir -p "${build_dir}"
  verilator --binary --timing --assert -Wall \
  --top-module "${top}" --Mdir "${build_dir}/obj_dir" \
  "${repo_root}/rtl/core/systolic_pe.sv" \
  "${repo_root}/rtl/core/systolic_array.sv" \
  "${repo_root}/rtl/core/input_feeder.sv" \
  "${repo_root}/rtl/core/systolic_controller.sv" \
  "${repo_root}/rtl/core/systolic_array_top.sv" \
  "${repo_root}/rtl/wrapper/axi_lite_slave.sv" \
  "${repo_root}/rtl/wrapper/axi_dual_bank_burst_write_slave.sv" \
  "${repo_root}/rtl/wrapper/systolic_dual_bank_device.sv" \
  "${repo_root}/rtl/wrapper/systolic_axi_dual_bank_top.sv" \
  "${repo_root}/${tb}" \
  2>&1 | tee "${build_dir}/compile.log"
  "${build_dir}/obj_dir/V${top}" 2>&1 | tee "${build_dir}/simulation.log"
}
run_test tb_systolic_dual_bank_device_tail tb/wrapper/unit/tb_systolic_dual_bank_device_tail.sv
run_test tb_systolic_axi_dual_bank_top tb/wrapper/integration/tb_systolic_axi_dual_bank_top.sv
