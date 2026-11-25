#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
build_root="${repo_root}/build/v2_dual_bank_c_burst_read"
mkdir -p "${build_root}"

rtl_common=(
  "${repo_root}/rtl/core/systolic_pe.sv"
  "${repo_root}/rtl/core/systolic_array.sv"
  "${repo_root}/rtl/core/input_feeder.sv"
  "${repo_root}/rtl/core/systolic_controller.sv"
  "${repo_root}/rtl/core/systolic_array_top.sv"
  "${repo_root}/rtl/wrapper/axi_lite_slave.sv"
  "${repo_root}/rtl/wrapper/axi_dual_bank_burst_write_slave.sv"
  "${repo_root}/rtl/wrapper/systolic_dual_bank_device.sv"
)

run_unit() {
  local out="${build_root}/unit"
  rm -rf -- "$out"; mkdir -p "$out"
  verilator --binary --timing --assert --Wall -Wno-BLKSEQ \
    --Mdir "$out/obj_dir" --top-module tb_axi_c_burst_read_slave \
    "${repo_root}/rtl/wrapper/axi_c_burst_read_slave.sv" \
    "${repo_root}/tb/wrapper/unit/tb_axi_c_burst_read_slave.sv" \
    >"$out/compile.log" 2>&1
  "$out/obj_dir/Vtb_axi_c_burst_read_slave" | tee "$out/simulation.log"
  local integration="${build_root}/ownership"
  rm -rf -- "$integration"; mkdir -p "$integration"
  verilator --binary --timing --assert --Wall -Wno-BLKSEQ \
    --Mdir "$integration/obj_dir" --top-module tb_dual_bank_c_burst_read_ownership \
    "${repo_root}/rtl/wrapper/axi_c_burst_read_slave.sv" \
    "${repo_root}/rtl/wrapper/systolic_dual_bank_device.sv" \
    "${repo_root}/tb/wrapper/integration/tb_dual_bank_c_burst_read_ownership.sv" \
    >"$integration/compile.log" 2>&1
  "$integration/obj_dir/Vtb_dual_bank_c_burst_read_ownership" | tee "$integration/simulation.log"
}

run_benchmark() {
  local mode="$1" n="$2" k="$3" top top_file define
  if [[ "$mode" == lite ]]; then
    top=systolic_axi_dual_bank_top
    top_file="${repo_root}/rtl/wrapper/systolic_axi_dual_bank_top.sv"
    define="-DDUAL_BANK"
  elif [[ "$mode" == burst_read ]]; then
    top=systolic_axi_dual_bank_burst_read_top
    top_file="${repo_root}/rtl/wrapper/systolic_axi_dual_bank_burst_read_top.sv"
    define="-DDUAL_BANK -DC_BURST_READ"
  else
    echo "mode must be lite or burst_read" >&2; return 2
  fi
  local out="${build_root}/n${n}_k${k}/${mode}"
  rm -rf -- "$out"; mkdir -p "$out"
  local extra=()
  [[ "$mode" == burst_read ]] && extra+=("${repo_root}/rtl/wrapper/axi_c_burst_read_slave.sv")
  verilator --cc --exe --build --timing --assert -Wall --public-flat-rw \
    --top-module "$top" "-GN=$n" "-GK=$k" "-GPACKED_ENABLE=1'b1" \
    --Mdir "$out/obj_dir" -CFLAGS "-std=c++17 $define -DBENCH_N=$n -DBENCH_K=$k" \
    "${rtl_common[@]}" "${extra[@]}" "$top_file" \
    "${repo_root}/sim/comparison/double_buffer_performance_benchmark.cpp" \
    >"$out/compile.log" 2>&1
  (cd "$out" && "obj_dir/V$top" | tee simulation.log)
}

summarize() {
  python3 - "$build_root" <<'PY'
import csv, pathlib, sys
root=pathlib.Path(sys.argv[1])
rows=[]
for n,k in ((16,64),(32,32)):
    for mode in ("lite","burst_read"):
        p=root/f"n{n}_k{k}"/mode/"summary.csv"
        row=next(csv.DictReader(p.open())); row["readback_mode"]=mode; rows.append(row)
fields=["readback_mode","N","K","operations","first_aw_to_last_ack","average_start_interval",
        "avg_start_to_device_done","avg_device_done_to_host_done","avg_host_done_to_first_result",
        "avg_first_to_last_result","avg_last_result_to_ack","avg_ack_to_next_start",
        "load_during_core_busy","load_during_device_done","burst_and_result_same_cycle"]
with (root/"comparison.csv").open("w",newline="") as f:
    w=csv.DictWriter(f,fieldnames=fields,extrasaction="ignore");w.writeheader();w.writerows(rows)
with (root/"summary.md").open("w") as f:
    f.write("# Dual-bank Lite versus C Burst read benchmark\n\n")
    f.write("All rows execute 20 operations with packed 16-beat A/B writes, single outstanding transactions, STATUS polling, and identical input matrices. Cycles are inclusive from the first input AW handshake through the final accepted ACK.\n\n")
    f.write("| N | K | Readback | Total cycles | Avg START interval | Avg result span | Speedup vs Lite |\n|---:|---:|---|---:|---:|---:|---:|\n")
    by={(int(r["N"]),int(r["K"]),r["readback_mode"]):r for r in rows}
    for n,k in ((16,64),(32,32)):
        base=float(by[n,k,"lite"]["first_aw_to_last_ack"])
        for mode in ("lite","burst_read"):
            r=by[n,k,mode]; total=float(r["first_aw_to_last_ack"])
            f.write(f"| {n} | {k} | {mode} | {total:.0f} | {float(r['average_start_interval']):.3f} | {float(r['avg_first_to_last_result']):.3f} | {base/total:.6f}x |\n")
PY
}

case "${1:-all}" in
  unit) run_unit ;;
  benchmark)
    run_benchmark lite 16 64; run_benchmark burst_read 16 64
    run_benchmark lite 32 32; run_benchmark burst_read 32 32; summarize ;;
  all)
    run_unit
    run_benchmark lite 16 64; run_benchmark burst_read 16 64
    run_benchmark lite 32 32; run_benchmark burst_read 32 32; summarize ;;
  *) echo "usage: $0 [unit|benchmark|all]" >&2; exit 2 ;;
esac
echo "Results: ${build_root}"
