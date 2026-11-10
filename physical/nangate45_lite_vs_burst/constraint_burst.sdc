create_clock -name core_clk -period 2.500 [get_ports clk]
set_clock_uncertainty 0.050 [get_clocks core_clk]
set_clock_transition 0.050 [get_clocks core_clk]
set axi_inputs [get_ports {s_axi_awaddr* s_axi_awprot* s_axi_awvalid s_axi_wdata* s_axi_wstrb* s_axi_wvalid s_axi_bready s_axi_araddr* s_axi_arprot* s_axi_arvalid s_axi_rready s_burst_awaddr* s_burst_awlen* s_burst_awsize* s_burst_awburst* s_burst_awvalid s_burst_wdata* s_burst_wstrb* s_burst_wlast s_burst_wvalid s_burst_bready}]
set_input_delay -clock core_clk -max 0.250 $axi_inputs
set_input_delay -clock core_clk -min 0.000 $axi_inputs
set_input_transition 0.050 $axi_inputs
set_output_delay -clock core_clk -max 0.250 [all_outputs]
set_output_delay -clock core_clk -min 0.000 [all_outputs]
set_load 0.010 [all_outputs]
# Synchronous active-low reset is stable during the active-operation experiment.
set_false_path -from [get_ports rst_n]
