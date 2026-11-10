include /work/physical/nangate45_lite_physical/config_cap_margin_10.mk

# The hook relocates only the two input buffers identified by the KLayout
# metal6 antenna markers.  Detailed placement still validates legalization.
export PRE_DETAIL_PLACE_TCL = /work/physical/nangate45_lite_physical/antenna_input_buffer_fix.tcl
