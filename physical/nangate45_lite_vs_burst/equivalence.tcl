set top $::env(SYNTH_TOP)
set filelist $::env(SYNTH_FILELIST)
set derived_v $::env(DERIVED_VERILOG)
set handle [open $filelist r]; set text [read $handle]; close $handle
set rtl_files [list]
foreach raw_line [split $text "\n"] {
    set source [string trim $raw_line]
    if {$source eq "" || [string match {#*} $source]} { continue }
    lappend rtl_files $source
}
set args [list --top $top -G N=2 -G K=17 -G DATA_W=8 -G ACC_W=18]
if {$top eq "systolic_axi_burst_top"} {
    set packed_enable 0
    if {[info exists ::env(PACKED_ENABLE)]} { set packed_enable $::env(PACKED_ENABLE) }
    if {$packed_enable ni {0 1}} { error "PACKED_ENABLE must be 0 or 1" }
    lappend args -G PACKED_ENABLE=$packed_enable
}
yosys read_slang {*}$args {*}$rtl_files
yosys hierarchy -check -top $top
yosys proc; yosys opt; yosys rename $top gold; yosys design -stash gold_design
yosys read_verilog $derived_v
yosys hierarchy -check -top $top
yosys proc; yosys opt; yosys rename $top gate; yosys design -stash gate_design
yosys design -reset
yosys design -copy-from gold_design -as gold gold
yosys design -copy-from gate_design -as gate gate
yosys equiv_make gold gate equiv
yosys hierarchy -top equiv
yosys equiv_simple
yosys equiv_induct -undef -seq 10
yosys equiv_status -assert
