# Nangate45 physical implementation of the V2 Lite constant-address decode.
export PLATFORM = nangate45
export DESIGN_NAME = systolic_axi_lite_top
export DESIGN_NICKNAME = systolic_axi_lite_n2_k17_constant_decode
export VERILOG_FILES = $(SYSTOLIC_DERIVED_V)
export SDC_FILE = /work/physical/nangate45_lite/constraint.sdc
export CLOCK_PORT = clk
export CLOCK_PERIOD = 2.500

# The floorplan is derived from this design's mapped area, not copied from V1.
export CORE_UTILIZATION = 50
export CORE_ASPECT_RATIO = 1
export PLACE_DENSITY_LB_ADDON = 0.10

# Kepler Formal is disabled for the documented host CPU SIGILL limitation.
export LEC_CHECK = 0
