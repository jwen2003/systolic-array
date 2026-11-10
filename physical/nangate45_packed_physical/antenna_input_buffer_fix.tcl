# Keep the identified AXI read-address input buffer close to its top-edge pin.
# The fixed location is a legal site in the last standard-cell row.  Detailed
# placement still validates legalization, and the logical netlist is unchanged.

set block [ord::get_db_block]
set inst [$block findInst input31]
if {$inst == "NULL"} {
  utl::error ANT 1 "Required input buffer input31 was not found."
}
if {[[$inst getMaster] getName] ne "BUF_X1"} {
  utl::error ANT 2 "input31 is not the expected BUF_X1 instance."
}

set x_um 77.90
set y_um 154.00
$inst setOrient MX
$inst setLocation \
  [ord::microns_to_dbu [expr {double($x_um)}]] \
  [ord::microns_to_dbu [expr {double($y_um)}]]
$inst setPlacementStatus FIRM
utl::info ANT 3 "Fixed input31 at ($x_um, $y_um), orientation MX."
