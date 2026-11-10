#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
verilator_bin="${VERILATOR:-verilator}"

bash "$repo_root/scripts/run_wrapper_tests.sh"

sources=(
  "$repo_root/rtl/core/systolic_pe.sv"
  "$repo_root/rtl/core/systolic_array.sv"
  "$repo_root/rtl/core/input_feeder.sv"
  "$repo_root/rtl/core/systolic_controller.sv"
  "$repo_root/rtl/core/systolic_array_top.sv"
  "$repo_root/rtl/wrapper/axi_lite_slave.sv"
  "$repo_root/rtl/wrapper/systolic_device.sv"
  "$repo_root/rtl/wrapper/systolic_axi_lite_top.sv"
  "$repo_root/tb/integration/tb_systolic_axi_lite_top.sv"
)

run_integration() {
  local n="$1" k="$2"
  local build_dir="$repo_root/build/v2_constant_decode_tests/n${n}_k${k}"
  mkdir -p "$build_dir"
  "$verilator_bin" --binary --timing --assert -Wall \
    --top-module tb_systolic_axi_lite_top -GN="$n" -GK="$k" \
    --Mdir "$build_dir" "${sources[@]}" \
    > "$build_dir/compile.log" 2>&1 || {
      cat "$build_dir/compile.log" >&2
      return 1
    }
  "$build_dir/Vtb_systolic_axi_lite_top" | tee "$build_dir/simulation.log"
}

run_integration 1 1
run_integration 2 3
run_integration 2 17
run_integration 3 5

echo "V2 constant-address decode tests passed."
