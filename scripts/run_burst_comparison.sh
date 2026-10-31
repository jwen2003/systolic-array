#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="$repo_root/build/wrapper/burst_comparison"
mkdir -p "$build_dir"
sources=(
  "$repo_root/rtl/core/systolic_pe.sv"
  "$repo_root/rtl/core/systolic_array.sv"
  "$repo_root/rtl/core/input_feeder.sv"
  "$repo_root/rtl/core/systolic_controller.sv"
  "$repo_root/rtl/core/systolic_array_top.sv"
  "$repo_root/rtl/wrapper/axi_lite_slave.sv"
  "$repo_root/rtl/wrapper/axi_burst_write_slave.sv"
  "$repo_root/rtl/wrapper/systolic_device.sv"
  "$repo_root/rtl/wrapper/systolic_axi_burst_top.sv"
)
verilator --cc --exe --build --assert -Wall \
  --top-module systolic_axi_burst_top -GN=2 -GK=17 \
  --Mdir "$build_dir" -CFLAGS "-std=c++17" \
  "${sources[@]}" "$repo_root/sim/burst/axi_burst_bfm.cpp" "$repo_root/sim/burst/main.cpp" \
  > "$build_dir/compile.log" 2>&1 || {
    cat "$build_dir/compile.log" >&2
    exit 1
  }
cd "$build_dir"
./Vsystolic_axi_burst_top | tee simulation.log
