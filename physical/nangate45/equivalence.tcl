# Compare the lowered read_slang design with the generated backend Verilog.
set derived_v $::env(DERIVED_VERILOG)

yosys read_slang --top systolic_array_top \
    -G N=2 -G K=2 -G DATA_W=8 -G ACC_W=18 \
    rtl/systolic_pe.sv rtl/systolic_array.sv rtl/input_feeder.sv \
    rtl/systolic_controller.sv rtl/systolic_array_top.sv
yosys hierarchy -check -top systolic_array_top
yosys proc
yosys opt
yosys rename systolic_array_top gold
yosys design -stash gold_design

yosys read_verilog $derived_v
yosys hierarchy -check -top systolic_array_top
yosys proc
yosys opt
yosys rename systolic_array_top gate
yosys design -stash gate_design
yosys design -reset
yosys design -copy-from gold_design -as gold gold
yosys design -copy-from gate_design -as gate gate
yosys equiv_make gold gate equiv
yosys hierarchy -top equiv
yosys equiv_simple
yosys equiv_induct -undef -seq 10
yosys equiv_status -assert
