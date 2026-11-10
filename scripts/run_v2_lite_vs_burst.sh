#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
build_root="$repo_root/build/v2_lite_vs_burst/performance"
report_root="$repo_root/reports/v2_lite_vs_burst"
mkdir -p "$build_root/lite" "$build_root/burst" "$report_root"

core_sources=(
  "$repo_root/rtl/core/systolic_pe.sv"
  "$repo_root/rtl/core/systolic_array.sv"
  "$repo_root/rtl/core/input_feeder.sv"
  "$repo_root/rtl/core/systolic_controller.sv"
  "$repo_root/rtl/core/systolic_array_top.sv"
)

verilator --cc --exe --build --timing --assert -Wall --public-flat-rw \
  --top-module systolic_axi_lite_top -GN=2 -GK=17 \
  --Mdir "$build_root/lite" -CFLAGS "-std=c++17 -I$repo_root/sim/wrapper" \
  "${core_sources[@]}" \
  "$repo_root/rtl/wrapper/axi_lite_slave.sv" \
  "$repo_root/rtl/wrapper/systolic_device.sv" \
  "$repo_root/rtl/wrapper/systolic_axi_lite_top.sv" \
  "$repo_root/sim/wrapper/axi_lite_bfm.cpp" \
  "$repo_root/sim/comparison/lite_transport_benchmark.cpp" \
  >"$build_root/lite/compile.log" 2>&1
(cd "$build_root/lite" && ./Vsystolic_axi_lite_top | tee simulation.log)

verilator --cc --exe --build --timing --assert -Wall --public-flat-rw \
  --top-module systolic_axi_burst_top -GN=2 -GK=17 -GPACKED_ENABLE=0 \
  --Mdir "$build_root/burst" -CFLAGS "-std=c++17 -I$repo_root/sim/burst" \
  "${core_sources[@]}" \
  "$repo_root/rtl/wrapper/axi_lite_slave.sv" \
  "$repo_root/rtl/wrapper/axi_burst_write_slave.sv" \
  "$repo_root/rtl/wrapper/systolic_device.sv" \
  "$repo_root/rtl/wrapper/systolic_axi_burst_top.sv" \
  "$repo_root/sim/burst/axi_burst_bfm.cpp" \
  "$repo_root/sim/comparison/burst_transport_benchmark.cpp" \
  >"$build_root/burst/compile.log" 2>&1
(cd "$build_root/burst" && ./Vsystolic_axi_burst_top | tee simulation.log)

{
  head -n 1 "$build_root/lite/performance.csv"
  tail -n +2 "$build_root/lite/performance.csv"
  tail -n +2 "$build_root/burst/performance.csv"
} > "$report_root/performance.csv"
{
  head -n 1 "$build_root/lite/backpressure.csv"
  tail -n +2 "$build_root/lite/backpressure.csv"
  tail -n +2 "$build_root/burst/backpressure.csv"
} > "$report_root/backpressure.csv"
cp "$build_root/burst/performance.csv" "$report_root/burst_length_comparison.csv"
cp "$build_root/burst/prediction_vs_measurement.csv" "$report_root/prediction_vs_measurement.csv"
cp "$build_root/burst/handshake_events.csv" "$report_root/handshake_events.csv"
cp "$build_root/burst/simulation.log" "$report_root/burst_length_test.log"

echo "Controlled transport comparison complete: $report_root/performance.csv"
