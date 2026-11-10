set audit_dir $::env(FINAL_AUDIT_DIR)
file mkdir $audit_dir

read_liberty /OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib
read_db $::env(FINAL_ODB)
read_sdc $::env(FINAL_SDC)
read_spef $::env(FINAL_SPEF)

proc audit_redirect {path command} {
  sta::redirect_file_begin $path
  uplevel 1 $command
  sta::redirect_file_end
}

set reg_clk [all_registers -clock_pins]
set reg_data [all_registers -data_pins]
set awaddr_q [get_pins -hierarchical {u_slave.awaddr_saved*/Q}]
set matrix_data [get_pins -hierarchical {u_device.*_matrix*/D}]
set path_fields {slew cap input_pin net fanout}

audit_redirect $audit_dir/check_setup.rpt {
  check_setup -verbose -unconstrained_endpoints -no_input_delay -no_output_delay -loops
}
audit_redirect $audit_dir/setup_paths.rpt {
  report_checks -path_delay max -format full_clock_expanded -fields $path_fields \
      -group_path_count 10 -endpoint_path_count 1 -digits 6
}
audit_redirect $audit_dir/hold_paths.rpt {
  report_checks -path_delay min -format full_clock_expanded -fields $path_fields \
      -group_path_count 10 -endpoint_path_count 1 -digits 6
}
audit_redirect $audit_dir/reg_to_reg_max.rpt {
  report_checks -from $reg_clk -to $reg_data -path_delay max \
      -format full_clock_expanded -fields $path_fields \
      -group_path_count 10 -endpoint_path_count 1 -digits 6
}
audit_redirect $audit_dir/input_to_reg_max.rpt {
  report_checks -from [all_inputs] -to $reg_data -path_delay max \
      -format full_clock_expanded -fields $path_fields \
      -group_path_count 10 -endpoint_path_count 1 -digits 6
}
audit_redirect $audit_dir/reg_to_output_max.rpt {
  report_checks -from $reg_clk -to [all_outputs] -path_delay max \
      -format full_clock_expanded -fields $path_fields \
      -group_path_count 10 -endpoint_path_count 1 -digits 6
}
audit_redirect $audit_dir/input_to_output_max.rpt {
  report_checks -from [all_inputs] -to [all_outputs] -path_delay max \
      -format full_clock_expanded -fields $path_fields \
      -group_path_count 10 -endpoint_path_count 1 -digits 6
}
audit_redirect $audit_dir/device_write_max.rpt {
  report_checks -from $awaddr_q -to $matrix_data -path_delay max \
      -format full_clock_expanded -fields $path_fields \
      -group_path_count 10 -endpoint_path_count 1 -digits 6
}
audit_redirect $audit_dir/critical_path.json {
  report_checks -path_delay max -format json -group_path_count 1 -endpoint_path_count 1
}
audit_redirect $audit_dir/electrical_violations.rpt {
  report_check_types -max_slew -max_capacitance -max_fanout -violators
}
audit_redirect $audit_dir/clock_latency.rpt {
  report_clock_latency -include_internal_latency -digits 6
}
audit_redirect $audit_dir/clock_skew_setup.rpt {
  report_clock_skew -setup -include_internal_latency -digits 6
}
audit_redirect $audit_dir/clock_skew_hold.rpt {
  report_clock_skew -hold -include_internal_latency -digits 6
}
