# Generate the Verilog-2005 backend input from the selected SystemVerilog variant.
set top systolic_array_top
if {[info exists ::env(SYNTH_TOP)]} {
    set top $::env(SYNTH_TOP)
}
if {![regexp {^[A-Za-z_][A-Za-z0-9_$]*$} $top]} {
    error "Invalid SYNTH_TOP SystemVerilog identifier: $top"
}

set rtl_files [list \
    rtl/systolic_pe.sv \
    rtl/systolic_array.sv \
    rtl/input_feeder.sv \
    rtl/systolic_controller.sv \
    rtl/systolic_array_top.sv]
if {[info exists ::env(SYNTH_FILELIST)]} {
    set filelist_path [string trim $::env(SYNTH_FILELIST)]
    if {$filelist_path eq ""} {
        error "SYNTH_FILELIST must not be empty"
    }
    if {![file isfile $filelist_path]} {
        error "SYNTH_FILELIST does not exist: $filelist_path"
    }
    set filelist_handle [open $filelist_path r]
    set filelist_text [read $filelist_handle]
    close $filelist_handle
    set rtl_files [list]
    foreach raw_line [split $filelist_text "\n"] {
        set source_path [string trim $raw_line]
        if {$source_path eq "" || [string match {#*} $source_path]} {
            continue
        }
        if {![file isfile $source_path]} {
            error "RTL source from SYNTH_FILELIST does not exist: $source_path"
        }
        lappend rtl_files $source_path
    }
    if {[llength $rtl_files] == 0} {
        error "SYNTH_FILELIST contains no RTL sources: $filelist_path"
    }
}

set out_dir $::env(FRONTEND_OUT_DIR)

yosys read_slang --top $top \
    -G N=2 -G K=2 -G DATA_W=8 -G ACC_W=18 \
    {*}$rtl_files
yosys hierarchy -check -top $top
yosys tee -o $out_dir/elaboration_check.rpt check
yosys proc
yosys opt
yosys tee -o $out_dir/post_proc_check.rpt check
yosys tee -o $out_dir/post_proc_stat.rpt stat -width
yosys write_verilog -noattr $out_dir/post_proc.v
yosys write_json $out_dir/post_proc.json
