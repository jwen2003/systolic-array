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

audit_redirect $audit_dir/check_setup.rpt {
  check_setup -verbose -unconstrained_endpoints -no_input_delay -no_output_delay -loops
}
audit_redirect $audit_dir/critical_path.json {
  report_checks -path_delay max -format json -group_path_count 1 -endpoint_path_count 1
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
