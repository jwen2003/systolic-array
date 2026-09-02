# Nangate45 N2/K2 registered-boundary implementation.
registered_config_dir := $(dir $(lastword $(MAKEFILE_LIST)))
include $(registered_config_dir)../nangate45/config.mk

override export DESIGN_NAME = systolic_array_pipelined_top
override export DESIGN_NICKNAME = systolic_array_pipelined_n2_k2
override export SDC_FILE = /work/physical/nangate45_registered/constraint.sdc
override export CLOCK_PERIOD = 2.000

override export SYNTH_N = 2
override export SYNTH_K = 2
override export SYNTH_DATA_W = 8
override export SYNTH_ACC_W = 18

override export LEC_CHECK = 0
