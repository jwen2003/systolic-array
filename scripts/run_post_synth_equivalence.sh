#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
if [[ -z "${ORFS_ROOT:-}" ]]; then
  echo "ORFS_ROOT is required. Example: export ORFS_ROOT=/path/to/OpenROAD-flow-scripts" >&2
  exit 2
fi
orfs_root="$(readlink -f -- "$ORFS_ROOT")"
image="openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0"
expected_orfs_commit="6101364b2d7909dd797e1e3e7f80695401cfa4e4"
timeout_seconds="${EQUIV_TIMEOUT_SECONDS:-600}"
run_root="$repo_root/build/openroad/lec_disabled/systolic_n2_k2_full"
output_dir="$run_root/post_synth_equivalence"
derived_verilog="$run_root/frontend/post_proc.v"
mapped_verilog="$run_root/work/results/nangate45/systolic_array_n2_k2/base/1_2_yosys.v"
cell_models="$orfs_root/tools/OpenROAD/test/Nangate45/work_around_yosys/cells.v"

test -d "$orfs_root/.git"
test "$(git -C "$orfs_root" rev-parse HEAD)" = "$expected_orfs_commit"
docker image inspect "$image" >/dev/null
test -s "$derived_verilog"
test -s "$mapped_verilog"
test -s "$cell_models"
mkdir -p "$output_dir"

set +e
timeout --signal=TERM --kill-after=30s "$timeout_seconds" docker run --rm \
  -v "$orfs_root/flow:/OpenROAD-flow-scripts/flow:ro" \
  -v "$orfs_root/tools/OpenROAD/test/Nangate45:/orfs-nangate45-test:ro" \
  -v "$repo_root:/work:ro" \
  -v "$output_dir:/equivalence-output" \
  -e DERIVED_VERILOG=/work/${derived_verilog#"$repo_root"/} \
  -e MAPPED_VERILOG=/work/${mapped_verilog#"$repo_root"/} \
  -e NANGATE_CELL_MODELS=/orfs-nangate45-test/work_around_yosys/cells.v \
  "$image" bash -lc \
  'source /OpenROAD-flow-scripts/env.sh >/dev/null; yosys -c /work/physical/nangate45/post_synth_equivalence.tcl -l /equivalence-output/equivalence.log'
run_rc=$?
set -e
printf '%s\n' "$run_rc" > "$output_dir/exitcode"
if [[ "$run_rc" -eq 0 ]]; then
  printf '%s\n' "proven" > "$output_dir/status"
elif [[ "$run_rc" -eq 124 ]]; then
  printf '%s\n' "inconclusive_tool_scalability" > "$output_dir/status"
else
  printf '%s\n' "failed_or_interrupted" > "$output_dir/status"
fi
exit "$run_rc"
