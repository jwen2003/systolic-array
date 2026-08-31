set gold_file $::env(DERIVED_VERILOG)
set gate_file $::env(MAPPED_VERILOG)
set cell_models $::env(NANGATE_CELL_MODELS)

yosys read_verilog $gold_file
yosys prep -top systolic_array_top -flatten
yosys rename systolic_array_top gold
yosys design -stash gold

yosys design -reset
yosys read_verilog $cell_models
yosys read_verilog $gate_file
yosys prep -top systolic_array_top -flatten
yosys rename systolic_array_top gate
yosys design -stash gate

yosys design -reset
yosys design -copy-from gold -as gold gold
yosys design -copy-from gate -as gate gate
yosys equiv_make gold gate equiv
yosys hierarchy -top equiv
yosys equiv_simple -seq 10
yosys equiv_induct -undef -seq 10
yosys equiv_status -assert
