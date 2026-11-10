# Post-synthesis STA on the mapped netlist, before floorplan or placement.
set lib_file $::env(NANGATE45_LIBERTY)
set netlist $::env(MAPPED_NETLIST)
set sdc_file $::env(STA_SDC)

read_liberty $lib_file
read_verilog $netlist
link_design systolic_axi_lite_top
read_sdc $sdc_file

# The Liberty default wire-load model is the only interconnect estimate here.
set_wire_load_model -name 5K_hvratio_1_1

puts "=== REPORT_BEGIN check_setup ==="
check_setup -verbose
puts "=== REPORT_END check_setup ==="
puts "=== REPORT_BEGIN units ==="
report_units
puts "=== REPORT_END units ==="
puts "=== REPORT_BEGIN timing_summary ==="
report_wns
report_tns
report_worst_slack
report_wns -min
report_tns -min
report_worst_slack -min
puts "=== REPORT_END timing_summary ==="
puts "=== REPORT_BEGIN constraints_max ==="
report_checks -path_delay max -format full_clock_expanded \
    -fields {slew cap input_pin net fanout} -group_path_count 10 -endpoint_path_count 1
puts "=== REPORT_END constraints_max ==="
puts "=== REPORT_BEGIN constraints_min ==="
report_checks -path_delay min -format full_clock_expanded \
    -fields {slew cap input_pin net fanout} -group_path_count 10 -endpoint_path_count 1
puts "=== REPORT_END constraints_min ==="

set reg_clk [all_registers -clock_pins]
set reg_data [all_registers -data_pins]
puts "=== REPORT_BEGIN reg_to_reg_max ==="
report_checks -from $reg_clk -to $reg_data -path_delay max \
    -format full_clock_expanded -fields {slew cap input_pin net fanout} \
    -group_path_count 10 -endpoint_path_count 1
puts "=== REPORT_END reg_to_reg_max ==="
puts "=== REPORT_BEGIN input_to_reg_max ==="
report_checks -from [all_inputs] -to $reg_data -path_delay max \
    -format full_clock_expanded -fields {slew cap input_pin net fanout} \
    -group_path_count 10 -endpoint_path_count 1
puts "=== REPORT_END input_to_reg_max ==="
puts "=== REPORT_BEGIN reg_to_output_max ==="
report_checks -from $reg_clk -to [all_outputs] -path_delay max \
    -format full_clock_expanded -fields {slew cap input_pin net fanout} \
    -group_path_count 10 -endpoint_path_count 1
puts "=== REPORT_END reg_to_output_max ==="
puts "=== REPORT_BEGIN input_to_output_max ==="
report_checks -from [all_inputs] -to [all_outputs] -path_delay max \
    -format full_clock_expanded -fields {slew cap input_pin net fanout} \
    -group_path_count 10 -endpoint_path_count 1
puts "=== REPORT_END input_to_output_max ==="
puts "=== REPORT_BEGIN violations ==="
report_check_types -max_slew -max_capacitance -max_fanout -violators
puts "=== REPORT_END violations ==="
