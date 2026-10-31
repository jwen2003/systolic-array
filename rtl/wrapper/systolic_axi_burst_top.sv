`timescale 1ns/1ps

// Lite control/read + restricted Burst writes, sharing Device/Core storage.
// PACKED_ENABLE enables dense INT8 aliases in Device and Burst descriptor decode.
// Single clock, synchronous active-low reset shared by all four instances.
// s_axi_*addr contains a device-relative BYTE offset, not a system address.
// The interconnect/host must subtract the accelerator base before this port.
// Write ownership: Lite has priority when idle. Reserve from the FIRST Lite
// AW or W handshake through B consumption (including partial AW/W arrival).
// A Burst reserves from AW handshake through B consumption. No preemption.
// Lite reads remain independent; simultaneous read/write sees pre-edge data.
// A stalled/malformed writer can block the other writer; no fairness/timeout
// hardware is included. Both masters must share reset and obey VALID holding.
// No backpressure enters the core. Existing Lite-only top is unchanged.
module systolic_axi_burst_top #(
    parameter int unsigned N = 2,
    parameter int unsigned K = 2,
    parameter int unsigned DATA_W = 8,
    parameter int unsigned ACC_W = 18,
    parameter bit PACKED_ENABLE = 0
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
    input  logic s_axi_rready,
    input  logic [31:0] s_burst_awaddr,
    input  logic [7:0] s_burst_awlen,
    input  logic [2:0] s_burst_awsize,
    input  logic [1:0] s_burst_awburst,
    input  logic s_burst_awvalid,
    output logic s_burst_awready,
    input  logic [31:0] s_burst_wdata,
    input  logic [3:0] s_burst_wstrb,
    input  logic s_burst_wlast, s_burst_wvalid,
    output logic s_burst_wready,
    output logic [1:0] s_burst_bresp,
    output logic s_burst_bvalid,
    input  logic s_burst_bready
);
    logic wr_en, wr_error, rd_en, rd_error;
    logic [31:0] wr_addr, wr_data, rd_addr, rd_data;
    logic [3:0] wr_strb;
    logic core_start, core_busy, core_done;
    logic signed [DATA_W-1:0] a_matrix [N-1:0][K-1:0];
    logic signed [DATA_W-1:0] b_matrix [K-1:0][N-1:0];
    logic signed [ACC_W-1:0] core_result [N-1:0][N-1:0];

    logic l_wr_en, b_wr_en, l_awready, l_wready, b_awready;
    logic [31:0] l_addr, l_data, b_addr, b_data;
    logic [3:0] l_strb, b_strb;
    logic lite_aw_owned, lite_w_owned, burst_active, allow_burst_aw;
    assign s_axi_awready = l_awready && !burst_active;
    assign s_axi_wready = l_wready && !burst_active;
    assign allow_burst_aw = !lite_aw_owned && !lite_w_owned
                         && !s_axi_awvalid && !s_axi_wvalid;
    assign s_burst_awready = b_awready && allow_burst_aw;
    assign wr_en = burst_active ? b_wr_en : l_wr_en;
    assign wr_addr = burst_active ? b_addr : l_addr;
    assign wr_data = burst_active ? b_data : l_data;
    assign wr_strb = burst_active ? b_strb : l_strb;
    always_ff @(posedge clk) begin
        if (!rst_n) begin lite_aw_owned <= 0; lite_w_owned <= 0; end
        else begin
            if (s_axi_awvalid && s_axi_awready) lite_aw_owned <= 1;
            if (s_axi_wvalid && s_axi_wready) lite_w_owned <= 1;
            if (s_axi_bvalid && s_axi_bready) begin
                lite_aw_owned <= 0;
                lite_w_owned <= 0;
            end
        end
    end

    axi_lite_slave u_slave (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awprot(s_axi_awprot),
        .s_axi_awvalid(s_axi_awvalid && !burst_active), .s_axi_awready(l_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid && !burst_active), .s_axi_wready(l_wready),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arprot(s_axi_arprot),
        .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .wr_en(l_wr_en), .wr_addr(l_addr), .wr_data(l_data),
        .wr_strb(l_strb), .wr_error(wr_error),
        .rd_en(rd_en), .rd_addr(rd_addr), .rd_data(rd_data), .rd_error(rd_error)
    );

    axi_burst_write_slave #(.PACKED_ENABLE(PACKED_ENABLE), .INPUT_WORDS(N*K), .MAX_BEATS(16)) u_burst (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(s_burst_awaddr), .s_axi_awlen(s_burst_awlen),
        .s_axi_awsize(s_burst_awsize), .s_axi_awburst(s_burst_awburst),
        .s_axi_awvalid(s_burst_awvalid && allow_burst_aw), .s_axi_awready(b_awready),
        .s_axi_wdata(s_burst_wdata), .s_axi_wstrb(s_burst_wstrb),
        .s_axi_wlast(s_burst_wlast), .s_axi_wvalid(s_burst_wvalid),
        .s_axi_wready(s_burst_wready),
        .s_axi_bresp(s_burst_bresp), .s_axi_bvalid(s_burst_bvalid),
        .s_axi_bready(s_burst_bready), .wr_grant(burst_active), .active(burst_active),
        .wr_en(b_wr_en), .wr_addr(b_addr), .wr_data(b_data), .wr_strb(b_strb),
        .wr_error(wr_error)
    );

    systolic_device #(.PACKED_ENABLE(PACKED_ENABLE), .N(N), .K(K), .DATA_W(DATA_W), .ACC_W(ACC_W)) u_device (
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
