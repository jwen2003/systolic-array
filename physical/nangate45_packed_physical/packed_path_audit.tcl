set audit_dir $::env(PACKED_PATH_AUDIT_DIR)
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

set current_addr_q [get_pins -hierarchical {u_burst.current_addr*/Q}]
set matrix_data [get_pins -hierarchical {u_device.*_matrix*/D}]
set bitmap_data [get_pins -hierarchical {u_device.*_written*/D}]
set path_fields {slew cap input_pin net fanout}

if {[llength $current_addr_q] == 0 || [llength $matrix_data] == 0 || [llength $bitmap_data] == 0} {
  error "Packed path audit pin selection is empty"
}

audit_redirect $audit_dir/current_addr_to_matrix.rpt {
  report_checks -from $current_addr_q -to $matrix_data -path_delay max \
    -format full_clock_expanded -fields $path_fields \
    -group_path_count 10 -endpoint_path_count 1 -digits 6
}
audit_redirect $audit_dir/current_addr_to_bitmap.rpt {
  report_checks -from $current_addr_q -to $bitmap_data -path_delay max \
    -format full_clock_expanded -fields $path_fields \
    -group_path_count 10 -endpoint_path_count 1 -digits 6
}
