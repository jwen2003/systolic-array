# Generic synthesis flow driven by environment variables from run_synth.sh.
set n $::env(SYNTH_N)
set k $::env(SYNTH_K)
set data_w $::env(SYNTH_DATA_W)
set acc_w $::env(SYNTH_ACC_W)
set out_dir $::env(SYNTH_OUT_DIR)

set top systolic_array_top
if {[info exists ::env(SYNTH_TOP)]} {
    set top $::env(SYNTH_TOP)
    if {![regexp {^[A-Za-z_][A-Za-z0-9_$]*$} $top]} {
        error "SYNTH_TOP is not a valid SystemVerilog identifier: $top"
    }
}

set rtl_files [list \
    rtl/systolic_pe.sv \
    rtl/systolic_array.sv \
    rtl/input_feeder.sv \
    rtl/systolic_controller.sv \
    rtl/systolic_array_top.sv]

if {[info exists ::env(SYNTH_FILELIST)]} {
    set filelist_path $::env(SYNTH_FILELIST)
    if {$filelist_path eq ""} {
        error "SYNTH_FILELIST must not be empty"
    }
    if {![file isfile $filelist_path]} {
        error "SYNTH_FILELIST does not name a readable file: $filelist_path"
    }

    set rtl_files [list]
    set filelist_handle [open $filelist_path r]
    set filelist_data [read $filelist_handle]
    close $filelist_handle
    foreach line [split $filelist_data "\n"] {
        set source_path [string trim $line]
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

yosys read_slang --top $top \
    -G N=$n -G K=$k -G DATA_W=$data_w -G ACC_W=$acc_w \
    {*}$rtl_files

yosys hierarchy -check -top $top
yosys tee -o $out_dir/elaboration_check.rpt check
yosys proc
yosys opt
yosys tee -o $out_dir/post_proc_check.rpt check
yosys write_verilog -noattr $out_dir/post_proc.v
yosys memory
yosys opt
yosys tee -o $out_dir/pretech_check.rpt check
yosys tee -o $out_dir/pretech_stat.rpt stat -width
yosys write_json $out_dir/pretech.json
yosys techmap
yosys opt
yosys tee -o $out_dir/final_check.rpt check
yosys tee -o $out_dir/stat.rpt stat -width
yosys write_verilog -noattr $out_dir/generic_netlist.v
yosys write_json $out_dir/generic_netlist.json
