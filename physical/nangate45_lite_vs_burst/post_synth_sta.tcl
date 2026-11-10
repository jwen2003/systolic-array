read_liberty $::env(NANGATE45_LIBERTY)
read_verilog $::env(MAPPED_NETLIST)
link_design $::env(SYNTH_TOP)
read_sdc $::env(STA_SDC)
set_wire_load_model -name 5K_hvratio_1_1
check_setup -verbose
report_units
report_wns -digits 6
report_tns -digits 6
report_worst_slack -digits 6
report_wns -min -digits 6
report_tns -min -digits 6
report_worst_slack -min -digits 6
report_checks -path_delay max -format full_clock_expanded -fields {slew cap input_pin net fanout} -group_path_count 10 -endpoint_path_count 1
report_checks -path_delay min -format full_clock_expanded -fields {slew cap input_pin net fanout} -group_path_count 10 -endpoint_path_count 1
report_check_types -max_slew -max_capacitance -max_fanout -violators
