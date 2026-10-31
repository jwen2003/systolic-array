`timescale 1ns/1ps

// AXI4-Lite protocol adapter, 32-bit address and data.
//
// One outstanding WRITE and one outstanding READ are supported independently.
// AW and W may arrive in either order. A new write is accepted only after the
// previous B response has been consumed. Reads likewise wait for the previous R.
// No bursts, queues, or same-cycle response replacement are implemented.
//
// Device-side contract:
// * wr_en requests exactly one write attempt at the next rising edge.
// * wr_error must be combinational from wr_addr/data/strb and device state.
// * The device updates state only on wr_en && !wr_error (except error logging).
// * rd_en marks the AR handshake; rd_data/error must be combinational from
//   rd_addr and device state. This adapter captures them at that rising edge.
// * There is no device-side wait/ready. Synchronous RAM needs a different adapter.
// * Address decoding, alignment, WSTRB semantics, access permissions and register
//   side effects belong to the device, not this protocol adapter.
//
// Reset is synchronous active-low. Interface acceptance is gated during reset;
// reset aborts pending requests/responses. Master and device must reset together.
// AWPROT/ARPROT are accepted but ignored: this module provides no access control.
module axi_lite_slave (
    input  logic        clk,
    input  logic        rst_n,

    // Write address channel: Master -> Slave.
    input  logic [31:0] s_axi_awaddr,
    input  logic [2:0]  s_axi_awprot,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    // Write data channel: Master -> Slave.
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    // Write response channel: Slave -> Master.
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    // Read address channel: Master -> Slave.
    input  logic [31:0] s_axi_araddr,
    input  logic [2:0]  s_axi_arprot,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    // Read data/response channel: Slave -> Master.
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // Internal write request and combinational error result.
    output logic        wr_en,
    output logic [31:0] wr_addr,
    output logic [31:0] wr_data,
    output logic [3:0]  wr_strb,
    input  logic        wr_error,

    // Internal read request and combinational data/error result.
    output logic        rd_en,
    output logic [31:0] rd_addr,
    input  logic [31:0] rd_data,
    input  logic        rd_error
);

    localparam logic [1:0] RESP_OKAY   = 2'b00;
    localparam logic [1:0] RESP_SLVERR = 2'b10;

    logic        aw_pending;
    logic [31:0] awaddr_saved;
    logic        w_pending;
    logic [31:0] wdata_saved;
    logic [3:0]  wstrb_saved;

    // Protection attributes are intentionally unused. Connect to 3'b000 in BFM.
    logic unused_prot;
    assign unused_prot = ^{s_axi_awprot, s_axi_arprot};

    // Each pending flag reserves one independent address/data storage slot.
    assign s_axi_awready = rst_n && !aw_pending && !s_axi_bvalid;
    assign s_axi_wready  = rst_n && !w_pending  && !s_axi_bvalid;

    assign wr_addr = awaddr_saved;
    assign wr_data = wdata_saved;
    assign wr_strb = wstrb_saved;
    assign wr_en   = rst_n && aw_pending && w_pending && !s_axi_bvalid;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            aw_pending   <= 1'b0;
            awaddr_saved <= '0;
            w_pending    <= 1'b0;
            wdata_saved  <= '0;
            wstrb_saved  <= '0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= RESP_OKAY;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                awaddr_saved <= s_axi_awaddr;
                aw_pending   <= 1'b1;
            end

            if (s_axi_wvalid && s_axi_wready) begin
                wdata_saved <= s_axi_wdata;
                wstrb_saved <= s_axi_wstrb;
                w_pending   <= 1'b1;
            end

            // With both slots occupied, AWREADY/WREADY are low: capture and
            // execution cannot conflict. Device and response sample this edge.
            if (wr_en) begin
                aw_pending   <= 1'b0;
                w_pending    <= 1'b0;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= wr_error ? RESP_SLVERR : RESP_OKAY;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
            // Otherwise hold BVALID/BRESP, including while BREADY is low.
        end
    end

    // Combinational device read; R registers hold a snapshot under backpressure.
    assign s_axi_arready = rst_n && !s_axi_rvalid;
    assign rd_addr      = s_axi_araddr;
    assign rd_en        = s_axi_arvalid && s_axi_arready;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= '0;
            s_axi_rresp  <= RESP_OKAY;
        end else begin
            if (rd_en) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rdata  <= rd_error ? 32'b0 : rd_data;
                s_axi_rresp  <= rd_error ? RESP_SLVERR : RESP_OKAY;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
            // Otherwise hold RVALID/RDATA/RRESP until the response is accepted.
        end
    end

endmodule
