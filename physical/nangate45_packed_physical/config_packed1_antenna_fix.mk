include /work/physical/nangate45_packed_physical/config_packed1.mk

# Relocate only the existing input buffer identified by the baseline KLayout
# Metal6 antenna marker.  No logical cell or timing exception is added.
export PRE_DETAIL_PLACE_TCL = /work/physical/nangate45_packed_physical/antenna_input_buffer_fix.tcl
