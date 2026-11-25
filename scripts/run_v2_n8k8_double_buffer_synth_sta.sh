#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
build_root="${DOUBLE_BUFFER_SYNTH_BUILD_ROOT:-$repo_root/build/v2_n8k8_double_buffer_synth_sta}"
orfs_commit=6101364b2d7909dd797e1e3e7f80695401cfa4e4
image='openroad/orfs@sha256:73bd87efa06758865277f347fbc6b932642d8ab21a5430c5ce5480aaa60c27d0'
[[ -n "${ORFS_ROOT:-}" ]] || { echo 'ORFS_ROOT is required' >&2; exit 2; }
orfs_root="$(readlink -f -- "$ORFS_ROOT")"
[[ "$(git -C "$orfs_root" rev-parse HEAD)" == "$orfs_commit" ]] || { echo 'ORFS commit mismatch' >&2; exit 2; }
yosys_bin="${OSS_CAD_SUITE_ROOT:-$HOME/.local/opt/oss-cad-suite-20260830}/bin/yosys"
[[ -x "$yosys_bin" ]] || { echo "Missing pinned Yosys: $yosys_bin" >&2; exit 2; }
docker image inspect "$image" >/dev/null
mkdir -p "$build_root"

write_common_inputs() {
  local dir="$1"
  cp "$repo_root/physical/nangate45_lite_vs_burst/constraint_burst.sdc" "$dir/constraint.sdc"
  cat >"$dir/frontend.tcl" <<'TCL'
set top $::env(SYNTH_TOP); set out $::env(FRONTEND_OUT_DIR)
set h [open $::env(SYNTH_FILELIST) r]; set text [read $h]; close $h
set files [list]; foreach raw [split $text "\n"] {set f [string trim $raw]; if {$f ne "" && ![string match {#*} $f]} {lappend files $f}}
set args [list --top $top -G N=8 -G K=8 -G DATA_W=8 -G ACC_W=18 -G PACKED_ENABLE=1]
yosys read_slang {*}$args {*}$files
yosys hierarchy -check -top $top
yosys tee -o $out/elaboration_check.rpt check
yosys proc; yosys opt
yosys tee -o $out/post_proc_check.rpt check
yosys write_verilog -noattr $out/post_proc.v
yosys write_json $out/post_proc.json
TCL
  cat >"$dir/equivalence.tcl" <<'TCL'
set top $::env(SYNTH_TOP); set h [open $::env(SYNTH_FILELIST) r]; set text [read $h]; close $h
set files [list]; foreach raw [split $text "\n"] {set f [string trim $raw]; if {$f ne "" && ![string match {#*} $f]} {lappend files $f}}
yosys read_slang --top $top -G N=8 -G K=8 -G DATA_W=8 -G ACC_W=18 -G PACKED_ENABLE=1 {*}$files
yosys hierarchy -check -top $top; yosys proc; yosys opt; yosys rename $top gold; yosys design -stash gold_design
yosys read_verilog $::env(DERIVED_VERILOG); yosys hierarchy -check -top $top; yosys proc; yosys opt; yosys rename $top gate; yosys design -stash gate_design
yosys design -reset; yosys design -copy-from gold_design -as gold gold; yosys design -copy-from gate_design -as gate gate
yosys equiv_make gold gate equiv; yosys hierarchy -top equiv; yosys equiv_simple; yosys equiv_induct -undef -seq 10; yosys equiv_status -assert
TCL
  cat >"$dir/path_audit.tcl" <<'TCL'
read_liberty $::env(NANGATE45_LIBERTY)
read_verilog $::env(MAPPED_NETLIST)
link_design $::env(SYNTH_TOP)
read_sdc $::env(STA_SDC)
set_wire_load_model -name 5K_hvratio_1_1
proc save_report {path command} {sta::redirect_file_begin $path; uplevel 1 $command; sta::redirect_file_end}
set out $::env(PATH_AUDIT_DIR); file mkdir $out
set fields {slew cap input_pin net fanout}
save_report $out/global_top5.rpt {report_checks -path_delay max -format full_clock_expanded -fields $fields -group_path_count 5 -endpoint_path_count 1 -digits 6}
if {$::env(SYNTH_TOP) eq "systolic_axi_dual_bank_top"} {
  set storage [get_pins -hierarchical {u_device.a_bank*/Q u_device.b_bank*/Q}]
  set bank_select [get_pins -hierarchical {u_device.active_bank*/Q u_device.active_bank*/QN}]
} else {
  set storage [get_pins -hierarchical {u_device.a_matrix*/Q u_device.b_matrix*/Q}]
  set bank_select [list]
}
set pe [get_pins -hierarchical {u_core.u_array.*u_pe.psum_out*/D}]
set maps [get_pins -hierarchical {u_device.*_written*/Q}]
set control [get_pins -hierarchical {u_device.core_start*/D u_device.state*/D}]
save_report $out/storage_to_pe.rpt {puts "storage_count [llength $storage] pe_count [llength $pe]"; report_checks -from $storage -to $pe -path_delay max -format full_clock_expanded -fields $fields -group_path_count 5 -endpoint_path_count 1 -digits 6}
if {[llength $bank_select]} {save_report $out/bank_select_to_pe.rpt {puts "bank_select_count [llength $bank_select] pe_count [llength $pe]"; report_checks -from $bank_select -to $pe -path_delay max -format full_clock_expanded -fields $fields -group_path_count 5 -endpoint_path_count 1 -digits 6}}
save_report $out/bitmap_to_control.rpt {puts "map_count [llength $maps] control_count [llength $control]"; report_checks -from $maps -to $control -path_delay max -format full_clock_expanded -fields $fields -group_path_count 5 -endpoint_path_count 1 -digits 6}
TCL
}

run_one() {
  local variant="$1" top="$2" adapter="$3" device="$4" top_file="$5"
  local final="$build_root/$variant"
  [[ ! -e "$final" ]] || { echo "Result exists: $final" >&2; return 2; }
  local stage; stage="$(mktemp -d "$build_root/.run.${variant}.XXXXXX")"
  mkdir -p "$stage/frontend" "$stage/work" "$stage/sta" "$stage/paths"
  write_common_inputs "$stage"
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
  local rel="${stage#"$repo_root/"}"
  cat >"$stage/config.mk" <<EOF
export PLATFORM = nangate45
export DESIGN_NAME = $top
export DESIGN_NICKNAME = ${top}_n8_k8_packed
export VERILOG_FILES = \$(SYSTOLIC_DERIVED_V)
export SDC_FILE = /work/$rel/constraint.sdc
export CLOCK_PORT = clk
export CLOCK_PERIOD = 2.500
export CORE_UTILIZATION = 50
export CORE_ASPECT_RATIO = 1
export PLACE_DENSITY_LB_ADDON = 0.10
export LEC_CHECK = 0
EOF
  export SYNTH_TOP="$top" SYNTH_FILELIST="$stage/filelist.f" FRONTEND_OUT_DIR="$stage/frontend"
  (cd "$repo_root" && "$yosys_bin" -c "$stage/frontend.tcl" -l "$stage/frontend/yosys.log") >"$stage/frontend/console.log" 2>&1
  export DERIVED_VERILOG="$stage/frontend/post_proc.v"
  echo 'not_run: N8/K8 source-to-derived equivalence is outside this synthesis/STA gate; an exploratory run showed tool-scalability non-proofs.' >"$stage/frontend/equivalence_status.txt"
  docker run --rm -v "$orfs_root/flow:/OpenROAD-flow-scripts/flow:ro" -v "$repo_root:/work" \
    -e FLOW_HOME=/OpenROAD-flow-scripts/flow -e WORK_HOME="/work/$rel/work" \
    -e SYSTOLIC_DERIVED_V="/work/$rel/frontend/post_proc.v" "$image" bash -lc \
    "source /OpenROAD-flow-scripts/env.sh >/dev/null; cd /OpenROAD-flow-scripts/flow; make -j1 DESIGN_CONFIG=/work/$rel/config.mk synth" \
    >"$stage/synthesis.log" 2>&1
  local mapped; mapped="$(find "$stage/work/results" -name 1_2_yosys.v -type f -print -quit)"; [[ -s "$mapped" ]] || { echo 'Mapped netlist missing' >&2; return 1; }
  local common=(-v "$orfs_root/flow:/OpenROAD-flow-scripts/flow:ro" -v "$repo_root:/work" \
    -e NANGATE45_LIBERTY=/OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib \
    -e MAPPED_NETLIST="/work/${mapped#"$repo_root/"}" -e STA_SDC="/work/$rel/constraint.sdc" -e SYNTH_TOP="$top")
  docker run --rm "${common[@]}" "$image" bash -lc \
    'source /OpenROAD-flow-scripts/env.sh >/dev/null; sta -exit /work/physical/nangate45_lite_vs_burst/post_synth_sta.tcl' >"$stage/sta/openroad_sta.log" 2>&1
  docker run --rm "${common[@]}" -e PATH_AUDIT_DIR="/work/$rel/paths" "$image" bash -lc \
    "source /OpenROAD-flow-scripts/env.sh >/dev/null; sta -exit /work/$rel/path_audit.tcl" >"$stage/paths/opensta.log" 2>&1
  {
    echo "utc=$(date -u +%FT%TZ)"; echo "git_head=$(git -C "$repo_root" rev-parse HEAD)"; git -C "$repo_root" status --porcelain
    echo "top=$top"; echo N=8; echo K=8; echo DATA_W=8; echo ACC_W=18; echo PACKED_ENABLE=1
    echo clock_period_ns=2.500; echo clock_uncertainty_ns=0.050; echo input_delay_max_ns=0.250; echo input_delay_min_ns=0.000
    echo input_transition_ns=0.050; echo output_load_pf=0.010; echo corner=typical_1.10V_25C; echo wire_load=5K_hvratio_1_1
    echo "orfs_commit=$orfs_commit"; echo "image=$image"; "$yosys_bin" -V
    docker run --rm "$image" bash -lc 'source /OpenROAD-flow-scripts/env.sh >/dev/null; yosys -V; openroad -version; sta -version'
  } >"$stage/manifest.txt"
  (cd "$repo_root" && while read -r f; do sha256sum "$f"; done <"$stage/filelist.f") >"$stage/source_sha256.txt"
  (cd "$repo_root" && sha256sum "$stage/filelist.f" "$stage/constraint.sdc" "$stage/config.mk" "$stage/frontend.tcl" "$stage/equivalence.tcl" "$stage/path_audit.tcl") >"$stage/flow_sha256.txt"
  grep -Ei 'packed|16384|20480|32768|36864' "$stage/frontend/post_proc.v" | head -100 >"$stage/packed_evidence.txt" || true
  mv "$stage" "$final"
}

run_one single systolic_axi_burst_top axi_burst_write_slave.sv systolic_device.sv systolic_axi_burst_top.sv
run_one dual systolic_axi_dual_bank_top axi_dual_bank_burst_write_slave.sv systolic_dual_bank_device.sv systolic_axi_dual_bank_top.sv
echo "N8/K8 wrapper synthesis/STA results: $build_root"
