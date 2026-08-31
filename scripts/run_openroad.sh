#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
orfs_root="${ORFS_ROOT:-/mnt/c/Projects/OpenROAD-flow-scripts}"
image="openroad/orfs@sha256:d995618be9f2bcdfa5538b885123463070dfbf178bea1818716d4652fe0fa380"
yosys_bin="/home/yttlj2003/.local/opt/oss-cad-suite-20260830/bin/yosys"
build_root="$repo_root/build/openroad"
formal_dir="$build_root/n2_k2"

orfs_root="$(readlink -f "$orfs_root")"
[[ "$orfs_root" == "/mnt/c/Projects/OpenROAD-flow-scripts" ]] || { echo "Unexpected ORFS path" >&2; exit 1; }
[[ "$(git -C "$orfs_root" -c safe.directory="$orfs_root" rev-parse HEAD)" == "6101364b2d7909dd797e1e3e7f80695401cfa4e4" ]] || { echo "ORFS commit mismatch" >&2; exit 1; }
mkdir -p "$build_root"
stage="$(mktemp -d "$build_root/.run.XXXXXX")"
stage="$(readlink -f "$stage")"
[[ "$stage" == "$build_root"/.run.* ]] || exit 1
preserve_failure() {
  if [[ -d "$stage" && "$stage" == "$build_root"/.run.* ]]; then
    failed_dir="$build_root/failed_n2_k2"
    [[ ! -e "$failed_dir" ]] || mv "$failed_dir" "$stage/previous_failure"
    mv "$stage" "$failed_dir"
  fi
}
trap 'preserve_failure' ERR

mkdir -p "$stage/frontend" "$stage/work"
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
  "$image" bash -lc \
  'source /OpenROAD-flow-scripts/env.sh >/dev/null; cd /OpenROAD-flow-scripts/flow; make DESIGN_CONFIG=/work/physical/nangate45/config.mk'

{
  echo "utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "git_commit=$(git -C "$repo_root" rev-parse HEAD)"
  echo "orfs_root=$orfs_root"
  echo "orfs_commit=6101364b2d7909dd797e1e3e7f80695401cfa4e4"
  echo "image=$image"
  echo "clock_period_ns=2.500"
} > "$stage/run_manifest.txt"

if [[ -d "$formal_dir" ]]; then mv "$formal_dir" "$stage/previous"; fi
mv "$stage" "$formal_dir"
rm -rf -- "$formal_dir/previous"
trap - ERR
echo "OpenROAD N2/K2 flow completed."
