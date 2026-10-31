`timescale 1ns/1ps

// Device semantics behind axi_lite_slave; no AXI handshake logic here.
// Fixed hardware shape. One signed INT8 per 32-bit input slot; INT18 results.
// Optional PACKED_ENABLE aliases at 4000/5000 update up to four INT8 lanes.
// Addresses are byte offsets relative to the accelerator's base address.
//
// 0000 VERSION (0.2.0 = 0000_0200), 0004 COMMAND[0]=START (WO)
// 0008 STATUS: [0]BUSY [1]DONE [2]INPUTS_READY [3]ERROR
// 000c ACK[0] (WO): DONE -> LOAD, invalidate both input written maps
// 0010 ERROR_STATUS (W1C), 0020 HW_N, 0024 HW_K, 0028 DATA_W, 002c ACC_W
// 1000 A[i][k]: +4*(i*K+k); 2000 B[k][j]: +4*(k*N+j)
// 3000 C[i][j]: +4*(i*N+j), read-only and readable only in DONE.
//
// A/B reads and writes are allowed only in LOAD. An unwritten input reads zero.
// WSTRB[0] controls input and command writes; input upper bytes are ignored.
// Zero strobes cause no side effect, but address/permission checks still apply.
// Reserved command bits are ignored. ACK outside DONE is a successful no-op.
// Reads of WO registers and undefined offsets report INVALID_ADDRESS.
//
// Errors: [0]START_NOT_ALLOWED [1]INPUT_INCOMPLETE [2]INVALID_ADDRESS
// [3]INPUT_WRITE_NOT_ALLOWED [4]RESULT_NOT_READY [5]MISALIGNED_ACCESS
// [6]WRITE_TO_READ_ONLY [7]INPUT_READ_NOT_ALLOWED.
// Alignment has priority over other reasons within a request. Independent
// read/write errors are ORed. New errors win over simultaneous W1C clearing.
// Errors never force an ERROR state or abort a running calculation.
//
// Reset: synchronous active-low, shared with slave/core. Clears state, maps,
// start and errors; does not clear input storage or copy/reset core results.
// RUN includes the registered start handoff. Core runs to completion unstalled.
// DONE owns the core result snapshot until ACK. No new start before ACK.
// Same-edge reads observe the pre-edge state/data (including a read with ACK).
module systolic_device #(
    parameter int unsigned N = 2,
    parameter int unsigned K = 2,
    parameter int unsigned DATA_W = 8,
    parameter int unsigned ACC_W = 18,
    parameter bit PACKED_ENABLE = 0
) (
    input  logic clk,
    input  logic rst_n,
    input  logic wr_en,
    input  logic [31:0] wr_addr,
    input  logic [31:0] wr_data,
    input  logic [3:0] wr_strb,
    output logic wr_error,
    input  logic rd_en,
    input  logic [31:0] rd_addr,
    output logic [31:0] rd_data,
    output logic rd_error,
    output logic core_start,
    input  logic core_busy,
    input  logic core_done,
    output logic signed [DATA_W-1:0] a_matrix [N-1:0][K-1:0],
    output logic signed [DATA_W-1:0] b_matrix [K-1:0][N-1:0],
    input  logic signed [ACC_W-1:0] core_result [N-1:0][N-1:0]
);
    localparam int unsigned INPUT_WORDS = N*K;
    localparam int unsigned RESULT_WORDS = N*N;
    localparam logic [31:0] A_BASE = 32'h1000;
    localparam logic [31:0] B_BASE = 32'h2000;
    localparam logic [31:0] C_BASE = 32'h3000;
    localparam logic [31:0] A_END = A_BASE + 4*INPUT_WORDS;
    localparam logic [31:0] B_END = B_BASE + 4*INPUT_WORDS;
    localparam logic [31:0] C_END = C_BASE + 4*RESULT_WORDS;
    // Packed aliases share the same storage/maps. Word aligned, byte-lane INT8.
    // Tail slots are rounded to a word; an asserted out-of-range lane rejects
    // the WHOLE beat with INVALID_ADDRESS. Packed aliases are write-only.
    localparam logic [31:0] PA_BASE = 32'h4000;
    localparam logic [31:0] PB_BASE = 32'h5000;
    localparam logic [31:0] PACKED_BYTES = 4*((INPUT_WORDS+3)/4);
    logic packed_a, packed_b;
    int unsigned packed_index;
    assign packed_a = PACKED_ENABLE && wr_addr >= PA_BASE && wr_addr < PA_BASE+PACKED_BYTES;
    assign packed_b = PACKED_ENABLE && wr_addr >= PB_BASE && wr_addr < PB_BASE+PACKED_BYTES;
    assign packed_index = packed_a ? wr_addr-PA_BASE : wr_addr-PB_BASE;
    localparam logic [31:0] ERROR_MASK = 32'hff;

    typedef enum logic [1:0] {LOAD, RUN, DONE} state_t;
    state_t state;
    logic [INPUT_WORDS-1:0] a_written, b_written;
    logic inputs_ready;
    logic [31:0] error_status, wr_error_bits, rd_error_bits;
    logic [31:0] new_errors, clear_mask, byte_mask;
    logic start_accept, ack_accept;
    int unsigned wr_index, rd_index;

    initial begin
        if (N == 0 || K == 0 || INPUT_WORDS > 1024 || RESULT_WORDS > 1024)
            $fatal(1, "Shape must fit the separate 4 KiB buffer windows");
        if (DATA_W != 8 || ACC_W != 18)
            $fatal(1, "This device contract supports INT8 inputs / INT18 results");
    end

    assign inputs_ready = (&a_written) && (&b_written);
    assign wr_error = |wr_error_bits;
    assign rd_error = |rd_error_bits;
    assign new_errors = (wr_en ? wr_error_bits : 32'b0)
                      | (rd_en ? rd_error_bits : 32'b0);
    assign byte_mask = {{8{wr_strb[3]}}, {8{wr_strb[2]}},
                        {8{wr_strb[1]}}, {8{wr_strb[0]}}};
    assign clear_mask = (wr_en && !wr_error && wr_addr == 32'h0010)
                     ? (wr_data & byte_mask & ERROR_MASK) : 32'b0;
    assign start_accept = wr_en && !wr_error && wr_addr == 32'h0004
                       && wr_strb[0] && wr_data[0];
    assign ack_accept = wr_en && !wr_error && wr_addr == 32'h000c
                     && wr_strb[0] && wr_data[0] && state == DONE;

    // Decode write permissions independently of wr_en; log only an actual attempt.
    always_comb begin
        wr_error_bits = '0;
        wr_index = 0;
        if (wr_addr[1:0] != 2'b00) begin
            wr_error_bits[5] = 1'b1;
        end else if (packed_a || packed_b) begin
            if (state != LOAD) wr_error_bits[3] = 1'b1;
            else for (int unsigned lane=0; lane<4; lane++)
                if (wr_strb[lane] && packed_index+lane >= INPUT_WORDS)
                    wr_error_bits[2] = 1'b1;
        end else if (wr_addr >= A_BASE && wr_addr < A_END) begin
            wr_index = (wr_addr - A_BASE) >> 2;
            if (state != LOAD) wr_error_bits[3] = 1'b1;
        end else if (wr_addr >= B_BASE && wr_addr < B_END) begin
            wr_index = (wr_addr - B_BASE) >> 2;
            if (state != LOAD) wr_error_bits[3] = 1'b1;
        end else if (wr_addr >= C_BASE && wr_addr < C_END) begin
            wr_error_bits[6] = 1'b1;
        end else begin
            case (wr_addr)
                32'h0004: begin
                    if (wr_strb[0] && wr_data[0]) begin
                        if (state != LOAD || core_busy)
                            wr_error_bits[0] = 1'b1;
                        else if (!inputs_ready)
                            wr_error_bits[1] = 1'b1;
                    end
                end
                32'h000c, 32'h0010: begin end
                32'h0000, 32'h0008, 32'h0020, 32'h0024,
                32'h0028, 32'h002c: wr_error_bits[6] = 1'b1;
                default: wr_error_bits[2] = 1'b1;
            endcase
        end
    end

    // Combinational read view. The AXI slave captures and holds the response.
    always_comb begin
        rd_data = '0;
        rd_error_bits = '0;
        rd_index = 0;
        if (rd_addr[1:0] != 2'b00) begin
            rd_error_bits[5] = 1'b1;
        end else if (rd_addr >= A_BASE && rd_addr < A_END) begin
            rd_index = (rd_addr - A_BASE) >> 2;
            if (state != LOAD) rd_error_bits[7] = 1'b1;
            else if (a_written[rd_index])
                rd_data = {{(32-DATA_W){a_matrix[rd_index/K][rd_index%K][DATA_W-1]}},
                           a_matrix[rd_index/K][rd_index%K]};
        end else if (rd_addr >= B_BASE && rd_addr < B_END) begin
            rd_index = (rd_addr - B_BASE) >> 2;
            if (state != LOAD) rd_error_bits[7] = 1'b1;
            else if (b_written[rd_index])
                rd_data = {{(32-DATA_W){b_matrix[rd_index/N][rd_index%N][DATA_W-1]}},
                           b_matrix[rd_index/N][rd_index%N]};
        end else if (rd_addr >= C_BASE && rd_addr < C_END) begin
            rd_index = (rd_addr - C_BASE) >> 2;
            if (state != DONE) rd_error_bits[4] = 1'b1;
            else rd_data = {{(32-ACC_W){core_result[rd_index/N][rd_index%N][ACC_W-1]}},
                            core_result[rd_index/N][rd_index%N]};
        end else begin
            case (rd_addr)
                32'h0000: rd_data = 32'h0000_0200;
                32'h0008: begin
                    rd_data[0] = (state == RUN);
                    rd_data[1] = (state == DONE);
                    rd_data[2] = inputs_ready;
                    rd_data[3] = |error_status;
                end
                32'h0010: rd_data = error_status;
                32'h0020: rd_data = N;
                32'h0024: rd_data = K;
                32'h0028: rd_data = DATA_W;
                32'h002c: rd_data = ACC_W;
                default: rd_error_bits[2] = 1'b1;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= LOAD;
            core_start <= 1'b0;
            a_written <= '0;
            b_written <= '0;
            error_status <= '0;
        end else begin
            core_start <= 1'b0;
            error_status <= (error_status & ~clear_mask) | new_errors;

            case (state)
                LOAD: if (start_accept) begin
                    state <= RUN;
                    core_start <= 1'b1;
                end
                RUN: if (core_done) state <= DONE;
                DONE: if (ack_accept) begin
                    state <= LOAD;
                    a_written <= '0;
                    b_written <= '0;
                end
                default: state <= LOAD;
            endcase

            if (wr_en && !wr_error && (packed_a || packed_b)) begin
                for (int unsigned lane=0; lane<4; lane++) begin
                    if (wr_strb[lane] && packed_index+lane < INPUT_WORDS) begin
                        if (packed_a) begin
                            a_matrix[(packed_index+lane)/K][(packed_index+lane)%K]
                                <= $signed(wr_data[8*lane +: 8]);
                            a_written[packed_index+lane] <= 1'b1;
                        end else begin
                            b_matrix[(packed_index+lane)/N][(packed_index+lane)%N]
                                <= $signed(wr_data[8*lane +: 8]);
                            b_written[packed_index+lane] <= 1'b1;
                        end
                    end
                end
            end else if (wr_en && !wr_error && wr_strb[0]) begin
                if (wr_addr >= A_BASE && wr_addr < A_END) begin
                    a_matrix[wr_index/K][wr_index%K] <= $signed(wr_data[DATA_W-1:0]);
                    a_written[wr_index] <= 1'b1;
                end else if (wr_addr >= B_BASE && wr_addr < B_END) begin
                    b_matrix[wr_index/N][wr_index%N] <= $signed(wr_data[DATA_W-1:0]);
                    b_written[wr_index] <= 1'b1;
                end
            end
        end
    end
endmodule
