#!/usr/bin/env bash
set -euo pipefail

# Separate entry point: preserves the existing wrapper unit-test runner.
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="$repo_root/build/wrapper/tb_systolic_axi_lite_top"
mkdir -p "$build_dir"

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
for source_file in "${sources[@]}"; do
  if [[ ! -f "$source_file" ]]; then
    echo "Missing source: $source_file" >&2
    exit 1
  fi
done

verilator --binary --timing --assert -Wall \
  --top-module tb_systolic_axi_lite_top \
  --Mdir "$build_dir" "${sources[@]}" \
  > "$build_dir/compile.log" 2>&1 || {
    cat "$build_dir/compile.log" >&2
    exit 1
  }
"$build_dir/Vtb_systolic_axi_lite_top" | tee "$build_dir/simulation.log"
