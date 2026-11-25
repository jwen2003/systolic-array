`timescale 1ns/1ps

module tb_systolic_axi_dual_bank_top;
    localparam int N=2,K=2;
    logic clk=0,rst_n=0;
    logic [31:0] s_axi_awaddr=0,s_axi_wdata=0,s_axi_araddr=0;
    logic [2:0] s_axi_awprot=0,s_axi_arprot=0;
    logic [3:0] s_axi_wstrb=0; logic s_axi_awvalid=0,s_axi_awready,s_axi_wvalid=0,s_axi_wready;
    logic [1:0] s_axi_bresp; logic s_axi_bvalid,s_axi_bready=0,s_axi_arvalid=0,s_axi_arready;
    logic [31:0] s_axi_rdata; logic [1:0] s_axi_rresp; logic s_axi_rvalid,s_axi_rready=0;
    logic [31:0] s_burst_awaddr=0,s_burst_wdata=0; logic [7:0] s_burst_awlen=0;
    logic [2:0] s_burst_awsize=2; logic [1:0] s_burst_awburst=1;
    logic s_burst_awvalid=0,s_burst_awready; logic [3:0] s_burst_wstrb=0;
    logic s_burst_wlast=0,s_burst_wvalid=0,s_burst_wready; logic [1:0] s_burst_bresp;
    logic s_burst_bvalid,s_burst_bready=0;
    int checks=0,overlap_cycles=0;
    int signed model_a[0:1][0:N-1][0:K-1],model_b[0:1][0:K-1][0:N-1];
    systolic_axi_dual_bank_top #(.N(N),.K(K),.PACKED_ENABLE(1)) dut(.*);
    always #5 clk<=~clk;
    always_ff @(posedge clk) if (rst_n && dut.core_busy && dut.u_burst.active)
        overlap_cycles <= overlap_cycles + 1;
    task automatic check(input bit c,input string m); checks++; if(!c)$fatal(1,"check %0d: %s",checks,m); endtask
    task automatic lite_write(input logic[31:0] a,d,input logic[3:0] strb=4'hf,input logic[1:0] resp=0,input int stall=0);
        @(negedge clk); s_axi_awaddr=a;s_axi_wdata=d;s_axi_wstrb=strb;s_axi_awvalid=1;s_axi_wvalid=1;
        do @(posedge clk); while(!(s_axi_awready&&s_axi_wready));
        @(negedge clk);s_axi_awvalid=0;s_axi_wvalid=0;
        repeat(stall) begin @(posedge clk);#1;check(s_axi_bvalid&&s_axi_bresp==resp,"Lite B held under backpressure");end
        @(negedge clk);s_axi_bready=1;@(posedge clk);#1;check(s_axi_bresp==resp,"Lite BRESP");@(negedge clk);s_axi_bready=0;
    endtask
    task automatic lite_read(input logic[31:0] a,input logic[31:0] d,input logic[1:0] resp=0,input int stall=0);
        @(negedge clk);s_axi_araddr=a;s_axi_arvalid=1;do @(posedge clk);while(!s_axi_arready);
        @(negedge clk);s_axi_arvalid=0;
        repeat(stall) begin @(posedge clk);#1;check(s_axi_rvalid&&s_axi_rdata==d&&s_axi_rresp==resp,"Lite R held");end
        @(negedge clk);s_axi_rready=1;@(posedge clk);#1;
        check(s_axi_rdata==d&&s_axi_rresp==resp,
              $sformatf("Lite read addr=%08x expected=%08x/%0d actual=%08x/%0d",a,d,resp,s_axi_rdata,s_axi_rresp));
        @(negedge clk);s_axi_rready=0;
    endtask
    task automatic burst(input logic[31:0] a,input int beats,input logic[31:0] data[0:15],input logic[3:0] strb[0:15],input logic[1:0] resp=0,input int stall=0);
        @(negedge clk);s_burst_awaddr=a;s_burst_awlen=8'(beats-1);s_burst_awvalid=1;
        do @(posedge clk);while(!s_burst_awready);@(negedge clk);s_burst_awvalid=0;
        for(int i=0;i<beats;i++) begin s_burst_wdata=data[i];s_burst_wstrb=strb[i];s_burst_wlast=i==beats-1;s_burst_wvalid=1;
            do @(posedge clk);while(!s_burst_wready);@(negedge clk); end
        s_burst_wvalid=0;s_burst_wlast=0;
        repeat(stall) begin @(posedge clk);#1;check(s_burst_bvalid&&s_burst_bresp==resp,"Burst B held");end
        s_burst_bready=1;@(posedge clk);#1;check(s_burst_bresp==resp,"Burst response");@(negedge clk);s_burst_bready=0;
    endtask
    task automatic wait_done;
        while (dut.u_device.state != 2) begin @(posedge clk); #1; end
    endtask
    function automatic int signed golden(input bit bank,row,col);
        golden=0; for(int k=0;k<K;k++)golden+=model_a[bank][row][k]*model_b[bank][k][col];
    endfunction
    task automatic check_c(input bit bank);
        lite_read(32'h3000,golden(bank,0,0));
        lite_read(32'h3004,golden(bank,0,1));
        lite_read(32'h3008,golden(bank,1,0));
        lite_read(32'h300c,golden(bank,1,1));
    endtask
    initial begin
        logic[31:0] bd[0:15];logic[3:0] bs[0:15];
        model_a[0][0][0]=2;model_a[0][0][1]=-3;model_a[0][1][0]=4;model_a[0][1][1]=5;
        model_b[0][0][0]=-1;model_b[0][0][1]=6;model_b[0][1][0]=7;model_b[0][1][1]=-2;
        model_a[1][0][0]=1;model_a[1][0][1]=2;model_a[1][1][0]=3;model_a[1][1][1]=4;
        model_b[1][0][0]=5;model_b[1][0][1]=6;model_b[1][1][0]=7;model_b[1][1][1]=8;
        repeat(2)@(posedge clk);@(negedge clk);rst_n=1;
        lite_read(0,32'h300);
        // Bank 0 normal writes establish the baseline address map.
        lite_write(32'h1000,2);lite_write(32'h1004,32'hffff_fffd);lite_write(32'h1008,4);lite_write(32'h100c,5);
        lite_write(32'h2000,32'hffff_ffff);lite_write(32'h2004,6);lite_write(32'h2008,7);lite_write(32'h200c,32'hffff_fffe);
        lite_read(8,32'h4); lite_write(4,1); // START0
        // The active bank is locked, while a packed Burst loads bank 1.
        bd[0]=32'h04030201;bs[0]=4'hf;burst(32'h8000,1,bd,bs,0,2);
        bd[0]=32'h08070605;burst(32'h9000,1,bd,bs);
        lite_write(32'h1000,99,4'hf,2); lite_read(32'h1000,0,2);
        wait_done();check(overlap_cycles>0,"bank1 load overlaps bank0 calculation");
        lite_read(8,32'h5e); // DONE, both ready, active bank0, sticky error
        check_c(0);
        lite_write(4,2,4'hf,2); // DONE blocks START1
        // Concurrent C read and ACK sees the pre-edge DONE result.
        fork lite_read(32'h300c,14,0,2); lite_write(32'hc,1); join
        lite_read(8,32'h18); // bank1 ready; bank0 map cleared; sticky error
        lite_write(4,2); // START1 without reload
        // Reload bank0 through normal Burst while bank1 computes.
        for(int i=0;i<4;i++)begin bd[i]=i+1;bs[i]=1;end burst(32'h1000,4,bd,bs);
        for(int i=0;i<4;i++)begin bd[i]=(i==0)?1:0;bs[i]=1;end burst(32'h2000,4,bd,bs);
        wait_done();check_c(1);
        lite_write(32'hc,1);lite_read(8,32'h0c); // only bank0 remains ready
        // Both START bits, incomplete bank, high alias, and crossing Burst reject without side effects.
        lite_write(4,3,4'hf,2);lite_write(4,2,4'hf,2);lite_write(32'h1000_6000,1,4'hf,2);
        bd[0]=1;bd[1]=2;bs[0]=1;bs[1]=1;burst(32'h601c,2,bd,bs,2);
        // Reset during RUN aborts ownership and invalidates both maps.
        lite_write(4,1);repeat(2)@(posedge clk);@(negedge clk);rst_n=0;@(posedge clk);@(negedge clk);rst_n=1;
        lite_read(8,0);lite_read(32'h1000,0);lite_read(32'h6000,0);
        $display("PASS tb_systolic_axi_dual_bank_top: %0d checks, %0d overlap cycles",checks,overlap_cycles);$finish;
    end
    initial begin #200000;$fatal(1,"watchdog");end
endmodule
