#!/usr/bin/env bash
set -euo pipefail

image="${1:?immutable image reference required}"
design_config="${2:?ORFS-relative design config required}"
output_dir="${3:?output directory required}"
threads="${4:-16}"
lec_check="${5-}"
target="${6:-cts}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
if [[ -z "${ORFS_ROOT:-}" ]]; then
  echo "ORFS_ROOT is required. Example: export ORFS_ROOT=/path/to/OpenROAD-flow-scripts" >&2
  exit 2
fi
orfs_root="$ORFS_ROOT"

orfs_root="$(readlink -f -- "$orfs_root")"
[[ -d "$orfs_root" && -d "$orfs_root/.git" ]] || { echo "ORFS_ROOT must name an existing Git checkout" >&2; exit 2; }
[[ "$(git -C "$orfs_root" -c safe.directory="$orfs_root" rev-parse HEAD)" == "6101364b2d7909dd797e1e3e7f80695401cfa4e4" ]] || { echo "ORFS commit mismatch" >&2; exit 2; }
output_dir="$(readlink -m "$output_dir")"
build_root="$(readlink -f "$repo_root/build/openroad")"
case "$output_dir" in
  "$build_root"/compatibility/*|"$build_root"/lec_disabled/*) ;;
  *) exit 2 ;;
esac
[[ ! -e "$output_dir" ]] || { echo "Output already exists: $output_dir" >&2; exit 2; }
mkdir -p "$output_dir/work"

docker_env=(
  -e FLOW_HOME=/OpenROAD-flow-scripts/flow
  -e WORK_HOME="/work/${output_dir#"$repo_root/"}/work"
  -e OPENROAD_NUM_THREADS="$threads"
  -e OMP_NUM_THREADS="$threads"
)
if [[ -n "$lec_check" ]]; then
  docker_env+=(-e LEC_CHECK="$lec_check")
fi

set +e
docker run --rm \
  -v "$orfs_root/flow:/OpenROAD-flow-scripts/flow:ro" \
  -v "$repo_root:/work" \
  "${docker_env[@]}" \
  "$image" bash -lc \
  "source /OpenROAD-flow-scripts/env.sh >/dev/null; cd /OpenROAD-flow-scripts/flow; make -j1 DESIGN_CONFIG=$design_config $target" \
  > "$output_dir/docker.log" 2>&1
run_rc=$?
set -e
printf '%s\n' "$run_rc" > "$output_dir/docker.exitcode"
{
  echo "image=$image"
  echo "design_config=$design_config"
  echo "threads=$threads"
  echo "lec_check=${lec_check:-default}"
  echo "target=$target"
  echo "utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$output_dir/manifest.txt"
exit "$run_rc"
