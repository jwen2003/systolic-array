#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
build_root="${repo_root}/build/v2_double_buffer_performance"
mkdir -p "${build_root}"

run_one() {
  local mode="$1" n="$2" k="$3" top define adapter device top_file
  if [[ "$mode" == single ]]; then
    top=systolic_axi_burst_top; define=""; adapter=axi_burst_write_slave.sv
    device=systolic_device.sv; top_file=systolic_axi_burst_top.sv
  elif [[ "$mode" == dual ]]; then
    top=systolic_axi_dual_bank_top; define=-DDUAL_BANK; adapter=axi_dual_bank_burst_write_slave.sv
    device=systolic_dual_bank_device.sv; top_file=systolic_axi_dual_bank_top.sv
  else echo "mode must be single or dual" >&2; return 2; fi
  local out="${build_root}/n${n}_k${k}/${mode}"
  mkdir -p "$out"
  verilator --cc --exe --build --timing --assert -Wall --public-flat-rw \
    --top-module "$top" "-GN=$n" "-GK=$k" "-GPACKED_ENABLE=1'b1" \
    --Mdir "$out/obj_dir" -CFLAGS "-std=c++17 $define -DBENCH_N=$n -DBENCH_K=$k" \
    "$repo_root/rtl/core/systolic_pe.sv" "$repo_root/rtl/core/systolic_array.sv" \
    "$repo_root/rtl/core/input_feeder.sv" "$repo_root/rtl/core/systolic_controller.sv" \
    "$repo_root/rtl/core/systolic_array_top.sv" "$repo_root/rtl/wrapper/axi_lite_slave.sv" \
    "$repo_root/rtl/wrapper/$adapter" "$repo_root/rtl/wrapper/$device" \
    "$repo_root/rtl/wrapper/$top_file" "$repo_root/sim/comparison/double_buffer_performance_benchmark.cpp" \
    >"$out/compile.log" 2>&1 || { cat "$out/compile.log" >&2; return 1; }
  (cd "$out" && "obj_dir/V$top" | tee simulation.log)
}

if [[ $# -eq 3 ]]; then run_one "$1" "$2" "$3"; exit; fi
if [[ $# -ne 0 ]]; then echo "usage: $0 [single|dual N K]" >&2; exit 2; fi
for cfg in "2 2" "8 8" "16 64" "32 32"; do
  read -r n k <<<"$cfg"
  run_one single "$n" "$k"
  run_one dual "$n" "$k"
done
{
  head -n1 "${build_root}/n2_k2/single/summary.csv"
  for cfg in n2_k2 n8_k8 n16_k64 n32_k32; do
    tail -n1 "${build_root}/${cfg}/single/summary.csv"
    tail -n1 "${build_root}/${cfg}/dual/summary.csv"
  done
} >"${build_root}/summary.csv"
python3 - "$build_root" <<'PY'
import csv, pathlib, sys
root = pathlib.Path(sys.argv[1])
rows = list(csv.DictReader((root / "summary.csv").open()))
by_cfg = {(int(r["N"]), int(r["K"]), r["mode"]): r for r in rows}
fields = ["N", "K", "single_cycles", "dual_cycles", "cycles_saved", "speedup",
          "single_first_commit_cycles", "dual_first_commit_cycles"]
with (root / "comparison.csv").open("w", newline="") as f:
    out = csv.DictWriter(f, fieldnames=fields); out.writeheader()
    for n, k in [(2,2), (8,8), (16,64), (32,32)]:
        s, d = by_cfg[n,k,"single"], by_cfg[n,k,"dual"]
        sc, dc = int(s["first_aw_to_last_ack"]), int(d["first_aw_to_last_ack"])
        out.writerow({"N":n,"K":k,"single_cycles":sc,"dual_cycles":dc,
                      "cycles_saved":sc-dc,"speedup":f"{sc/dc:.6f}",
                      "single_first_commit_cycles":s["first_commit_to_last_ack"],
                      "dual_first_commit_cycles":d["first_commit_to_last_ack"]})
with (root / "summary.md").open("w") as f:
    f.write("# Single-buffer vs dual-input-bank cycle benchmark\n\n")
    f.write("Cycles are inclusive from the first Burst AW acceptance to operation 20 ACK acceptance. ")
    f.write("All configurations use packed writes, maximum 16-beat bursts, STATUS polling, Lite C reads, and 20 operations.\n\n")
    f.write("| N | K | Single cycles | Dual cycles | Saved | Speedup |\n|---:|---:|---:|---:|---:|---:|\n")
    for n, k in [(2,2), (8,8), (16,64), (32,32)]:
        s, d = by_cfg[n,k,"single"], by_cfg[n,k,"dual"]
        sc, dc = int(s["first_aw_to_last_ack"]), int(d["first_aw_to_last_ack"])
        f.write(f"| {n} | {k} | {sc} | {dc} | {sc-dc} | {sc/dc:.6f}x |\n")
    f.write("\nThe first valid input commit boundary is one cycle later, so both totals decrease by one and each speedup is unchanged.\n")
PY
echo "Results: ${build_root}/summary.csv"
