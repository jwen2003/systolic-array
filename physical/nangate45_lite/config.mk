# Nangate45 N2/K17 Lite-only post-synthesis experiment.
export PLATFORM = nangate45
export DESIGN_NAME = systolic_axi_lite_top
export DESIGN_NICKNAME = systolic_axi_lite_n2_k17
export VERILOG_FILES = $(SYSTOLIC_DERIVED_V)
export SDC_FILE = /work/physical/nangate45_lite/constraint.sdc
export CLOCK_PORT = clk
export CLOCK_PERIOD = 2.500

# Keep the same synthesis library and optimization conventions as the V1 flow.
export CORE_UTILIZATION = 50
export CORE_ASPECT_RATIO = 1
export PLACE_DENSITY_LB_ADDON = 0.10
export LEC_CHECK = 0
