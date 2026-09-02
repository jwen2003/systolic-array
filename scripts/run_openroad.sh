#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
orfs_root="${ORFS_ROOT:-/mnt/c/Projects/OpenROAD-flow-scripts}"
yosys_bin="${OSS_CAD_SUITE_ROOT:-$HOME/.local/opt/oss-cad-suite-20260830}/bin/yosys"
build_root="$repo_root/build/openroad"
orfs_commit="6101364b2d7909dd797e1e3e7f80695401cfa4e4"
registered_image="openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0"
variant="${FLOW_VARIANT:-baseline}"
dry_run="${DRY_RUN:-0}"

case "$variant" in
  baseline)
    synth_top="systolic_array_top"
    filelist_rel="synth/filelists/systolic_array_top.f"
    config_rel="physical/nangate45/config.mk"
    sdc_rel="physical/nangate45/constraint.sdc"
    nickname="systolic_array_n2_k2"
    clock_period="2.500"
    image="openroad/orfs@sha256:d995618be9f2bcdfa5538b885123463070dfbf178bea1818716d4652fe0fa380"
    orfs_target="default"
    make_target=""
    run_parent="$build_root"
    final_dir="$build_root/n2_k2"
    ;;
  registered_boundary)
    synth_top="systolic_array_pipelined_top"
    filelist_rel="synth/filelists/systolic_array_pipelined_top.f"
    config_rel="physical/nangate45_registered/config.mk"
    sdc_rel="physical/nangate45_registered/constraint.sdc"
    nickname="systolic_array_pipelined_n2_k2"
    clock_period="2.000"
    image="$registered_image"
    orfs_target="finish"
    make_target="finish"
    run_parent="$build_root/registered_boundary"
    final_dir="$run_parent/500mhz"
    ;;
  *)
    echo "Unsupported FLOW_VARIANT: $variant" >&2
    exit 2
    ;;
esac

[[ "$dry_run" == "0" || "$dry_run" == "1" ]] || { echo "DRY_RUN must be 0 or 1" >&2; exit 2; }

require_repo_file() {
  local rel="$1"
  local resolved
  [[ "$rel" != /* && "$rel" != *".."* ]] || { echo "Unsafe repository path: $rel" >&2; exit 2; }
  resolved="$(readlink -f "$repo_root/$rel")"
  [[ -f "$resolved" && "$resolved" == "$repo_root"/* ]] || { echo "Missing or unsafe repository file: $rel" >&2; exit 2; }
}

require_repo_file "$filelist_rel"
require_repo_file "$config_rel"
require_repo_file "$sdc_rel"
require_repo_file "physical/nangate45/frontend.tcl"
require_repo_file "physical/nangate45/equivalence.tcl"

orfs_root="$(readlink -f "$orfs_root")"
[[ "$orfs_root" == "/mnt/c/Projects/OpenROAD-flow-scripts" ]] || { echo "Unexpected ORFS path" >&2; exit 1; }
[[ "$(git -C "$orfs_root" -c safe.directory="$orfs_root" rev-parse HEAD)" == "$orfs_commit" ]] || { echo "ORFS commit mismatch" >&2; exit 1; }

stage_template="$run_parent/.run.XXXXXX"
frontend_template="$stage_template/frontend"
derived_template="$frontend_template/post_proc.v"

print_plan() {
  printf '%s\n' \
    "variant=$variant" \
    "top=$synth_top" \
    "filelist=$repo_root/$filelist_rel" \
    "container_filelist=/work/$filelist_rel" \
    "config=$repo_root/$config_rel" \
    "container_config=/work/$config_rel" \
    "sdc=$repo_root/$sdc_rel" \
    "nickname=$nickname" \
    "clock_period_ns=$clock_period" \
    "lec_check=0" \
    "orfs_commit=$orfs_commit" \
    "image=$image" \
    "frontend_output_dir=$frontend_template" \
    "derived_verilog=$derived_template" \
    "temporary_work_dir=$stage_template" \
    "final_publish_dir=$final_dir" \
    "orfs_target=$orfs_target"
}

if [[ "$dry_run" == "1" ]]; then
  print_plan
  exit 0
fi

mkdir -p "$run_parent"
run_parent="$(readlink -f "$run_parent")"
build_root="$(readlink -f "$build_root")"
[[ "$run_parent" == "$build_root" || "$run_parent" == "$build_root/registered_boundary" ]] || exit 2
[[ ! -L "$final_dir" ]] || { echo "Refusing symlink publish path: $final_dir" >&2; exit 2; }
if [[ "$variant" == "registered_boundary" && -e "$final_dir" ]]; then
  echo "Registered result already exists: $final_dir" >&2
  exit 2
fi

stage="$(mktemp -d "$run_parent/.run.XXXXXX")"
stage="$(readlink -f "$stage")"
[[ "$stage" == "$run_parent"/.run.* ]] || exit 2
preserve_failure() {
  if [[ "$variant" == "baseline" && -d "$stage" && "$stage" == "$build_root"/.run.* ]]; then
    failed_dir="$build_root/failed_n2_k2"
    [[ ! -e "$failed_dir" ]] || mv "$failed_dir" "$stage/previous_failure"
    mv "$stage" "$failed_dir"
  fi
}
trap 'preserve_failure' ERR

mkdir -p "$stage/frontend" "$stage/work"
export SYNTH_TOP="$synth_top"
export SYNTH_FILELIST="$filelist_rel"
export FRONTEND_OUT_DIR="$stage/frontend"
cd "$repo_root"
"$yosys_bin" -c physical/nangate45/frontend.tcl -l "$stage/frontend/yosys.log"
export DERIVED_VERILOG="$stage/frontend/post_proc.v"
"$yosys_bin" -c physical/nangate45/equivalence.tcl -l "$stage/frontend/equivalence.log"

docker run --rm \
  -v "$orfs_root/flow:/OpenROAD-flow-scripts/flow:ro" \
  -v "$repo_root:/work" \
  -e FLOW_HOME=/OpenROAD-flow-scripts/flow \
  -e WORK_HOME="/work/${stage#"$repo_root/"}/work" \
  -e SYSTOLIC_DERIVED_V="/work/${stage#"$repo_root/"}/frontend/post_proc.v" \
  -e SYNTH_TOP="$synth_top" \
  -e SYNTH_FILELIST="/work/$filelist_rel" \
  -e FRONTEND_OUT_DIR="/work/${stage#"$repo_root/"}/frontend" \
  -e DERIVED_VERILOG="/work/${stage#"$repo_root/"}/frontend/post_proc.v" \
  "$image" bash -lc \
  "source /OpenROAD-flow-scripts/env.sh >/dev/null; cd /OpenROAD-flow-scripts/flow; make DESIGN_CONFIG=/work/$config_rel $make_target"

{
  echo "utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "git_commit=$(git -C "$repo_root" rev-parse HEAD)"
  echo "variant=$variant"
  echo "top=$synth_top"
  echo "filelist=$filelist_rel"
  echo "config=$config_rel"
  echo "sdc=$sdc_rel"
  echo "nickname=$nickname"
  echo "orfs_root=$orfs_root"
  echo "orfs_commit=$orfs_commit"
  echo "image=$image"
  echo "clock_period_ns=$clock_period"
} > "$stage/run_manifest.txt"

if [[ "$variant" == "baseline" ]]; then
  if [[ -d "$final_dir" ]]; then mv "$final_dir" "$stage/previous"; fi
  mv "$stage" "$final_dir"
  rm -rf -- "$final_dir/previous"
else
  mv "$stage" "$final_dir"
fi
trap - ERR
echo "OpenROAD $variant flow completed."
