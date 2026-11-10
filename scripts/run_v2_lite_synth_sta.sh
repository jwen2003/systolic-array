#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
orfs_commit="6101364b2d7909dd797e1e3e7f80695401cfa4e4"
image="openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0"
build_parent="$repo_root/build/v2_lite_synth_sta"
final_dir="$build_parent/n2_k17_2p5ns"

if [[ -z "${ORFS_ROOT:-}" ]]; then
  echo "ORFS_ROOT is required. Example: export ORFS_ROOT=/path/to/OpenROAD-flow-scripts" >&2
  exit 2
fi
orfs_root="$(readlink -f -- "$ORFS_ROOT")"
[[ -d "$orfs_root/.git" ]] || { echo "ORFS_ROOT is not a Git checkout" >&2; exit 2; }
[[ "$(git -C "$orfs_root" rev-parse HEAD)" == "$orfs_commit" ]] || { echo "ORFS commit mismatch" >&2; exit 2; }

yosys_bin="${OSS_CAD_SUITE_ROOT:-$HOME/.local/opt/oss-cad-suite-20260830}/bin/yosys"
[[ -x "$yosys_bin" ]] || { echo "Pinned read_slang Yosys not found: $yosys_bin" >&2; exit 2; }
for rel in \
  synth/filelists/systolic_axi_lite_top.f \
  physical/nangate45_lite/config.mk \
  physical/nangate45_lite/constraint.sdc \
  physical/nangate45_lite/frontend.tcl \
  physical/nangate45_lite/equivalence.tcl \
  physical/nangate45_lite/post_synth_sta.tcl; do
  [[ -f "$repo_root/$rel" ]] || { echo "Missing required file: $rel" >&2; exit 2; }
done

mkdir -p "$build_parent"
[[ ! -e "$final_dir" ]] || { echo "Result already exists: $final_dir" >&2; exit 2; }
stage="$(mktemp -d "$build_parent/.run.XXXXXX")"
failure_dir="$build_parent/failed_$(date -u +%Y%m%dT%H%M%SZ)"
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
mkdir -p "$stage/frontend" "$stage/work" "$stage/sta"

cd "$repo_root"
export FRONTEND_OUT_DIR="$stage/frontend"
"$yosys_bin" -c physical/nangate45_lite/frontend.tcl -l "$stage/frontend/yosys.log"
export DERIVED_VERILOG="$stage/frontend/post_proc.v"
"$yosys_bin" -c physical/nangate45_lite/equivalence.tcl -l "$stage/frontend/equivalence.log"

repo_rel_stage="${stage#"$repo_root/"}"
docker run --rm \
  -v "$orfs_root/flow:/OpenROAD-flow-scripts/flow:ro" \
  -v "$repo_root:/work" \
  -e FLOW_HOME=/OpenROAD-flow-scripts/flow \
  -e WORK_HOME="/work/$repo_rel_stage/work" \
  -e SYSTOLIC_DERIVED_V="/work/$repo_rel_stage/frontend/post_proc.v" \
  "$image" bash -lc \
  'source /OpenROAD-flow-scripts/env.sh >/dev/null; cd /OpenROAD-flow-scripts/flow; make -j1 DESIGN_CONFIG=/work/physical/nangate45_lite/config.mk synth'

mapped_netlist="$(find "$stage/work/results" -type f -name '1_2_yosys.v' -print -quit)"
[[ -s "$mapped_netlist" ]] || { echo "Mapped netlist not found" >&2; exit 1; }
mapped_container="/work/${mapped_netlist#"$repo_root/"}"
sta_container="/work/${stage#"$repo_root/"}/sta"
docker run --rm \
  -v "$orfs_root/flow:/OpenROAD-flow-scripts/flow:ro" \
  -v "$repo_root:/work" \
  -e NANGATE45_LIBERTY=/OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib \
  -e MAPPED_NETLIST="$mapped_container" \
  -e STA_SDC=/work/physical/nangate45_lite/constraint.sdc \
  -e STA_REPORT_DIR="$sta_container" \
  "$image" bash -lc \
  'source /OpenROAD-flow-scripts/env.sh >/dev/null; sta -exit /work/physical/nangate45_lite/post_synth_sta.tcl' \
  > "$stage/sta/openroad_sta.log" 2>&1
if grep -q '^Error:' "$stage/sta/openroad_sta.log"; then
  echo "OpenSTA reported an error" >&2
  exit 1
fi

{
  echo "utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "git_head=$(git rev-parse HEAD)"
  echo "git_status_begin"
  git status --porcelain
  echo "git_status_end"
  echo "orfs_commit=$orfs_commit"
  echo "image=$image"
  echo "top=systolic_axi_lite_top"
  echo "N=2"
  echo "K=17"
  echo "DATA_W=8"
  echo "ACC_W=18"
  echo "clock_period_ns=2.500"
  echo "clock_uncertainty_ns=0.050"
  echo "input_delay_max_ns=0.250"
  echo "input_delay_min_ns=0.000"
  echo "output_delay_max_ns=0.250"
  echo "output_delay_min_ns=0.000"
  echo "input_transition_ns=0.050"
  echo "output_load_pf=0.010"
  echo "interconnect_model=Liberty_default_wire_load_5K_hvratio_1_1"
  echo "liberty=NangateOpenCellLibrary_typical.lib"
  echo "corner=typical_1.10V_25C"
  "$yosys_bin" -V
  docker image inspect "$image" --format 'image_id={{.Id}} image_created={{.Created}} image_arch={{.Architecture}}'
  docker run --rm "$image" bash -lc \
    'source /OpenROAD-flow-scripts/env.sh >/dev/null; yosys -V; openroad -version; sta -version'
} > "$stage/manifest.txt"

while IFS= read -r source; do
  [[ -z "$source" || "$source" == \#* ]] && continue
  (cd "$repo_root" && sha256sum "$source")
done < "$repo_root/synth/filelists/systolic_axi_lite_top.f" > "$stage/source_sha256.txt"

mv "$stage" "$final_dir"
trap - EXIT
echo "V2 Lite-only synthesis and post-synthesis STA completed: $final_dir"
