`timescale 1ns/1ps

// Experimental integration: one Core, two independently loadable input banks,
// Lite control/read access, and restricted Burst writes to either bank.
module systolic_axi_dual_bank_top #(
    parameter int unsigned N=2,K=2,DATA_W=8,ACC_W=18,
    parameter bit PACKED_ENABLE=0
) (
    input logic clk,rst_n,
    input logic [31:0] s_axi_awaddr,input logic [2:0] s_axi_awprot,input logic s_axi_awvalid,output logic s_axi_awready,
    input logic [31:0] s_axi_wdata,input logic [3:0] s_axi_wstrb,input logic s_axi_wvalid,output logic s_axi_wready,
    output logic [1:0] s_axi_bresp,output logic s_axi_bvalid,input logic s_axi_bready,
    input logic [31:0] s_axi_araddr,input logic [2:0] s_axi_arprot,input logic s_axi_arvalid,output logic s_axi_arready,
    output logic [31:0] s_axi_rdata,output logic [1:0] s_axi_rresp,output logic s_axi_rvalid,input logic s_axi_rready,
    input logic [31:0] s_burst_awaddr,input logic [7:0] s_burst_awlen,input logic [2:0] s_burst_awsize,
    input logic [1:0] s_burst_awburst,input logic s_burst_awvalid,output logic s_burst_awready,
    input logic [31:0] s_burst_wdata,input logic [3:0] s_burst_wstrb,input logic s_burst_wlast,s_burst_wvalid,
    output logic s_burst_wready,output logic [1:0] s_burst_bresp,output logic s_burst_bvalid,input logic s_burst_bready
);
    logic wr_en,wr_error,rd_en,rd_error,core_start,core_busy,core_done;
    logic result_available_unused;
    logic [31:0] wr_addr,wr_data,rd_addr,rd_data,l_addr,l_data,b_addr,b_data;
    logic [3:0] wr_strb,l_strb,b_strb; logic l_wr_en,b_wr_en,l_awready,l_wready,b_awready;
    logic lite_aw_owned,lite_w_owned,burst_active,allow_burst_aw;
    logic signed [DATA_W-1:0] a_matrix[N-1:0][K-1:0],b_matrix[K-1:0][N-1:0];
    logic signed [ACC_W-1:0] result[N-1:0][N-1:0];
    assign s_axi_awready=l_awready&&!burst_active; assign s_axi_wready=l_wready&&!burst_active;
    assign allow_burst_aw=!lite_aw_owned&&!lite_w_owned&&!s_axi_awvalid&&!s_axi_wvalid;
    assign s_burst_awready=b_awready&&allow_burst_aw;
    assign wr_en=burst_active?b_wr_en:l_wr_en; assign wr_addr=burst_active?b_addr:l_addr;
    assign wr_data=burst_active?b_data:l_data; assign wr_strb=burst_active?b_strb:l_strb;
    always_ff @(posedge clk) begin
        if(!rst_n) begin lite_aw_owned<=0;lite_w_owned<=0;end else begin
            if(s_axi_awvalid&&s_axi_awready) lite_aw_owned<=1;
            if(s_axi_wvalid&&s_axi_wready) lite_w_owned<=1;
            if(s_axi_bvalid&&s_axi_bready) begin lite_aw_owned<=0;lite_w_owned<=0;end
        end
    end
    axi_lite_slave u_slave(.*,.s_axi_awready(l_awready),.s_axi_wready(l_wready),
        .s_axi_awvalid(s_axi_awvalid&&!burst_active),.s_axi_wvalid(s_axi_wvalid&&!burst_active),
        .wr_en(l_wr_en),.wr_addr(l_addr),.wr_data(l_data),.wr_strb(l_strb),
        .rd_en(rd_en),.rd_addr(rd_addr),.rd_data(rd_data),.rd_error(rd_error));
    axi_dual_bank_burst_write_slave #(.INPUT_WORDS(N*K),.MAX_BEATS(16),.PACKED_ENABLE(PACKED_ENABLE)) u_burst(
        .clk(clk),.rst_n(rst_n),.s_axi_awaddr(s_burst_awaddr),.s_axi_awlen(s_burst_awlen),.s_axi_awsize(s_burst_awsize),
        .s_axi_awburst(s_burst_awburst),.s_axi_awvalid(s_burst_awvalid&&allow_burst_aw),.s_axi_awready(b_awready),
        .s_axi_wdata(s_burst_wdata),.s_axi_wstrb(s_burst_wstrb),.s_axi_wlast(s_burst_wlast),.s_axi_wvalid(s_burst_wvalid),
        .s_axi_wready(s_burst_wready),.s_axi_bresp(s_burst_bresp),.s_axi_bvalid(s_burst_bvalid),.s_axi_bready(s_burst_bready),
        .wr_grant(burst_active),.active(burst_active),.wr_en(b_wr_en),.wr_addr(b_addr),.wr_data(b_data),.wr_strb(b_strb),.wr_error(wr_error));
    systolic_dual_bank_device #(.N(N),.K(K),.DATA_W(DATA_W),.ACC_W(ACC_W),.PACKED_ENABLE(PACKED_ENABLE)) u_device(
        .clk(clk),.rst_n(rst_n),.wr_en(wr_en),.wr_addr(wr_addr),.wr_data(wr_data),.wr_strb(wr_strb),.wr_error(wr_error),
        .rd_en(rd_en),.rd_addr(rd_addr),.rd_data(rd_data),.rd_error(rd_error),.result_read_busy(1'b0),.result_available(result_available_unused),.core_start(core_start),.core_busy(core_busy),
        .core_done(core_done),.a_matrix(a_matrix),.b_matrix(b_matrix),.core_result(result));
    systolic_array_top #(.N(N),.K(K),.DATA_W(DATA_W),.ACC_W(ACC_W)) u_core(
        .clk(clk),.rst_n(rst_n),.start(core_start),.a_matrix(a_matrix),.b_matrix(b_matrix),.busy(core_busy),.done(core_done),.result(result));
    always_ff @(posedge clk) if (rst_n && result_available_unused && core_busy)
        $error("DONE result and core BUSY must be mutually exclusive");
endmodule
