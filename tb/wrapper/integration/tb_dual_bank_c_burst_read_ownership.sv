`timescale 1ns/1ps

// Integration test for the Device result lifetime and C Burst reservation.
module tb_dual_bank_c_burst_read_ownership;
    localparam int N=2,K=1,DATA_W=8,ACC_W=18;
    logic clk=0,rst_n=0,wr_en,rd_en,core_busy,core_done,core_start;
    logic [31:0] wr_addr,wr_data,rd_addr,rd_data; logic [3:0] wr_strb;
    logic wr_error,rd_error,result_available,result_read_busy;
    logic signed [DATA_W-1:0] a_matrix[N-1:0][K-1:0],b_matrix[K-1:0][N-1:0];
    logic signed [ACC_W-1:0] core_result[N-1:0][N-1:0];
    logic [31:0] araddr,rdata;logic [7:0] arlen;logic [2:0] arsize;
    logic [1:0] arburst,rresp;logic arvalid,arready,rlast,rvalid,rready;
    int checks=0;
    always #5 clk=~clk;

    systolic_dual_bank_device #(.N(N),.K(K),.DATA_W(DATA_W),.ACC_W(ACC_W),.PACKED_ENABLE(1)) dev(
        .clk,.rst_n,.wr_en,.wr_addr,.wr_data,.wr_strb,.wr_error,.rd_en,.rd_addr,.rd_data,.rd_error,
        .result_read_busy,.result_available,.core_start,.core_busy,.core_done,.a_matrix,.b_matrix,.core_result);
    axi_c_burst_read_slave #(.N(N),.ACC_W(ACC_W)) reader(
        .clk,.rst_n,.s_axi_araddr(araddr),.s_axi_arlen(arlen),.s_axi_arsize(arsize),.s_axi_arburst(arburst),
        .s_axi_arvalid(arvalid),.s_axi_arready(arready),.s_axi_rdata(rdata),.s_axi_rresp(rresp),
        .s_axi_rlast(rlast),.s_axi_rvalid(rvalid),.s_axi_rready(rready),.result_available,.result(core_result),.result_read_busy);

    task automatic check_value(input logic condition,input string message);
        checks++;if(!condition)$fatal(1,"FAIL: %s",message);
    endtask
    task automatic write_word(input logic[31:0] addr,data);
        @(negedge clk);wr_en=1;wr_addr=addr;wr_data=data;wr_strb=4'hf;#1;check_value(!wr_error,"write accepted");
        @(posedge clk);@(negedge clk);wr_en=0;
    endtask
    task automatic denied_ack(input string message);
        wr_en=1;wr_addr=32'hc;wr_data=1;wr_strb=1;#1;check_value(wr_error,message);
        @(posedge clk);@(negedge clk);wr_en=0;
    endtask

    initial begin
        wr_en=0;wr_addr=0;wr_data=0;wr_strb=0;rd_en=0;rd_addr=0;core_busy=0;core_done=0;
        araddr=0;arlen=0;arsize=2;arburst=1;arvalid=0;rready=0;
        for(int r=0;r<N;r++)for(int c=0;c<N;c++)core_result[r][c]=ACC_W'(r*N+c-2);
        repeat(2)@(posedge clk);@(negedge clk);rst_n=1;
        write_word(32'h1000,32'h02);write_word(32'h1004,32'h03);
        write_word(32'h2000,32'h04);write_word(32'h2004,32'h05);
        check_value(a_matrix[0][0]==2&&a_matrix[1][0]==3&&b_matrix[0][0]==4&&b_matrix[0][1]==5,
            "selected bank data");
        check_value(!rd_error&&!$isunknown(rd_data),"idle read outputs");
        write_word(32'h0004,1);
        check_value(core_start,"START0 accepted");core_busy=1;
        @(posedge clk);@(negedge clk);core_busy=0;core_done=1;
        @(posedge clk);@(negedge clk);core_done=0;
        check_value(result_available,"result enters DONE");

        // A legal AR reserves C before the edge, so a simultaneous ACK loses.
        araddr=32'h3000;arlen=3;arsize=2;arburst=1;arvalid=1;
        wr_en=1;wr_addr=32'hc;wr_data=1;wr_strb=1;#1;
        check_value(arready&&result_read_busy,"legal AR reserves result");
        check_value(wr_error,"AR wins over same-cycle ACK");
        @(posedge clk);@(negedge clk);arvalid=0;wr_en=0;

        // Loading the inactive bank remains legal while C is being returned.
        write_word(32'h6000,32'h7f);
        rready=0;
        for(int beat=0;beat<4;beat++)begin
            @(negedge clk);check_value(rvalid&&rresp==0,"C response beat");
            check_value(rlast==(beat==3),"C response RLAST");
            check_value($signed(rdata)==beat-2,"C response data");
            if(beat==3)begin
                // Outstanding is evaluated before the edge; retry is required.
                wr_en=1;wr_addr=32'hc;wr_data=1;wr_strb=1;#1;
                check_value(wr_error,"final R and ACK same edge is rejected");
            end
            rready=1;
            @(posedge clk);
        end
        @(negedge clk);rready=0;wr_en=0;
        check_value(result_available&&!result_read_busy,"result retained after burst");
        write_word(32'h000c,1);
        @(negedge clk);check_value(!result_available,"retry ACK releases result");

        // Reset aborts an active read and clears the result ownership state.
        rst_n=0;@(posedge clk);#1;check_value(!rvalid&&!result_read_busy&&!result_available,"reset clears ownership");
        $display("PASS: dual-bank C Burst ownership (%0d checks)",checks);$finish;
    end
endmodule
