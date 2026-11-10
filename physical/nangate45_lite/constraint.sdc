# V2 Lite-only active-operation experiment at a nominal 2.5 ns target.
set clock_port [get_ports clk]
create_clock -name core_clk -period 2.500 $clock_port
set_clock_uncertainty 0.050 [get_clocks core_clk]
set_clock_transition 0.050 [get_clocks core_clk]

# Experimental external-interface budget reused from the V1 comparison point.
# These values are assumptions, not measurements of a concrete AXI interconnect.
set axi_inputs [get_ports {s_axi_awaddr* s_axi_awprot* s_axi_awvalid \
    s_axi_wdata* s_axi_wstrb* s_axi_wvalid s_axi_bready \
    s_axi_araddr* s_axi_arprot* s_axi_arvalid s_axi_rready}]
set_input_delay -clock core_clk -max 0.250 $axi_inputs
set_input_delay -clock core_clk -min 0.000 $axi_inputs
set_input_transition 0.050 $axi_inputs
set_output_delay -clock core_clk -max 0.250 [all_outputs]
set_output_delay -clock core_clk -min 0.000 [all_outputs]
set_load 0.010 [all_outputs]

# rst_n is synchronous active-low. Active-operation STA assumes reset is
# released before an operation and stable throughout it; reset interface
# assertion/deassertion timing is outside this experiment.
set_false_path -from [get_ports rst_n]
