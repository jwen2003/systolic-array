#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
orfs_root="${ORFS_ROOT:-/mnt/c/Projects/OpenROAD-flow-scripts}"
image="openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0"
expected_orfs_commit="6101364b2d7909dd797e1e3e7f80695401cfa4e4"
run_root="${1:-$repo_root/build/openroad/lec_disabled/systolic_n2_k2_full}"
run_root="$(readlink -m "$run_root")"
build_root="$(readlink -f "$repo_root/build/openroad")"
case "$run_root" in
  "$build_root"/lec_disabled/systolic_n2_k2_full|"$build_root"/clock_sweep/.run.*|"$build_root"/clock_sweep/clk_*) ;;
  *) echo "Refusing unexpected audit root: $run_root" >&2; exit 2 ;;
esac
result_root="$run_root/work/results/nangate45/systolic_array_n2_k2/base"
audit_root="$run_root/final_audit"

test -d "$orfs_root/.git"
test "$(git -C "$orfs_root" rev-parse HEAD)" = "$expected_orfs_commit"
docker image inspect "$image" >/dev/null
test -s "$result_root/6_final.odb"
test -s "$result_root/6_final.sdc"
test -s "$result_root/6_final.spef"

mkdir -p "$audit_root"
docker run --rm \
  -v "$orfs_root/flow:/OpenROAD-flow-scripts/flow:ro" \
  -v "$repo_root:/work" \
  -e FINAL_ODB=/work/${result_root#"$repo_root"/}/6_final.odb \
  -e FINAL_SDC=/work/${result_root#"$repo_root"/}/6_final.sdc \
  -e FINAL_SPEF=/work/${result_root#"$repo_root"/}/6_final.spef \
  -e FINAL_AUDIT_DIR=/work/${audit_root#"$repo_root"/} \
  "$image" bash -lc \
  'source /OpenROAD-flow-scripts/env.sh >/dev/null; openroad -exit /work/physical/nangate45/final_audit.tcl' \
  > "$audit_root/openroad.log" 2>&1

test -s "$audit_root/check_setup.rpt"
test -s "$audit_root/critical_path.json"
