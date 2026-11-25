#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
build_root="${DOUBLE_BUFFER_PHYSICAL_BUILD_ROOT:-$repo_root/build/openroad/v2_n8k8_double_buffer_physical}"
orfs_commit=6101364b2d7909dd797e1e3e7f80695401cfa4e4
image='openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0'
threads="${OPENROAD_THREADS:-16}"

[[ "$threads" =~ ^[1-9][0-9]*$ ]] || { echo 'OPENROAD_THREADS must be positive' >&2; exit 2; }
[[ -n "${ORFS_ROOT:-}" ]] || { echo 'ORFS_ROOT is required' >&2; exit 2; }
orfs_root="$(readlink -f -- "$ORFS_ROOT")"
[[ -d "$orfs_root/.git" ]] || { echo 'ORFS_ROOT is not a Git checkout' >&2; exit 2; }
[[ "$(git -C "$orfs_root" rev-parse HEAD)" == "$orfs_commit" ]] || { echo 'ORFS commit mismatch' >&2; exit 2; }
yosys_bin="${OSS_CAD_SUITE_ROOT:-$HOME/.local/opt/oss-cad-suite-20260830}/bin/yosys"
[[ -x "$yosys_bin" ]] || { echo "Missing pinned Yosys: $yosys_bin" >&2; exit 2; }
for rel in physical/nangate45_lite_vs_burst/constraint_burst.sdc; do
  [[ -f "$repo_root/$rel" ]] || { echo "Missing input: $rel" >&2; exit 2; }
done
docker image inspect "$image" >/dev/null
mkdir -p "$build_root"

write_frontend() {
  local path="$1"
  cat >"$path" <<'TCL'
set top $::env(SYNTH_TOP)
set out $::env(FRONTEND_OUT_DIR)
set h [open $::env(SYNTH_FILELIST) r]
set text [read $h]
close $h
set files [list]
foreach raw [split $text "\n"] {
  set file [string trim $raw]
  if {$file ne "" && ![string match {#*} $file]} { lappend files $file }
}
yosys read_slang --top $top -G N=8 -G K=8 -G DATA_W=8 -G ACC_W=18 -G PACKED_ENABLE=1 {*}$files
yosys hierarchy -check -top $top
yosys tee -o $out/elaboration_check.rpt check
yosys proc
yosys opt
yosys tee -o $out/post_proc_check.rpt check
yosys write_verilog -noattr $out/post_proc.v
yosys write_json $out/post_proc.json
TCL
}

write_audit() {
  local path="$1"
  cat >"$path" <<'TCL'
set out $::env(FINAL_AUDIT_DIR)
file mkdir $out
read_liberty /OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib
read_db $::env(FINAL_ODB)
read_sdc $::env(FINAL_SDC)
read_spef $::env(FINAL_SPEF)

proc save_report {path command} {
  sta::redirect_file_begin $path
  uplevel 1 $command
  sta::redirect_file_end
}
set fields {slew cap input_pin net fanout}
set reg_clk [all_registers -clock_pins]
set reg_data [all_registers -data_pins]
save_report $out/check_setup.rpt {check_setup -verbose -unconstrained_endpoints -no_input_delay -no_output_delay -loops}
save_report $out/setup_top5.rpt {report_checks -path_delay max -format full_clock_expanded -fields $fields -group_path_count 5 -endpoint_path_count 1 -digits 6}
save_report $out/hold_top5.rpt {report_checks -path_delay min -format full_clock_expanded -fields $fields -group_path_count 5 -endpoint_path_count 1 -digits 6}
save_report $out/critical_path.json {report_checks -path_delay max -format json -group_path_count 1 -endpoint_path_count 1}
save_report $out/electrical_violations.rpt {report_check_types -max_slew -max_capacitance -max_fanout -violators}
save_report $out/clock_latency.rpt {report_clock_latency -include_internal_latency -digits 6}
save_report $out/clock_skew_setup.rpt {report_clock_skew -setup -include_internal_latency -digits 6}
save_report $out/clock_skew_hold.rpt {report_clock_skew -hold -include_internal_latency -digits 6}

set cycle_idx [get_pins -hierarchical {u_core.u_controller.cycle_idx*/Q u_core.u_controller.cycle_idx*/QN}]
set storage [get_pins -hierarchical {u_device.a_matrix*/Q u_device.b_matrix*/Q u_device.a_bank*/Q u_device.b_bank*/Q}]
set active_bank [get_pins -hierarchical {u_device.active_bank*/Q u_device.active_bank*/QN}]
set pe [get_pins -hierarchical {u_core.u_array.*u_pe.psum_out*/D}]
save_report $out/cycle_idx_to_pe.rpt {
  puts "cycle_idx_count [llength $cycle_idx] pe_count [llength $pe]"
  report_checks -from $cycle_idx -to $pe -path_delay max -format full_clock_expanded -fields $fields -group_path_count 5 -endpoint_path_count 1 -digits 6
}
save_report $out/storage_to_pe.rpt {
  puts "storage_count [llength $storage] pe_count [llength $pe]"
  report_checks -from $storage -to $pe -path_delay max -format full_clock_expanded -fields $fields -group_path_count 5 -endpoint_path_count 1 -digits 6
}
if {[llength $active_bank]} {
  save_report $out/active_bank_to_pe.rpt {
    puts "active_bank_count [llength $active_bank] pe_count [llength $pe]"
    report_checks -from $active_bank -to $pe -path_delay max -format full_clock_expanded -fields $fields -group_path_count 5 -endpoint_path_count 1 -digits 6
  }
}
TCL
}

run_one() {
  local variant="$1" top="$2" adapter="$3" device="$4" top_file="$5"
  local final="$build_root/$variant"
  [[ ! -e "$final" && ! -L "$final" ]] || { echo "Result exists: $final" >&2; return 2; }
  local stage failure
  stage="$(mktemp -d "$build_root/.run.${variant}.XXXXXX")"
  failure="$build_root/failed_${variant}_$(date -u +%Y%m%dT%H%M%SZ)"
  preserve() {
    local rc=$?
    if [[ $rc -ne 0 && -d "$stage" ]]; then
      echo "$rc" >"$stage/exit_code.txt"
      mv "$stage" "$failure"
      echo "Preserved failed run: $failure" >&2
    fi
    return "$rc"
  }
  trap preserve RETURN
  mkdir -p "$stage/frontend" "$stage/work" "$stage/final_audit"
  cp "$repo_root/physical/nangate45_lite_vs_burst/constraint_burst.sdc" "$stage/constraint.sdc"
  write_frontend "$stage/frontend.tcl"
  write_audit "$stage/final_audit.tcl"
  cat >"$stage/filelist.f" <<EOF
rtl/core/systolic_pe.sv
rtl/core/systolic_array.sv
rtl/core/input_feeder.sv
rtl/core/systolic_controller.sv
rtl/core/systolic_array_top.sv
rtl/wrapper/axi_lite_slave.sv
rtl/wrapper/$adapter
rtl/wrapper/$device
rtl/wrapper/$top_file
EOF
  local stage_rel="${stage#"$repo_root/"}"
  local nickname="${top}_n8_k8_packed_physical"
  cat >"$stage/config.mk" <<EOF
export PLATFORM = nangate45
export DESIGN_NAME = $top
export DESIGN_NICKNAME = $nickname
export VERILOG_FILES = \$(SYSTOLIC_DERIVED_V)
export SDC_FILE = /work/$stage_rel/constraint.sdc
export CLOCK_PORT = clk
export CLOCK_PERIOD = 2.500
export CORE_UTILIZATION = 50
export CORE_ASPECT_RATIO = 1
export PLACE_DENSITY_LB_ADDON = 0.10
export LEC_CHECK = 0
EOF

  cd "$repo_root"
  export SYNTH_TOP="$top" SYNTH_FILELIST="$stage/filelist.f" FRONTEND_OUT_DIR="$stage/frontend"
  "$yosys_bin" -c "$stage/frontend.tcl" -l "$stage/frontend/yosys.log" >"$stage/frontend/console.log" 2>&1
  export DERIVED_VERILOG="$stage/frontend/post_proc.v"
  echo 'not_run: large N8/K8 source-to-derived formal is outside this physical gate; post-route equivalence is not proven.' >"$stage/frontend/equivalence_status.txt"

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
    "source /OpenROAD-flow-scripts/env.sh >/dev/null; cd /OpenROAD-flow-scripts/flow; make -j1 DESIGN_CONFIG=/work/$stage_rel/config.mk finish" \
    >"$stage/docker.log" 2>&1
  local rc=$?
  set -e
  echo "$rc" >"$stage/docker.exitcode"
  [[ $rc -eq 0 ]] || return "$rc"

  local result_rel="$stage_rel/work/results/nangate45/$nickname/base"
  for artifact in 6_final.odb 6_final.sdc 6_final.spef 6_final.gds; do
    [[ -s "$repo_root/$result_rel/$artifact" ]] || { echo "Missing final artifact: $artifact" >&2; return 1; }
  done
  docker run --rm \
    -v "$orfs_root/flow:/OpenROAD-flow-scripts/flow:ro" \
    -v "$repo_root:/work" \
    -e FINAL_ODB="/work/$result_rel/6_final.odb" \
    -e FINAL_SDC="/work/$result_rel/6_final.sdc" \
    -e FINAL_SPEF="/work/$result_rel/6_final.spef" \
    -e FINAL_AUDIT_DIR="/work/$stage_rel/final_audit" \
    "$image" bash -lc \
    "source /OpenROAD-flow-scripts/env.sh >/dev/null; openroad -exit /work/$stage_rel/final_audit.tcl" \
    >"$stage/final_audit/openroad.log" 2>&1
  [[ -s "$stage/final_audit/critical_path.json" ]] || return 1

  {
    echo "utc=$(date -u +%FT%TZ)"
    echo "git_head=$(git rev-parse HEAD)"
    echo git_status_begin; git status --porcelain; echo git_status_end
    echo "top=$top"; echo N=8; echo K=8; echo DATA_W=8; echo ACC_W=18; echo PACKED_ENABLE=1
    echo clock_period_ns=2.500; echo clock_uncertainty_ns=0.050
    echo input_delay_max_ns=0.250; echo input_delay_min_ns=0.000
    echo output_delay_max_ns=0.250; echo output_delay_min_ns=0.000
    echo input_transition_ns=0.050; echo output_load_pf=0.010
    echo core_utilization=50; echo core_aspect_ratio=1; echo place_density_lb_addon=0.10
    echo "orfs_commit=$orfs_commit"; echo "image=$image"
    docker image inspect "$image" --format 'image_id={{.Id}} image_created={{.Created}} image_arch={{.Architecture}}'
    "$yosys_bin" -V
    docker run --rm "$image" bash -lc 'source /OpenROAD-flow-scripts/env.sh >/dev/null; yosys -V; openroad -version; sta -version; klayout -v'
  } >"$stage/manifest.txt"
  (while read -r file; do sha256sum "$file"; done <"$stage/filelist.f") >"$stage/source_sha256.txt"
  sha256sum "$stage/filelist.f" "$stage/constraint.sdc" "$stage/config.mk" "$stage/frontend.tcl" "$stage/final_audit.tcl" >"$stage/flow_sha256.txt"
  mv "$stage" "$final"
  trap - RETURN
  echo "Completed $variant: $final"
}

case "${PHYSICAL_VARIANTS:-both}" in
  single)
    run_one single systolic_axi_burst_top axi_burst_write_slave.sv systolic_device.sv systolic_axi_burst_top.sv
    ;;
  dual)
    run_one dual systolic_axi_dual_bank_top axi_dual_bank_burst_write_slave.sv systolic_dual_bank_device.sv systolic_axi_dual_bank_top.sv
    ;;
  both)
    run_one single systolic_axi_burst_top axi_burst_write_slave.sv systolic_device.sv systolic_axi_burst_top.sv
    run_one dual systolic_axi_dual_bank_top axi_dual_bank_burst_write_slave.sv systolic_dual_bank_device.sv systolic_axi_dual_bank_top.sv
    ;;
  *) echo 'PHYSICAL_VARIANTS must be single, dual, or both' >&2; exit 2 ;;
esac
echo "N8/K8 physical results: $build_root"
