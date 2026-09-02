# Butterfly 400 MHz evaluation convention, adapted to the systolic top-level protocol.
create_clock -name core_clock -period 2.000 [get_ports clk]
set_clock_uncertainty 0.050 [get_clocks core_clock]
set_clock_transition 0.050 [get_clocks core_clock]

# Matrix inputs are stable throughout busy, but their first-cycle path remains timed.
set data_inputs [get_ports {start a_matrix* b_matrix*}]
set_input_delay 0.250 -clock core_clock $data_inputs
set_input_transition 0.050 $data_inputs
set_output_delay 0.250 -clock core_clock [all_outputs]
set_load 0.010 [all_outputs]

# Reset is synchronous functional control and is excluded only from performance paths.
set_false_path -from [get_ports rst_n]
