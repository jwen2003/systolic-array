`timescale 1ns/1ps

module tb_axi_c_burst_read_slave;
    localparam int N=4, ACC_W=18;
    logic clk=0,rst_n=0;
    logic [31:0] araddr; logic [7:0] arlen; logic [2:0] arsize;
    logic [1:0] arburst; logic arvalid,arready;
    logic [31:0] rdata; logic [1:0] rresp; logic rlast,rvalid,rready;
    logic result_available,result_read_busy;
    logic signed [ACC_W-1:0] result[N-1:0][N-1:0];
    int checks=0;
    always #5 clk=~clk;

    axi_c_burst_read_slave #(.N(N),.ACC_W(ACC_W)) dut(.*,
        .s_axi_araddr(araddr),.s_axi_arlen(arlen),.s_axi_arsize(arsize),
        .s_axi_arburst(arburst),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
        .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rlast(rlast),
        .s_axi_rvalid(rvalid),.s_axi_rready(rready));

    task automatic check_value(input logic condition,input string message);
        checks++;
        if(!condition) $fatal(1,"FAIL: %s",message);
    endtask

    task automatic send_ar(input logic [31:0] addr,input int beats,
        input logic [2:0] size=3'd2,input logic [1:0] burst=2'b01);
        @(negedge clk); araddr=addr; arlen=8'(beats-1); arsize=size;
        arburst=burst; arvalid=1;
        do @(posedge clk); while(!arready);
        #1;
        @(negedge clk); arvalid=0;
    endtask

    task automatic consume(input int beats,input logic [1:0] response,
        input int first_index=0);
        rready=0;
        for(int i=0;i<beats;i++) begin
            do @(negedge clk); while(!rvalid);
            check_value(rresp==response,"response code");
            check_value(rlast==(i==beats-1),"RLAST position");
            if(response==0) check_value(rdata=={{(32-ACC_W){result[(first_index+i)/N][(first_index+i)%N][ACC_W-1]}},
                result[(first_index+i)/N][(first_index+i)%N]},"result data");
            else check_value(rdata==0,"invalid request hides result");
            rready=1;
            @(posedge clk);
        end
        @(negedge clk); rready=0;
    endtask

    initial begin
        araddr=0;arlen=0;arsize=2;arburst=1;arvalid=0;rready=0;result_available=0;
        for(int r=0;r<N;r++) for(int c=0;c<N;c++) result[r][c]=ACC_W'(r*N+c-8);
        repeat(2) @(posedge clk); #1;
        check_value(!arready&&!rvalid&&!result_read_busy,"synchronous reset state");
        @(negedge clk);rst_n=1;result_available=1;

        $display("legal requests");
        send_ar(32'h3000,1); consume(1,0,0); $display("one done");
        send_ar(32'h3000,16); consume(16,0,0); $display("sixteen done");
        send_ar(32'h303c,1); consume(1,0,15); $display("last done");

        // R payload and control must remain stable while the master stalls.
        $display("backpressure"); send_ar(32'h3004,2);
        rready=0; do @(posedge clk); while(!rvalid); #1;
        begin logic [34:0] held={rdata,rresp,rlast}; repeat(3) begin
            @(posedge clk); #1; check_value({rdata,rresp,rlast}==held&&rvalid,"backpressure stability");
        end end
        consume(2,0,1);

        $display("invalid requests"); result_available=0; send_ar(32'h3000,3); consume(3,2);
        result_available=1;
        send_ar(32'h3002,1); consume(1,2);
        send_ar(32'h3000,1,3'd1); consume(1,2);
        send_ar(32'h3000,1,3'd2,2'b00); consume(1,2);
        send_ar(32'h303c,2); consume(2,2);
        send_ar(32'h2ffc,2); consume(2,2);
        send_ar(32'h3000,17); consume(17,2);

        $display("reservation"); send_ar(32'h3000,2);
        check_value(result_read_busy,"result reserved while response outstanding");
        consume(2,0,0);
        @(posedge clk); #1; check_value(!result_read_busy,"reservation released after final handshake");

        @(negedge clk);rst_n=0;rready=1;
        @(posedge clk);#1;check_value(!rvalid&&!result_read_busy,"reset aborts response");
        $display("PASS: axi_c_burst_read_slave (%0d checks)",checks);
        $finish;
    end
endmodule
