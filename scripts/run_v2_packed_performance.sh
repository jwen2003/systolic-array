#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
build_dir="$repo_root/build/v2_packed_performance"
report_dir="$repo_root/reports/v2_packed_performance"
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
  -GN=2 -GK=17 -GDATA_W=8 -GACC_W=18 "-GPACKED_ENABLE=1'b1" \
  --Mdir "$build_dir" \
  -CFLAGS "-std=c++17 -I$repo_root/sim/burst" \
  "${sources[@]}" \
  "$repo_root/sim/burst/axi_burst_bfm.cpp" \
  "$repo_root/sim/comparison/packed_vs_unpacked_benchmark.cpp" \
  >"$build_dir/compile.log" 2>&1 || {
    cat "$build_dir/compile.log" >&2
    exit 1
  }

(cd "$build_dir" && ./Vsystolic_axi_burst_top | tee simulation.log)
cp "$build_dir/comparison.csv" "$report_dir/comparison.csv"
cp "$build_dir/transaction_events.csv" "$report_dir/transaction_events.csv"
cp "$build_dir/timeline.csv" "$report_dir/timeline.csv"
cp "$build_dir/prediction_vs_measurement.csv" "$report_dir/prediction_vs_measurement.csv"
cp "$build_dir/simulation.log" "$report_dir/simulation.log"
cp "$build_dir/compile.log" "$report_dir/compile.log"
echo "Packed vs unpacked performance report: $report_dir/comparison.csv"
