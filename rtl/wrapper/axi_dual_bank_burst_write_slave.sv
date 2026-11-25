`timescale 1ns/1ps

// Restricted write-burst adapter for both dual-bank normal/packed windows.
module axi_dual_bank_burst_write_slave #(
    parameter int unsigned INPUT_WORDS=4, MAX_BEATS=16,
    parameter bit PACKED_ENABLE=0
) (
    input logic clk,rst_n,input logic [31:0] s_axi_awaddr,input logic [7:0] s_axi_awlen,
    input logic [2:0] s_axi_awsize,input logic [1:0] s_axi_awburst,input logic s_axi_awvalid,
    output logic s_axi_awready,input logic [31:0] s_axi_wdata,input logic [3:0] s_axi_wstrb,
    input logic s_axi_wlast,s_axi_wvalid,output logic s_axi_wready,output logic [1:0] s_axi_bresp,
    output logic s_axi_bvalid,input logic s_axi_bready,input logic wr_grant,output logic active,
    output logic wr_en,output logic [31:0] wr_addr,wr_data,output logic [3:0] wr_strb,input logic wr_error
);
    typedef enum logic [1:0] {WAIT_ADDR,DATA,RESP} state_t; state_t state;
    logic [31:0] current_addr; logic [8:0] left,beats;
    logic descriptor_bad,burst_error,discard,last_bad,fire,next_bad;
    logic [32:0] end_addr;
    localparam logic [32:0] BYTES=4*INPUT_WORDS, PBYTES=4*((INPUT_WORDS+3)/4);
    function automatic logic valid_window(input logic [31:0] a,input logic [32:0] e);
        return (a>=32'h1000&&e<=33'h1000+BYTES)||(a>=32'h2000&&e<=33'h2000+BYTES)||
          (a>=32'h6000&&e<=33'h6000+BYTES)||(a>=32'h7000&&e<=33'h7000+BYTES)||
          (PACKED_ENABLE&&((a>=32'h4000&&e<=33'h4000+PBYTES)||(a>=32'h5000&&e<=33'h5000+PBYTES)||
                          (a>=32'h8000&&e<=33'h8000+PBYTES)||(a>=32'h9000&&e<=33'h9000+PBYTES)));
    endfunction
    assign beats={1'b0,s_axi_awlen}+1; assign end_addr={1'b0,s_axi_awaddr}+(33'(beats)<<2);
    assign descriptor_bad=s_axi_awaddr[1:0]!=0||s_axi_awsize!=2||s_axi_awburst!=1||beats>9'(MAX_BEATS)||!valid_window(s_axi_awaddr,end_addr);
    assign s_axi_awready=rst_n&&state==WAIT_ADDR; assign s_axi_wready=rst_n&&state==DATA&&(discard||wr_grant);
    assign s_axi_bvalid=rst_n&&state==RESP; assign active=state!=WAIT_ADDR; assign fire=s_axi_wvalid&&s_axi_wready;
    assign last_bad=s_axi_wlast!=(left==1); assign wr_en=fire&&!discard&&!last_bad;
    assign wr_addr=current_addr; assign wr_data=s_axi_wdata; assign wr_strb=s_axi_wstrb;
    assign next_bad=burst_error||last_bad||(wr_en&&wr_error);
    always_ff @(posedge clk) begin
        if(!rst_n) begin state<=WAIT_ADDR; current_addr<=0; left<=0; burst_error<=0; discard<=0; s_axi_bresp<=0; end
        else case(state)
            WAIT_ADDR: if(s_axi_awvalid&&s_axi_awready) begin current_addr<=s_axi_awaddr;left<=beats;burst_error<=descriptor_bad;discard<=descriptor_bad;state<=DATA;end
            DATA: if(fire) begin current_addr<=current_addr+4;left<=left-1;burst_error<=next_bad;discard<=discard||last_bad;
                if(left==1) begin s_axi_bresp<=next_bad?2'b10:0;state<=RESP;end end
            RESP: if(s_axi_bready&&s_axi_bvalid) state<=WAIT_ADDR;
            default: state<=WAIT_ADDR;
        endcase
    end
endmodule
