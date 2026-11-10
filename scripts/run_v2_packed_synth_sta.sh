#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
orfs_commit=6101364b2d7909dd797e1e3e7f80695401cfa4e4
image='openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0'
build_root="${PACKED_SYNTH_BUILD_ROOT:-$repo_root/build/v2_packed_synth_sta}"
[[ "$build_root" == /* ]] || build_root="$repo_root/$build_root"
top=systolic_axi_burst_top
filelist=synth/filelists/systolic_axi_burst_top.f
sdc=physical/nangate45_lite_vs_burst/constraint_burst.sdc

[[ -n "${ORFS_ROOT:-}" ]] || { echo 'ORFS_ROOT is required' >&2; exit 2; }
orfs_root="$(readlink -f -- "$ORFS_ROOT")"
[[ "$(git -C "$orfs_root" rev-parse HEAD)" == "$orfs_commit" ]] || { echo 'ORFS commit mismatch' >&2; exit 2; }
yosys_bin="${OSS_CAD_SUITE_ROOT:-$HOME/.local/opt/oss-cad-suite-20260830}/bin/yosys"
[[ -x "$yosys_bin" ]] || { echo "Missing pinned Yosys: $yosys_bin" >&2; exit 2; }

for rel in \
  "$filelist" \
  "$sdc" \
  physical/nangate45_lite_vs_burst/frontend.tcl \
  physical/nangate45_lite_vs_burst/equivalence.tcl \
  physical/nangate45_lite_vs_burst/post_synth_sta.tcl \
  physical/nangate45_packed_synth_sta/packed_path_sta.tcl \
  physical/nangate45_packed_synth_sta/config_packed0.mk \
  physical/nangate45_packed_synth_sta/config_packed1.mk; do
  [[ -f "$repo_root/$rel" ]] || { echo "Missing input: $rel" >&2; exit 2; }
done

docker image inspect "$image" >/dev/null
mkdir -p "$build_root"
active_stage=''
active_failure=''
preserve_on_exit() {
  local rc=$?
  trap - EXIT
  if [[ $rc -ne 0 && -n "$active_stage" && -d "$active_stage" ]]; then
    echo "$rc" > "$active_stage/exit_code.txt"
    mv "$active_stage" "$active_failure"
  fi
  exit "$rc"
}
trap preserve_on_exit EXIT

run_one() {
  local variant=$1 packed_enable=$2 config=$3
  local final="$build_root/$variant"
  [[ ! -e "$final" && ! -L "$final" ]] || { echo "Result exists: $final" >&2; return 2; }
  local stage failure
  stage="$(mktemp -d "$build_root/.run.${variant}.XXXXXX")"
  failure="$build_root/failed_${variant}_$(date -u +%Y%m%dT%H%M%SZ)"
  active_stage="$stage"
  active_failure="$failure"
  mkdir -p "$stage/frontend" "$stage/work" "$stage/sta" "$stage/packed_paths"

  export SYNTH_TOP="$top" SYNTH_FILELIST="$filelist" PACKED_ENABLE="$packed_enable"
  export FRONTEND_OUT_DIR="$stage/frontend"
  (cd "$repo_root" && "$yosys_bin" -c physical/nangate45_lite_vs_burst/frontend.tcl -l "$stage/frontend/yosys.log")
  export DERIVED_VERILOG="$stage/frontend/post_proc.v"
  (cd "$repo_root" && "$yosys_bin" -c physical/nangate45_lite_vs_burst/equivalence.tcl -l "$stage/frontend/equivalence.log")

  local rel_stage mapped
  rel_stage="${stage#"$repo_root/"}"
  docker run --rm \
    -v "$orfs_root/flow:/OpenROAD-flow-scripts/flow:ro" \
    -v "$repo_root:/work" \
    -e FLOW_HOME=/OpenROAD-flow-scripts/flow \
    -e WORK_HOME="/work/$rel_stage/work" \
    -e SYSTOLIC_DERIVED_V="/work/$rel_stage/frontend/post_proc.v" \
    "$image" bash -lc \
    "source /OpenROAD-flow-scripts/env.sh >/dev/null; cd /OpenROAD-flow-scripts/flow; make -j1 DESIGN_CONFIG=/work/$config synth" \
    > "$stage/synthesis.log" 2>&1
  mapped="$(find "$stage/work/results" -name 1_2_yosys.v -type f -print -quit)"
  [[ -s "$mapped" ]] || { echo "Mapped netlist missing for $variant" >&2; return 1; }

  docker run --rm \
    -v "$orfs_root/flow:/OpenROAD-flow-scripts/flow:ro" \
    -v "$repo_root:/work" \
    -e NANGATE45_LIBERTY=/OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib \
    -e MAPPED_NETLIST="/work/${mapped#"$repo_root/"}" \
    -e STA_SDC="/work/$sdc" \
    -e SYNTH_TOP="$top" \
    "$image" bash -lc \
    'source /OpenROAD-flow-scripts/env.sh >/dev/null; sta -exit /work/physical/nangate45_lite_vs_burst/post_synth_sta.tcl' \
    > "$stage/sta/openroad_sta.log" 2>&1

  docker run --rm \
    -v "$orfs_root/flow:/OpenROAD-flow-scripts/flow:ro" \
    -v "$repo_root:/work" \
    -e NANGATE45_LIBERTY=/OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib \
    -e MAPPED_NETLIST="/work/${mapped#"$repo_root/"}" \
    -e STA_SDC="/work/$sdc" \
    -e SYNTH_TOP="$top" \
    -e PACKED_PATH_DIR="/work/$rel_stage/packed_paths" \
    "$image" bash -lc \
    'source /OpenROAD-flow-scripts/env.sh >/dev/null; sta -exit /work/physical/nangate45_packed_synth_sta/packed_path_sta.tcl' \
    > "$stage/packed_paths/opensta.log" 2>&1

  {
    echo "utc=$(date -u +%FT%TZ)"
    echo "git_head=$(git -C "$repo_root" rev-parse HEAD)"
    echo git_status_begin
    git -C "$repo_root" status --porcelain
    echo git_status_end
    echo "top=$top"
    echo N=2
    echo K=17
    echo DATA_W=8
    echo ACC_W=18
    echo "PACKED_ENABLE=$packed_enable"
    echo "orfs_commit=$orfs_commit"
    echo "image=$image"
    docker image inspect "$image" --format 'image_id={{.Id}} image_created={{.Created}} image_arch={{.Architecture}}'
    docker run --rm "$image" bash -lc 'source /OpenROAD-flow-scripts/env.sh >/dev/null; yosys -V; openroad -version; sta -version'
    "$yosys_bin" -V
    echo clock_period_ns=2.500
    echo clock_uncertainty_ns=0.050
    echo input_delay_max_ns=0.250
    echo input_delay_min_ns=0.000
    echo input_transition_ns=0.050
    echo output_load_pf=0.010
    echo wire_load=5K_hvratio_1_1
    echo "config=$config"
  } > "$stage/manifest.txt"

  while IFS= read -r src; do
    [[ -z "$src" || "$src" == \#* ]] && continue
    (cd "$repo_root" && sha256sum "$src")
  done < "$repo_root/$filelist" > "$stage/source_sha256.txt"
  (cd "$repo_root" && sha256sum \
    "$filelist" \
    "$sdc" \
    physical/nangate45_lite_vs_burst/frontend.tcl \
    physical/nangate45_lite_vs_burst/equivalence.tcl \
    physical/nangate45_lite_vs_burst/post_synth_sta.tcl \
    physical/nangate45_packed_synth_sta/packed_path_sta.tcl \
    "$config") > "$stage/flow_sha256.txt"

  mv "$stage" "$final"
  active_stage=''
  active_failure=''
}

run_one packed0 0 physical/nangate45_packed_synth_sta/config_packed0.mk
run_one packed1 1 physical/nangate45_packed_synth_sta/config_packed1.mk
echo "Packed synthesis/STA results: $build_root"
