#!/usr/bin/env bash
set -euo pipefail

image="${1:?immutable image reference required}"
output_dir="${2:?output directory required}"
threads="${3:-16}"
target="${4:-finish}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
orfs_root="${ORFS_ROOT:-/mnt/c/Projects/OpenROAD-flow-scripts}"
yosys_bin="/home/yttlj2003/.local/opt/oss-cad-suite-20260830/bin/yosys"

orfs_root="$(readlink -f "$orfs_root")"
output_dir="$(readlink -m "$output_dir")"
build_root="$(readlink -f "$repo_root/build/openroad")"
[[ "$orfs_root" == "/mnt/c/Projects/OpenROAD-flow-scripts" ]] || exit 2
case "$output_dir" in
  "$build_root"/compatibility/*|"$build_root"/lec_disabled/*) ;;
  *) exit 2 ;;
esac
[[ ! -e "$output_dir" ]] || { echo "Output already exists: $output_dir" >&2; exit 2; }
mkdir -p "$output_dir/frontend" "$output_dir/work"

export FRONTEND_OUT_DIR="$output_dir/frontend"
cd "$repo_root"
"$yosys_bin" -c physical/nangate45/frontend.tcl -l "$output_dir/frontend/yosys.log"
export DERIVED_VERILOG="$output_dir/frontend/post_proc.v"
"$yosys_bin" -c physical/nangate45/equivalence.tcl -l "$output_dir/frontend/equivalence.log"

set +e
docker run --rm \
  -v "$orfs_root/flow:/OpenROAD-flow-scripts/flow:ro" \
  -v "$repo_root:/work" \
  -e FLOW_HOME=/OpenROAD-flow-scripts/flow \
  -e WORK_HOME="/work/${output_dir#"$repo_root/"}/work" \
  -e SYSTOLIC_DERIVED_V="/work/${output_dir#"$repo_root/"}/frontend/post_proc.v" \
  -e OPENROAD_NUM_THREADS="$threads" \
  -e OMP_NUM_THREADS="$threads" \
  "$image" bash -lc \
  "source /OpenROAD-flow-scripts/env.sh >/dev/null; cd /OpenROAD-flow-scripts/flow; make -j1 DESIGN_CONFIG=/work/physical/nangate45/config.mk $target" \
  > "$output_dir/docker.log" 2>&1
run_rc=$?
set -e
printf '%s\n' "$run_rc" > "$output_dir/docker.exitcode"
{
  echo "image=$image"
  echo "threads=$threads"
  echo "target=$target"
  echo "utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$output_dir/manifest.txt"
exit "$run_rc"
