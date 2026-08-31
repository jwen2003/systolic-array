# Generate the Verilog-2005 backend input from the frozen SystemVerilog baseline.
set out_dir $::env(FRONTEND_OUT_DIR)

yosys read_slang --top systolic_array_top \
    -G N=2 -G K=2 -G DATA_W=8 -G ACC_W=18 \
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
yosys tee -o $out_dir/post_proc_stat.rpt stat -width
yosys write_verilog -noattr $out_dir/post_proc.v
yosys write_json $out_dir/post_proc.json

