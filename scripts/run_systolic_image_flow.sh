#!/usr/bin/env bash
set -euo pipefail

variant="${FLOW_VARIANT:-baseline}"
dry_run="${DRY_RUN:-0}"
registered_image="openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
orfs_root="${ORFS_ROOT:-/mnt/c/Projects/OpenROAD-flow-scripts}"
yosys_bin="${OSS_CAD_SUITE_ROOT:-$HOME/.local/opt/oss-cad-suite-20260830}/bin/yosys"
orfs_commit="6101364b2d7909dd797e1e3e7f80695401cfa4e4"
build_root="$(readlink -f "$repo_root/build/openroad")"
threads="${3:-16}"
target="${4:-finish}"

case "$variant" in
  baseline)
    image="${1:?immutable image reference required}"
    output_dir="${2:?output directory required}"
    synth_top="systolic_array_top"
    filelist_rel="synth/filelists/systolic_array_top.f"
    config_rel="physical/nangate45/config.mk"
    sdc_rel="physical/nangate45/constraint.sdc"
    nickname="systolic_array_n2_k2"
    clock_period="2.500"
    ;;
  registered_boundary)
    image="${1:-$registered_image}"
    [[ "$image" == "$registered_image" ]] || { echo "Registered variant requires pinned image: $registered_image" >&2; exit 2; }
    output_dir="$repo_root/build/openroad/registered_boundary/500mhz"
    [[ -z "${2:-}" || "$(readlink -m "$2")" == "$output_dir" ]] || { echo "Registered output path is fixed: $output_dir" >&2; exit 2; }
    synth_top="systolic_array_pipelined_top"
    filelist_rel="synth/filelists/systolic_array_pipelined_top.f"
    config_rel="physical/nangate45_registered/config.mk"
    sdc_rel="physical/nangate45_registered/constraint.sdc"
    nickname="systolic_array_pipelined_n2_k2"
    clock_period="2.000"
    [[ -z "${4:-}" || "${4}" == "finish" ]] || { echo "Registered ORFS target is fixed: finish" >&2; exit 2; }
    target="finish"
    ;;
  *)
    echo "Unsupported FLOW_VARIANT: $variant" >&2
    exit 2
    ;;
esac

[[ "$dry_run" == "0" || "$dry_run" == "1" ]] || { echo "DRY_RUN must be 0 or 1" >&2; exit 2; }
[[ "$target" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Invalid ORFS target" >&2; exit 2; }
[[ "$threads" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid thread count" >&2; exit 2; }

for rel in "$filelist_rel" "$config_rel" "$sdc_rel" physical/nangate45/frontend.tcl physical/nangate45/equivalence.tcl; do
  [[ "$rel" != /* && "$rel" != *".."* ]] || exit 2
  resolved="$(readlink -f "$repo_root/$rel")"
  [[ -f "$resolved" && "$resolved" == "$repo_root"/* ]] || { echo "Missing or unsafe repository file: $rel" >&2; exit 2; }
done

orfs_root="$(readlink -f "$orfs_root")"
[[ "$orfs_root" == "/mnt/c/Projects/OpenROAD-flow-scripts" ]] || exit 2
[[ "$(git -C "$orfs_root" -c safe.directory="$orfs_root" rev-parse HEAD)" == "$orfs_commit" ]] || { echo "ORFS commit mismatch" >&2; exit 2; }

if [[ "$variant" == "registered_boundary" ]]; then
  run_parent="$build_root/registered_boundary"
  stage_template="$run_parent/.run.XXXXXX"
  frontend_template="$stage_template/frontend"
  derived_template="$frontend_template/post_proc.v"
else
  output_dir="$(readlink -m "$output_dir")"
  case "$output_dir" in
    "$build_root"/compatibility/*|"$build_root"/lec_disabled/*) ;;
    *) exit 2 ;;
  esac
  stage_template="$output_dir"
  frontend_template="$output_dir/frontend"
  derived_template="$frontend_template/post_proc.v"
fi

if [[ "$dry_run" == "1" ]]; then
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
    "final_publish_dir=$output_dir" \
    "orfs_target=$target"
  exit 0
fi

if [[ "$variant" == "registered_boundary" ]]; then
  [[ ! -e "$output_dir" && ! -L "$output_dir" ]] || { echo "Registered result already exists: $output_dir" >&2; exit 2; }
  mkdir -p "$run_parent"
  run_parent="$(readlink -f "$run_parent")"
  [[ "$run_parent" == "$build_root/registered_boundary" ]] || exit 2
  stage="$(mktemp -d "$run_parent/.run.XXXXXX")"
  stage="$(readlink -f "$stage")"
  [[ "$stage" == "$run_parent"/.run.* ]] || exit 2
  output_work="$stage"
else
  [[ ! -e "$output_dir" ]] || { echo "Output already exists: $output_dir" >&2; exit 2; }
  mkdir -p "$output_dir"
  output_work="$output_dir"
fi

mkdir -p "$output_work/frontend" "$output_work/work"
export SYNTH_TOP="$synth_top"
export SYNTH_FILELIST="$filelist_rel"
export FRONTEND_OUT_DIR="$output_work/frontend"
cd "$repo_root"
"$yosys_bin" -c physical/nangate45/frontend.tcl -l "$output_work/frontend/yosys.log"
export DERIVED_VERILOG="$output_work/frontend/post_proc.v"
"$yosys_bin" -c physical/nangate45/equivalence.tcl -l "$output_work/frontend/equivalence.log"

set +e
docker run --rm \
  -v "$orfs_root/flow:/OpenROAD-flow-scripts/flow:ro" \
  -v "$repo_root:/work" \
  -e FLOW_HOME=/OpenROAD-flow-scripts/flow \
  -e WORK_HOME="/work/${output_work#"$repo_root/"}/work" \
  -e SYSTOLIC_DERIVED_V="/work/${output_work#"$repo_root/"}/frontend/post_proc.v" \
  -e SYNTH_TOP="$synth_top" \
  -e SYNTH_FILELIST="/work/$filelist_rel" \
  -e FRONTEND_OUT_DIR="/work/${output_work#"$repo_root/"}/frontend" \
  -e DERIVED_VERILOG="/work/${output_work#"$repo_root/"}/frontend/post_proc.v" \
  -e OPENROAD_NUM_THREADS="$threads" \
  -e OMP_NUM_THREADS="$threads" \
  "$image" bash -lc \
  "source /OpenROAD-flow-scripts/env.sh >/dev/null; cd /OpenROAD-flow-scripts/flow; make -j1 DESIGN_CONFIG=/work/$config_rel $target" \
  > "$output_work/docker.log" 2>&1
run_rc=$?
set -e
printf '%s\n' "$run_rc" > "$output_work/docker.exitcode"
{
  echo "image=$image"
  echo "variant=$variant"
  echo "top=$synth_top"
  echo "config=$config_rel"
  echo "threads=$threads"
  echo "target=$target"
  echo "utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$output_work/manifest.txt"

if [[ "$run_rc" -eq 0 && "$variant" == "registered_boundary" ]]; then
  mv "$output_work" "$output_dir"
fi
exit "$run_rc"
