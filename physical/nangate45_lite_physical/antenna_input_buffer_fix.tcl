# Keep the two AXI read-address input buffers close to their bottom-edge pins.
# KLayout identifies the original long metal6 pin-to-buffer routes as antenna
# violations.  The fixed locations are legal sites in the first standard-cell
# row and preserve the synthesized netlist and all interface timing semantics.

set block [ord::get_db_block]

foreach placement {
  {input30 52.06 1.40 R0}
  {input31 52.63 1.40 R0}
} {
  lassign $placement inst_name x_um y_um orient
  set inst [$block findInst $inst_name]
  if {$inst == "NULL"} {
    utl::error ANT 1 "Required input buffer $inst_name was not found."
  }
  if {[[$inst getMaster] getName] ne "BUF_X1"} {
    utl::error ANT 2 "$inst_name is not the expected BUF_X1 instance."
  }
  set x_dbu [ord::microns_to_dbu [expr {double($x_um)}]]
  set y_dbu [ord::microns_to_dbu [expr {double($y_um)}]]
  $inst setOrient $orient
  $inst setLocation $x_dbu $y_dbu
  $inst setPlacementStatus FIRM
  utl::info ANT 3 "Fixed $inst_name at ($x_um, $y_um), orientation $orient."
}
