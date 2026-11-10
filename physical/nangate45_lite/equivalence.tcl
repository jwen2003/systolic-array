# Prove the read_slang source design equivalent to its generated Verilog.
set top systolic_axi_lite_top
set filelist synth/filelists/systolic_axi_lite_top.f
set derived_v $::env(DERIVED_VERILOG)

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

yosys read_slang --top $top \
    -G N=2 -G K=17 -G DATA_W=8 -G ACC_W=18 \
    {*}$rtl_files
yosys hierarchy -check -top $top
yosys proc
yosys opt
yosys rename $top gold
yosys design -stash gold_design

yosys read_verilog $derived_v
yosys hierarchy -check -top $top
yosys proc
yosys opt
yosys rename $top gate
yosys design -stash gate_design
yosys design -reset
yosys design -copy-from gold_design -as gold gold
yosys design -copy-from gate_design -as gate gate
yosys equiv_make gold gate equiv
yosys hierarchy -top equiv
yosys equiv_simple
yosys equiv_induct -undef -seq 10
yosys equiv_status -assert
