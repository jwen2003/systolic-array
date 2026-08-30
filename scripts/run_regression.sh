#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="${BUILD_ROOT:-$repo_root/build/regression}"
random_tests="${RANDOM_TESTS:-100}"
verilator_bin="${VERILATOR:-verilator}"

rtl=(
  rtl/systolic_pe.sv
  rtl/systolic_array.sv
  rtl/input_feeder.sv
  rtl/systolic_controller.sv
  rtl/systolic_array_top.sv
)

run_test() {
  local name="$1"
  local top="$2"
  local tb="$3"
  shift 3
  local build_dir="$build_root/$name"
  local prefix="V$name"

  echo "[BUILD] $name"
  "$verilator_bin" --binary --timing --Wall \
    --top-module "$top" --prefix "$prefix" --Mdir "$build_dir" \
    "${rtl[@]}" "$tb" "$@"
  echo "[RUN]   $name"
  "$build_dir/$prefix"
}

cd "$repo_root"
mkdir -p "$build_root"

run_test pe         tb_systolic_pe         tb/tb_systolic_pe.sv
run_test array      tb_systolic_array      tb/tb_systolic_array.sv
run_test feeder     tb_input_feeder        tb/tb_input_feeder.sv
run_test controller tb_systolic_controller tb/tb_systolic_controller.sv
run_test top        tb_systolic_array_top  tb/tb_systolic_array_top.sv

for config in "1 1" "2 1" "2 2" "2 3" "4 1" "4 4"; do
  read -r n k <<<"$config"
  run_test "random_n${n}_k${k}" tb_systolic_array_random \
    tb/tb_systolic_array_random.sv \
    "-GN=$n" "-GK=$k" "-GNUM_RANDOM_TESTS=$random_tests"
done

echo "Regression passed: 5 directed testbenches and 6 parameter configurations."
