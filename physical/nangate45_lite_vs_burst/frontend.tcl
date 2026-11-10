set top $::env(SYNTH_TOP)
set filelist $::env(SYNTH_FILELIST)
set out_dir $::env(FRONTEND_OUT_DIR)
set handle [open $filelist r]; set text [read $handle]; close $handle
set rtl_files [list]
foreach raw_line [split $text "\n"] {
    set source [string trim $raw_line]
    if {$source eq "" || [string match {#*} $source]} { continue }
    if {![file isfile $source]} { error "Missing RTL source: $source" }
    lappend rtl_files $source
}
if {[llength $rtl_files] == 0} { error "Empty filelist" }
set args [list --top $top -G N=2 -G K=17 -G DATA_W=8 -G ACC_W=18]
if {$top eq "systolic_axi_burst_top"} {
    set packed_enable 0
    if {[info exists ::env(PACKED_ENABLE)]} { set packed_enable $::env(PACKED_ENABLE) }
    if {$packed_enable ni {0 1}} { error "PACKED_ENABLE must be 0 or 1" }
    lappend args -G PACKED_ENABLE=$packed_enable
}
yosys read_slang {*}$args {*}$rtl_files
yosys hierarchy -check -top $top
yosys tee -o $out_dir/elaboration_check.rpt check
yosys proc; yosys opt
yosys tee -o $out_dir/post_proc_check.rpt check
yosys techmap; yosys opt
yosys tee -o $out_dir/normalized_check.rpt check
yosys write_verilog -noattr $out_dir/post_proc.v
yosys write_json $out_dir/post_proc.json
