`timescale 1ns/1ps

module tb_systolic_dual_bank_device_tail;
    localparam int N=2,K=3;
    logic clk=0,rst_n=0,wr_en=0,rd_en=0,wr_error,rd_error,core_start,core_busy=0,core_done=0;
    logic result_read_busy=0,result_available;
    logic [31:0] wr_addr=0,wr_data=0,rd_addr=0,rd_data; logic [3:0] wr_strb=0;
    logic signed [7:0] a_matrix[N-1:0][K-1:0],b_matrix[K-1:0][N-1:0];
    logic signed [17:0] core_result[N-1:0][N-1:0]; int checks=0;
    systolic_dual_bank_device #(.N(N),.K(K),.PACKED_ENABLE(1)) dut(.*);
    always #5 clk<=~clk;
    task automatic check(input bit c,input string m);checks++;if(!c)$fatal(1,"check %0d: %s",checks,m);endtask
    task automatic write(input logic[31:0] a,d,input logic[3:0] s,input bit err=0);
        @(negedge clk);wr_addr=a;wr_data=d;wr_strb=s;wr_en=1;#1;check(wr_error==err,"write response");
        @(posedge clk);#1;@(negedge clk);wr_en=0;
    endtask
    initial begin
        for(int r=0;r<N;r++)for(int c=0;c<N;c++)core_result[r][c]=0;
        repeat(2)@(posedge clk);@(negedge clk);rst_n=1;
        write(32'h1000,32'd7,4'h1);
        write(32'h2000,32'd9,4'h1);
        check(a_matrix[0][0]==7&&b_matrix[0][0]==9&&!rd_error&&!core_start&&!result_available&&rd_data==32'h300,
              "unused bank remains accessible while idle");
        // Six elements use one full word and a two-lane tail. Word 0 crosses
        // the A row boundary; all four selected lanes must commit together.
        write(32'h8000,32'h04030201,4'hf);
        check(dut.a_bank[1][0][0]==1&&dut.a_bank[1][0][1]==2&&
              dut.a_bank[1][0][2]==3&&dut.a_bank[1][1][0]==4,
              "bank1 packed word crosses row without priority loss");
        write(32'h8004,32'h00000605,4'h3);
        check(dut.a_bank[1][1][1]==5&&dut.a_bank[1][1][2]==6&&$countones(dut.a_written[1])==6,
              "bank1 legal tail lanes update data and bitmap");
        write(32'h9004,32'h08070605,4'h4,1);
        check($countones(dut.b_written[1])==0,"illegal tail lane rejects whole beat");
        write(32'h9004,32'h08070605,4'h0);
        check($countones(dut.b_written[1])==0,"zero strobe has no side effects");
        write(32'h1000_8000,32'h1,4'h1,1);
        check($countones(dut.a_written[1])==6,"high alias cannot update bank1");
        $display("PASS tb_systolic_dual_bank_device_tail: %0d checks",checks);$finish;
    end
    initial begin #20000;$fatal(1,"watchdog");end
endmodule
