`timescale 1ns/1ps

// Restricted AXI4 WRITE path: single implicit ID, one outstanding transaction,
// aligned 32-bit INCR, 1..MAX_BEATS, entirely within ONE configured A/B window.
// PACKED_ENABLE additionally permits rounded dense INT8 windows at 4000/5000;
// Device validates each enabled byte lane, including padding in the final word.
// Not a complete general-purpose AXI4 slave; no read channels or sidebands.
// AW is accepted before W; master must not wait for WREADY to issue AWVALID.
//
// wr_grant is TOP ownership/arbitration permission, not device error/acceptance.
// With grant, each W handshake attempts exactly one combinational device write.
// Device must commit only wr_en && !wr_error. Device errors accumulate without
// stopping subsequent beats. active reserves the transaction through B handshake.
//
// Invalid AW descriptors are drained by AWLEN, without any device writes.
// WLAST mismatch suppresses that beat and subsequent writes; count still follows
// AWLEN (no early termination). Recovery from a master sending fewer/more beats
// than declared is NOT guaranteed; shared synchronous reset may be necessary.
// No rollback: successful earlier beats remain visible after SLVERR.
module axi_burst_write_slave #(
    parameter int unsigned INPUT_WORDS = 4,
    parameter int unsigned MAX_BEATS = 16,
    parameter bit PACKED_ENABLE = 0
) (
    input logic clk, rst_n,
    input logic [31:0] s_axi_awaddr,
    input logic [7:0] s_axi_awlen,
    input logic [2:0] s_axi_awsize,
    input logic [1:0] s_axi_awburst,
    input logic s_axi_awvalid,
    output logic s_axi_awready,
    input logic [31:0] s_axi_wdata,
    input logic [3:0] s_axi_wstrb,
    input logic s_axi_wlast, s_axi_wvalid,
    output logic s_axi_wready,
    output logic [1:0] s_axi_bresp,
    output logic s_axi_bvalid,
    input logic s_axi_bready,
    input logic wr_grant,
    output logic active,
    output logic wr_en,
    output logic [31:0] wr_addr, wr_data,
    output logic [3:0] wr_strb,
    input logic wr_error
);
    typedef enum logic [1:0] {WAIT_ADDR, RECEIVE_DATA, SEND_RESP} state_t;
    state_t state;
    logic [31:0] current_addr;
    logic [8:0] beats_remaining, requested_beats;
    logic [32:0] end_addr;
    logic descriptor_error, burst_error, discard;
    logic last_mismatch, beat_fire, error_next;
    localparam logic [32:0] A_END = 33'h1000 + 33'(4*INPUT_WORDS);
    localparam logic [32:0] B_END = 33'h2000 + 33'(4*INPUT_WORDS);

    localparam logic [32:0] PA_END = 33'h4000 + 33'(4*((INPUT_WORDS+3)/4));
    localparam logic [32:0] PB_END = 33'h5000 + 33'(4*((INPUT_WORDS+3)/4));

    initial begin
        if (INPUT_WORDS < 1 || INPUT_WORDS > 1024 || MAX_BEATS < 1 || MAX_BEATS > 16)
            $fatal(1, "Unsupported buffer capacity or burst limit");
    end

    assign requested_beats = {1'b0, s_axi_awlen} + 9'd1;
    // Exclusive end, extended to catch 32-bit wrap. Both windows are <=4 KiB;
    // requiring the whole range inside one window also prevents 4 KiB crossing.
    assign end_addr = {1'b0, s_axi_awaddr} + (33'(requested_beats) << 2);
    assign descriptor_error = s_axi_awaddr[1:0] != 0 || s_axi_awsize != 3'd2
        || s_axi_awburst != 2'b01 || requested_beats > 9'(MAX_BEATS)
        || !((s_axi_awaddr >= 32'h1000 && end_addr <= A_END)
          || (s_axi_awaddr >= 32'h2000 && end_addr <= B_END)
          || (PACKED_ENABLE && s_axi_awaddr >= 32'h4000 && end_addr <= PA_END)
          || (PACKED_ENABLE && s_axi_awaddr >= 32'h5000 && end_addr <= PB_END));

    assign s_axi_awready = rst_n && state == WAIT_ADDR;
    assign s_axi_wready = rst_n && state == RECEIVE_DATA && (discard || wr_grant);
    assign s_axi_bvalid = rst_n && state == SEND_RESP;
    assign active = state != WAIT_ADDR;
    assign beat_fire = s_axi_wvalid && s_axi_wready;
    assign last_mismatch = s_axi_wlast != (beats_remaining == 1);
    assign wr_addr = current_addr;
    assign wr_data = s_axi_wdata;
    assign wr_strb = s_axi_wstrb;
    // A W beat reaches Device only on a real handshake and only while the
    // descriptor/stream remains usable. WLAST mismatch is detected before
    // wr_en so the mismatching tail cannot partially update matrix storage.
    assign wr_en = beat_fire && !discard && !last_mismatch;
    assign error_next = burst_error || last_mismatch || (wr_en && wr_error);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= WAIT_ADDR;
            current_addr <= '0;
            beats_remaining <= '0;
            burst_error <= 0;
            discard <= 0;
            s_axi_bresp <= 2'b00;
        end else begin
            case (state)
                WAIT_ADDR: if (s_axi_awvalid && s_axi_awready) begin
                    // Descriptor validity is frozen with AW. Invalid requests
                    // still consume exactly AWLEN+1 beats to preserve channel
                    // framing, but discard prevents all Device side effects.
                    current_addr <= s_axi_awaddr;
                    beats_remaining <= requested_beats;
                    burst_error <= descriptor_error;
                    discard <= descriptor_error;
                    state <= RECEIVE_DATA;
                end
                RECEIVE_DATA: if (beat_fire) begin
                    // Address/count advance only on handshake. While WREADY is
                    // low, the master must hold WVALID, payload, strobe, and
                    // WLAST; this state deliberately makes no progress.
                    current_addr <= current_addr + 32'd4;
                    beats_remaining <= beats_remaining - 9'd1;
                    burst_error <= error_next;
                    discard <= discard || last_mismatch;
                    if (beats_remaining == 1) begin
                        s_axi_bresp <= error_next ? 2'b10 : 2'b00;
                        state <= SEND_RESP;
                    end
                end
                SEND_RESP: if (s_axi_bready && s_axi_bvalid) state <= WAIT_ADDR;
                default: state <= WAIT_ADDR;
            endcase
        end
    end
endmodule
