#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
image="openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0"
baseline="$repo_root/build/v2_lite_synth_sta/n2_k17_2p5ns"
out_dir="$repo_root/build/v2_lite_path_diagnosis"
netlist="$baseline/work/results/nangate45/systolic_axi_lite_n2_k17/base/1_2_yosys.v"

[[ -s "$netlist" ]] || { echo "Missing mapped baseline netlist: $netlist" >&2; exit 2; }
[[ -s "$baseline/frontend/post_proc.json" ]] || { echo "Missing baseline JSON" >&2; exit 2; }
docker image inspect "$image" >/dev/null

mkdir -p "$out_dir"
netlist_rel="${netlist#"$repo_root/"}"
docker run --rm \
  -v "$repo_root:/work" \
  -e NANGATE45_LIBERTY=/OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib \
  -e MAPPED_NETLIST="/work/$netlist_rel" \
  -e STA_SDC=/work/physical/nangate45_lite/constraint.sdc \
  "$image" bash -lc \
  'source /OpenROAD-flow-scripts/env.sh >/dev/null; sta -exit /work/physical/nangate45_lite/path_diagnosis.tcl' \
  > "$out_dir/high_precision_paths.rpt" 2>&1

if grep -q '^Error:' "$out_dir/high_precision_paths.rpt"; then
  echo "OpenSTA reported an error" >&2
  exit 1
fi
echo "Path diagnostics written to $out_dir/high_precision_paths.rpt"
