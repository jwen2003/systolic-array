# High-precision post-synthesis path diagnostics for the fixed V2 Lite baseline.
set sta_report_default_digits 6

read_liberty $::env(NANGATE45_LIBERTY)
read_verilog $::env(MAPPED_NETLIST)
link_design systolic_axi_lite_top
read_sdc $::env(STA_SDC)
set_wire_load_model -name 5K_hvratio_1_1

set reg_data [all_registers -data_pins]

puts "=== EXACT_INPUT_TO_REGISTER ==="
report_checks -from [get_ports {s_axi_araddr[12]}] \
  -to [get_pins {u_slave.s_axi_rdata_reg[10]$_SDFFE_PN0P_/D}] \
  -path_delay max -format full_clock_expanded \
  -fields {slew cap input_pin net fanout} -digits 6

puts "=== EXACT_REGISTER_TO_REGISTER ==="
report_checks -from [get_pins {u_slave.awaddr_saved[5]$_SDFFE_PN0P_/Q}] \
  -to [get_pins {u_device.a_matrix[136]$_DFFE_PP_/D}] \
  -path_delay max -format full_clock_expanded \
  -fields {slew cap input_pin net fanout} -digits 6

puts "=== NEIGHBOR_INPUT_TO_REGISTER ==="
report_checks -from [all_inputs] -to $reg_data -path_delay max \
  -format full_clock_expanded -fields {slew cap input_pin net fanout} \
  -group_path_count 10 -endpoint_path_count 1 -digits 6

puts "=== NEIGHBOR_REGISTER_TO_REGISTER ==="
report_checks -from [all_registers -clock_pins] -to $reg_data -path_delay max \
  -format full_clock_expanded -fields {slew cap input_pin net fanout} \
  -group_path_count 10 -endpoint_path_count 1 -digits 6

puts "=== ELECTRICAL_VIOLATIONS ==="
report_check_types -max_slew -max_capacitance -max_fanout -violators
