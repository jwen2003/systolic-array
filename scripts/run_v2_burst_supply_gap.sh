#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
build_dir="$repo_root/build/v2_burst_supply_gap"
report_dir="$repo_root/reports/v2_burst_supply_gap"
mkdir -p "$build_dir" "$report_dir"

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

verilator --cc --exe --build --timing --assert -Wall --public-flat-rw \
  --top-module systolic_axi_burst_top \
  -GN=2 -GK=17 -GDATA_W=8 -GACC_W=18 "-GPACKED_ENABLE=1'b0" \
  --Mdir "$build_dir" \
  -CFLAGS "-std=c++17 -I$repo_root/sim/burst" \
  "${sources[@]}" \
  "$repo_root/sim/burst/axi_burst_bfm.cpp" \
  "$repo_root/sim/comparison/burst_supply_gap_benchmark.cpp" \
  >"$build_dir/compile.log" 2>&1 || {
    cat "$build_dir/compile.log" >&2
    exit 1
  }

(cd "$build_dir" && ./Vsystolic_axi_burst_top | tee simulation.log)
for artifact in comparison.csv gap_comparison.csv element_events.csv transaction_events.csv timeline.csv simulation.log; do
  cp "$build_dir/$artifact" "$report_dir/$artifact"
done
echo "Burst supply-gap report: $report_dir/comparison.csv"
