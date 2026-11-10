#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
orfs_commit="6101364b2d7909dd797e1e3e7f80695401cfa4e4"
image="openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0"
run_parent="$repo_root/build/openroad/v2_lite_physical"
run_variant="${PHYSICAL_RUN:-baseline}"
case "$run_variant" in
  baseline)
    final_name="baseline_2p5ns"
    config_rel="physical/nangate45_lite_physical/config.mk"
    ;;
  cap_margin_10)
    final_name="cap_margin_10_2p5ns"
    config_rel="physical/nangate45_lite_physical/config_cap_margin_10.mk"
    ;;
  antenna_input_buffer_fix)
    run_parent="$repo_root/build/openroad/v2_lite_antenna"
    final_name="input_buffer_fix_2p5ns"
    config_rel="physical/nangate45_lite_physical/config_antenna_input_buffer_fix.mk"
    ;;
  *)
    echo "PHYSICAL_RUN must be baseline, cap_margin_10, or antenna_input_buffer_fix" >&2
    exit 2
    ;;
esac
final_dir="$run_parent/$final_name"
threads="${OPENROAD_THREADS:-16}"

[[ "$threads" =~ ^[1-9][0-9]*$ ]] || { echo "OPENROAD_THREADS must be positive" >&2; exit 2; }
[[ -n "${ORFS_ROOT:-}" ]] || { echo "ORFS_ROOT is required" >&2; exit 2; }
orfs_root="$(readlink -f -- "$ORFS_ROOT")"
[[ -d "$orfs_root/.git" ]] || { echo "ORFS_ROOT is not a Git checkout" >&2; exit 2; }
[[ "$(git -C "$orfs_root" rev-parse HEAD)" == "$orfs_commit" ]] || { echo "ORFS commit mismatch" >&2; exit 2; }

yosys_bin="${OSS_CAD_SUITE_ROOT:-$HOME/.local/opt/oss-cad-suite-20260830}/bin/yosys"
[[ -x "$yosys_bin" ]] || { echo "Pinned read_slang Yosys not found" >&2; exit 2; }
for rel in \
  synth/filelists/systolic_axi_lite_top.f \
  physical/nangate45_lite/frontend.tcl \
  physical/nangate45_lite/equivalence.tcl \
  physical/nangate45_lite/constraint.sdc \
  physical/nangate45_lite_physical/final_audit.tcl \
  physical/nangate45_lite_physical/antenna_input_buffer_fix.tcl \
  "$config_rel"; do
  [[ -f "$repo_root/$rel" ]] || { echo "Missing input: $rel" >&2; exit 2; }
done
docker image inspect "$image" >/dev/null
[[ ! -e "$final_dir" && ! -L "$final_dir" ]] || { echo "Result already exists: $final_dir" >&2; exit 2; }

mkdir -p "$run_parent"
stage="$(mktemp -d "$run_parent/.run.XXXXXX")"
failure_dir="$run_parent/failed_$(date -u +%Y%m%dT%H%M%SZ)"
preserve_failure() {
  rc=$?
  if [[ $rc -ne 0 && -d "$stage" ]]; then
    printf '%s\n' "$rc" > "$stage/exit_code.txt"
    mv "$stage" "$failure_dir"
    echo "Failure evidence preserved at $failure_dir" >&2
  fi
  exit "$rc"
}
trap preserve_failure EXIT
mkdir -p "$stage/frontend" "$stage/work"

cd "$repo_root"
export FRONTEND_OUT_DIR="$stage/frontend"
"$yosys_bin" -c physical/nangate45_lite/frontend.tcl -l "$stage/frontend/yosys.log"
export DERIVED_VERILOG="$stage/frontend/post_proc.v"
"$yosys_bin" -c physical/nangate45_lite/equivalence.tcl -l "$stage/frontend/equivalence.log"

stage_rel="${stage#"$repo_root/"}"
set +e
docker run --rm \
  -v "$orfs_root/flow:/OpenROAD-flow-scripts/flow:ro" \
  -v "$repo_root:/work" \
  -e FLOW_HOME=/OpenROAD-flow-scripts/flow \
  -e WORK_HOME="/work/$stage_rel/work" \
  -e SYSTOLIC_DERIVED_V="/work/$stage_rel/frontend/post_proc.v" \
  -e OPENROAD_NUM_THREADS="$threads" \
  -e OMP_NUM_THREADS="$threads" \
  "$image" bash -lc \
  "source /OpenROAD-flow-scripts/env.sh >/dev/null; cd /OpenROAD-flow-scripts/flow; make -j1 DESIGN_CONFIG=/work/$config_rel finish drc" \
  > "$stage/docker.log" 2>&1
rc=$?
set -e
printf '%s\n' "$rc" > "$stage/docker.exitcode"
[[ $rc -eq 0 ]] || exit "$rc"

result_rel="$stage_rel/work/results/nangate45/systolic_axi_lite_n2_k17_constant_decode/base"
mkdir -p "$stage/final_audit"
docker run --rm \
  -v "$orfs_root/flow:/OpenROAD-flow-scripts/flow:ro" \
  -v "$repo_root:/work" \
  -e FINAL_ODB="/work/$result_rel/6_final.odb" \
  -e FINAL_SDC="/work/$result_rel/6_final.sdc" \
  -e FINAL_SPEF="/work/$result_rel/6_final.spef" \
  -e FINAL_AUDIT_DIR="/work/$stage_rel/final_audit" \
  "$image" bash -lc \
  'source /OpenROAD-flow-scripts/env.sh >/dev/null; openroad -exit /work/physical/nangate45_lite_physical/final_audit.tcl' \
  > "$stage/final_audit/openroad.log" 2>&1

test -s "$stage/final_audit/critical_path.json"
test -s "$stage/final_audit/reg_to_reg_max.rpt"
test -s "$stage/final_audit/device_write_max.rpt"

{
  echo "utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "git_head=$(git rev-parse HEAD)"
  echo "git_status_begin"; git status --porcelain; echo "git_status_end"
  echo "orfs_commit=$orfs_commit"
  echo "image=$image"
  docker image inspect "$image" --format 'image_id={{.Id}} image_created={{.Created}} image_arch={{.Architecture}}'
  docker run --rm "$image" bash -lc 'source /OpenROAD-flow-scripts/env.sh >/dev/null; yosys -V; openroad -version; sta -version'
  echo "top=systolic_axi_lite_top"
  echo "N=2"; echo "K=17"; echo "DATA_W=8"; echo "ACC_W=18"; echo "PACKED_ENABLE=0"
  echo "clock_period_ns=2.500"
  echo "core_utilization=50"; echo "core_aspect_ratio=1"; echo "place_density_lb_addon=0.10"
  echo "physical_run=$run_variant"
  echo "config=$config_rel"
  echo "sdc=physical/nangate45_lite/constraint.sdc"
} > "$stage/manifest.txt"

{
  sha256sum rtl/core/*.sv rtl/wrapper/axi_lite_slave.sv rtl/wrapper/systolic_device.sv \
    rtl/wrapper/systolic_axi_lite_top.sv synth/filelists/systolic_axi_lite_top.f \
    physical/nangate45_lite/frontend.tcl physical/nangate45_lite/equivalence.tcl \
    physical/nangate45_lite/constraint.sdc physical/nangate45_lite_physical/final_audit.tcl \
    physical/nangate45_lite_physical/antenna_input_buffer_fix.tcl \
    "$config_rel"
} > "$stage/input_sha256.txt"

mv "$stage" "$final_dir"
trap - EXIT
echo "V2 Lite physical flow completed: $final_dir"
