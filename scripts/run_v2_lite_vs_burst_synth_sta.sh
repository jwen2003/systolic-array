#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
orfs_commit=6101364b2d7909dd797e1e3e7f80695401cfa4e4
image='openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0'
build_root="$repo_root/build/v2_lite_vs_burst/synth_sta"
[[ -n "${ORFS_ROOT:-}" ]] || { echo 'ORFS_ROOT is required' >&2; exit 2; }
orfs_root="$(readlink -f -- "$ORFS_ROOT")"
[[ "$(git -C "$orfs_root" rev-parse HEAD)" == "$orfs_commit" ]] || { echo 'ORFS commit mismatch' >&2; exit 2; }
yosys_bin="${OSS_CAD_SUITE_ROOT:-$HOME/.local/opt/oss-cad-suite-20260830}/bin/yosys"
[[ -x "$yosys_bin" ]] || { echo "Missing pinned Yosys: $yosys_bin" >&2; exit 2; }
mkdir -p "$build_root"

run_one() {
  local variant=$1 top=$2 filelist=$3 config=$4 sdc=$5
  local final="$build_root/$variant"
  [[ ! -e "$final" ]] || { echo "Result exists: $final" >&2; return 2; }
  local stage; stage="$(mktemp -d "$build_root/.run.${variant}.XXXXXX")"
  mkdir -p "$stage/frontend" "$stage/work" "$stage/sta"
  export SYNTH_TOP="$top" SYNTH_FILELIST="$filelist" FRONTEND_OUT_DIR="$stage/frontend"
  (cd "$repo_root" && "$yosys_bin" -c physical/nangate45_lite_vs_burst/frontend.tcl -l "$stage/frontend/yosys.log")
  export DERIVED_VERILOG="$stage/frontend/post_proc.v"
  (cd "$repo_root" && "$yosys_bin" -c physical/nangate45_lite_vs_burst/equivalence.tcl -l "$stage/frontend/equivalence.log")
  local rel_stage="${stage#"$repo_root/"}"
  docker run --rm -v "$orfs_root/flow:/OpenROAD-flow-scripts/flow:ro" -v "$repo_root:/work" \
    -e FLOW_HOME=/OpenROAD-flow-scripts/flow -e WORK_HOME="/work/$rel_stage/work" \
    -e SYSTOLIC_DERIVED_V="/work/$rel_stage/frontend/post_proc.v" "$image" bash -lc \
    "source /OpenROAD-flow-scripts/env.sh >/dev/null; cd /OpenROAD-flow-scripts/flow; make -j1 DESIGN_CONFIG=/work/$config synth"
  local mapped; mapped="$(find "$stage/work/results" -name 1_2_yosys.v -type f -print -quit)"
  [[ -s "$mapped" ]] || { echo 'Mapped netlist missing' >&2; return 1; }
  docker run --rm -v "$orfs_root/flow:/OpenROAD-flow-scripts/flow:ro" -v "$repo_root:/work" \
    -e NANGATE45_LIBERTY=/OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib \
    -e MAPPED_NETLIST="/work/${mapped#"$repo_root/"}" -e STA_SDC="/work/$sdc" \
    -e SYNTH_TOP="$top" "$image" bash -lc \
    'source /OpenROAD-flow-scripts/env.sh >/dev/null; sta -exit /work/physical/nangate45_lite_vs_burst/post_synth_sta.tcl' \
    >"$stage/sta/openroad_sta.log" 2>&1
  {
    echo "utc=$(date -u +%FT%TZ)"; echo "git_head=$(git -C "$repo_root" rev-parse HEAD)"; echo "top=$top"
    echo 'N=2'; echo 'K=17'; echo 'DATA_W=8'; echo 'ACC_W=18'; echo 'PACKED_ENABLE=0'
    echo "orfs_commit=$orfs_commit"; echo "image=$image"; echo 'clock_period_ns=2.500'
    echo 'corner=typical_1.10V_25C'; echo 'wire_load=5K_hvratio_1_1'
    "$yosys_bin" -V
  } >"$stage/manifest.txt"
  while IFS= read -r src; do [[ -z "$src" || "$src" == \#* ]] && continue; (cd "$repo_root" && sha256sum "$src"); done <"$repo_root/$filelist" >"$stage/source_sha256.txt"
  mv "$stage" "$final"
}

run_one lite systolic_axi_lite_top synth/filelists/systolic_axi_lite_top.f physical/nangate45_lite_vs_burst/config_lite.mk physical/nangate45_lite_vs_burst/constraint_lite.sdc
run_one burst systolic_axi_burst_top synth/filelists/systolic_axi_burst_top.f physical/nangate45_lite_vs_burst/config_burst.mk physical/nangate45_lite_vs_burst/constraint_burst.sdc
echo "Comparable synthesis/STA results: $build_root"
