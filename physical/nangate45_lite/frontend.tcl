# Normalize the V2 Lite-only SystemVerilog design for the ORFS Verilog frontend.
set top systolic_axi_lite_top
set filelist synth/filelists/systolic_axi_lite_top.f
set out_dir $::env(FRONTEND_OUT_DIR)

set handle [open $filelist r]
set text [read $handle]
close $handle
set rtl_files [list]
foreach raw_line [split $text "\n"] {
    set source [string trim $raw_line]
    if {$source eq "" || [string match {#*} $source]} { continue }
    if {![file isfile $source]} { error "Missing RTL source: $source" }
    lappend rtl_files $source
}
if {[llength $rtl_files] == 0} { error "Empty synthesis filelist: $filelist" }

yosys read_slang --top $top \
    -G N=2 -G K=17 -G DATA_W=8 -G ACC_W=18 \
    {*}$rtl_files
yosys hierarchy -check -top $top
yosys tee -o $out_dir/elaboration_check.rpt check
yosys tee -o $out_dir/elaboration_stat.rpt stat -width
yosys proc
yosys opt
yosys tee -o $out_dir/post_proc_check.rpt check
yosys tee -o $out_dir/post_proc_stat.rpt stat -width
# Lower word-level mux/demux cells that the Verilog backend otherwise emits as
# Yosys-internal primitives (for example $bwmux) not accepted by read_verilog.
yosys techmap
yosys opt
yosys tee -o $out_dir/normalized_check.rpt check
yosys tee -o $out_dir/normalized_stat.rpt stat -width
yosys write_verilog -noattr $out_dir/post_proc.v
yosys write_json $out_dir/post_proc.json
