read_liberty $::env(NANGATE45_LIBERTY)
read_verilog $::env(MAPPED_NETLIST)
link_design $::env(SYNTH_TOP)
read_sdc $::env(STA_SDC)
set_wire_load_model -name 5K_hvratio_1_1

proc audit_redirect {path command} {
  sta::redirect_file_begin $path
  uplevel 1 $command
  sta::redirect_file_end
}

set audit_dir $::env(PACKED_PATH_DIR)
file mkdir $audit_dir
set path_fields {slew cap input_pin net fanout}
set matrix_data [get_pins -hierarchical {u_device.*_matrix*/D}]
set bitmap_data [get_pins -hierarchical {u_device.*_written*/D}]
set current_addr_q [get_pins -hierarchical {u_burst.current_addr*/Q u_burst.current_addr*/QN}]

audit_redirect $audit_dir/current_addr_to_matrix.rpt {
  report_checks -from $current_addr_q -to $matrix_data -path_delay max \
    -format full_clock_expanded -fields $path_fields -group_path_count 10 \
    -endpoint_path_count 1 -digits 6
}
audit_redirect $audit_dir/current_addr_to_bitmap.rpt {
  report_checks -from $current_addr_q -to $bitmap_data -path_delay max \
    -format full_clock_expanded -fields $path_fields -group_path_count 10 \
    -endpoint_path_count 1 -digits 6
}

foreach bit {8 16 24 31} {
  set port [get_ports [format {s_burst_wdata[%d]} $bit]]
  audit_redirect [file join $audit_dir [format {wdata_%d_to_matrix.rpt} $bit]] {
    report_checks -from $port -to $matrix_data -path_delay max \
      -format full_clock_expanded -fields $path_fields -group_path_count 10 \
      -endpoint_path_count 1 -digits 6
  }
}

foreach bit {1 2 3} {
  set port [get_ports [format {s_burst_wstrb[%d]} $bit]]
  audit_redirect [file join $audit_dir [format {wstrb_%d_to_bitmap.rpt} $bit]] {
    report_checks -from $port -to $bitmap_data -path_delay max \
      -format full_clock_expanded -fields $path_fields -group_path_count 10 \
      -endpoint_path_count 1 -digits 6
  }
}

audit_redirect $audit_dir/object_counts.rpt {
  puts "current_addr_q [llength $current_addr_q]"
  puts "matrix_data [llength $matrix_data]"
  puts "bitmap_data [llength $bitmap_data]"
}
