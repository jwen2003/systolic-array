# Generic synthesis flow driven by environment variables from run_synth.sh.
set n $::env(SYNTH_N)
set k $::env(SYNTH_K)
set data_w $::env(SYNTH_DATA_W)
set acc_w $::env(SYNTH_ACC_W)
set out_dir $::env(SYNTH_OUT_DIR)

yosys read_slang --top systolic_array_top \
    -G N=$n -G K=$k -G DATA_W=$data_w -G ACC_W=$acc_w \
    rtl/systolic_pe.sv \
    rtl/systolic_array.sv \
    rtl/input_feeder.sv \
    rtl/systolic_controller.sv \
    rtl/systolic_array_top.sv

yosys hierarchy -check -top systolic_array_top
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
