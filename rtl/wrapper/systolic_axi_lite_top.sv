`timescale 1ns/1ps

// Structural integration only: AXI adapter -> device -> frozen baseline V1 core.
// Single clock, synchronous active-low reset shared by all three instances.
// s_axi_*addr contains a device-relative BYTE offset, not a system address.
// The interconnect/host must subtract the accelerator base before this port.
// No new FSM, result copy, or backpressure connection to the core is added here.
module systolic_axi_lite_top #(
    parameter int unsigned N = 2,
    parameter int unsigned K = 2,
    parameter int unsigned DATA_W = 8,
    parameter int unsigned ACC_W = 18
) (
    input  logic clk,
    input  logic rst_n,
    input  logic [31:0] s_axi_awaddr,
    input  logic [2:0] s_axi_awprot,
    input  logic s_axi_awvalid,
    output logic s_axi_awready,
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0] s_axi_wstrb,
    input  logic s_axi_wvalid,
    output logic s_axi_wready,
    output logic [1:0] s_axi_bresp,
    output logic s_axi_bvalid,
    input  logic s_axi_bready,
    input  logic [31:0] s_axi_araddr,
    input  logic [2:0] s_axi_arprot,
    input  logic s_axi_arvalid,
    output logic s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0] s_axi_rresp,
    output logic s_axi_rvalid,
    input  logic s_axi_rready
);
    logic wr_en, wr_error, rd_en, rd_error;
    logic [31:0] wr_addr, wr_data, rd_addr, rd_data;
    logic [3:0] wr_strb;
    logic core_start, core_busy, core_done;
    logic signed [DATA_W-1:0] a_matrix [N-1:0][K-1:0];
    logic signed [DATA_W-1:0] b_matrix [K-1:0][N-1:0];
    logic signed [ACC_W-1:0] core_result [N-1:0][N-1:0];

    axi_lite_slave u_slave (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awprot(s_axi_awprot),
        .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arprot(s_axi_arprot),
        .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .wr_strb(wr_strb), .wr_error(wr_error),
        .rd_en(rd_en), .rd_addr(rd_addr), .rd_data(rd_data), .rd_error(rd_error)
    );

    systolic_device #(.N(N), .K(K), .DATA_W(DATA_W), .ACC_W(ACC_W)) u_device (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .wr_strb(wr_strb), .wr_error(wr_error),
        .rd_en(rd_en), .rd_addr(rd_addr), .rd_data(rd_data), .rd_error(rd_error),
        .core_start(core_start), .core_busy(core_busy), .core_done(core_done),
        .a_matrix(a_matrix), .b_matrix(b_matrix), .core_result(core_result)
    );

    systolic_array_top #(.N(N), .K(K), .DATA_W(DATA_W), .ACC_W(ACC_W)) u_core (
        .clk(clk), .rst_n(rst_n), .start(core_start),
        .a_matrix(a_matrix), .b_matrix(b_matrix),
        .busy(core_busy), .done(core_done), .result(core_result)
    );
endmodule
