# Nangate45 N2/K2 reference implementation.
export PLATFORM = nangate45
export DESIGN_NAME = systolic_array_top
export DESIGN_NICKNAME = systolic_array_n2_k2

export VERILOG_FILES = $(SYSTOLIC_DERIVED_V)
export SDC_FILE = /work/physical/nangate45/constraint.sdc

export CLOCK_PORT = clk
export CLOCK_PERIOD = 2.500
export CORE_UTILIZATION = 50
export CORE_ASPECT_RATIO = 1
export PLACE_DENSITY_LB_ADDON = 0.10

# Kepler Formal exits with SIGILL on the Ryzen 7 7730U host.
# Official Nangate45/GCD reproduces the failure, and three pinned official
# images reproduce kepler-formal --help exit 132. Physical transformations
# remain enabled; independent equivalence evidence is handled separately.
export LEC_CHECK = 0
