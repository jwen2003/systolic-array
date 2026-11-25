`timescale 1ns/1ps

// Restricted, single-outstanding AXI read channel for the C result window.
// Requests are checked once at AR acceptance. Invalid requests drain the
// requested beat count as SLVERR/zero data so a master cannot be stranded.
module axi_c_burst_read_slave #(
    parameter int unsigned N = 2,
    parameter int unsigned ACC_W = 18,
    parameter int unsigned MAX_BEATS = 16,
    parameter logic [31:0] C_BASE = 32'h0000_3000
) (
    input  logic clk, rst_n,
    input  logic [31:0] s_axi_araddr,
    input  logic [7:0]  s_axi_arlen,
    input  logic [2:0]  s_axi_arsize,
    input  logic [1:0]  s_axi_arburst,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rlast,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,
    input  logic        result_available,
    input  logic signed [ACC_W-1:0] result [N-1:0][N-1:0],
    output logic        result_read_busy
);
    localparam int unsigned RESULT_WORDS = N*N;
    localparam logic [32:0] C_LIMIT = {1'b0,C_BASE} + 4*RESULT_WORDS;
    localparam logic [8:0] MAX_BEATS_VALUE = 9'(MAX_BEATS);
    logic active, request_legal;
    logic [8:0] beats_left;
    logic [31:0] current_addr, data_addr, selected_data;
    logic [32:0] last_addr_ext;
    logic ar_accept, legal_ar_accept;

    initial begin
        if (N == 0 || ACC_W == 0) $fatal(1, "N and ACC_W must be positive");
        if (MAX_BEATS == 0 || MAX_BEATS > 256) $fatal(1, "Invalid MAX_BEATS");
        if (ACC_W > 32) $fatal(1, "C burst data requires ACC_W <= 32");
    end

    assign s_axi_arready = rst_n && !active && !s_axi_rvalid;
    assign ar_accept = s_axi_arvalid && s_axi_arready;
    assign last_addr_ext = {1'b0,s_axi_araddr} + {23'b0,s_axi_arlen,2'b00};
    always_comb begin
        request_legal = result_available &&
            s_axi_arsize == 3'd2 && s_axi_arburst == 2'b01 &&
            {1'b0,s_axi_arlen} < MAX_BEATS_VALUE && s_axi_araddr[1:0] == 2'b00 &&
            !last_addr_ext[32] && s_axi_araddr >= C_BASE &&
            last_addr_ext < C_LIMIT &&
            s_axi_araddr[31:12] == last_addr_ext[31:12];
    end
    assign legal_ar_accept = ar_accept && request_legal;

    // A legal AR reserves the result on its acceptance edge. Keeping the
    // combinational term here makes a simultaneous ACK lose deterministically.
    assign result_read_busy = active || legal_ar_accept;

    // During a consumed beat, preselect the next fixed result coordinate so
    // the registered channel can sustain one beat per cycle without indexing.
    always_comb begin
        data_addr = current_addr;
        if (!active) data_addr = s_axi_araddr;
        else if (s_axi_rvalid && s_axi_rready && beats_left > 1)
            data_addr = current_addr + 32'd4;
        selected_data = 32'b0;
        for (int r=0; r<N; r++) begin
            for (int c=0; c<N; c++) begin
                selected_data |= {32{data_addr == C_BASE + 4*(r*N+c)}} &
                    {{(32-ACC_W){result[r][c][ACC_W-1]}},result[r][c]};
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            active <= 1'b0;
            beats_left <= '0;
            current_addr <= '0;
            s_axi_rdata <= '0;
            s_axi_rresp <= 2'b00;
            s_axi_rlast <= 1'b0;
            s_axi_rvalid <= 1'b0;
        end else if (ar_accept) begin
            active <= 1'b1;
            beats_left <= {1'b0,s_axi_arlen} + 9'd1;
            current_addr <= s_axi_araddr;
            s_axi_rdata <= request_legal ? selected_data : 32'b0;
            s_axi_rresp <= request_legal ? 2'b00 : 2'b10;
            s_axi_rlast <= s_axi_arlen == 0;
            s_axi_rvalid <= 1'b1;
        end else if (s_axi_rvalid && s_axi_rready) begin
            if (beats_left == 1) begin
                active <= 1'b0;
                beats_left <= '0;
                s_axi_rvalid <= 1'b0;
                s_axi_rlast <= 1'b0;
            end else begin
                beats_left <= beats_left - 9'd1;
                current_addr <= current_addr + 32'd4;
                s_axi_rdata <= s_axi_rresp == 2'b00 ? selected_data : 32'b0;
                s_axi_rlast <= beats_left == 2;
            end
        end
    end
endmodule
