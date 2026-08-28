`timescale 1ns/1ps

module systolic_array #(
    parameter int N      = 2,
    parameter int DATA_W = 8,
    parameter int ACC_W  = 18
) (
    input  logic                              clk,
    input  logic                              rst_n,
    input  logic                              acc_clear,

    input  logic signed [DATA_W-1:0]          a_left       [N-1:0],
    input  logic                              a_valid_left [N-1:0],

    input  logic signed [DATA_W-1:0]          b_top        [N-1:0],
    input  logic                              b_valid_top  [N-1:0],

    output logic signed [ACC_W-1:0]           psum         [N-1:0][N-1:0]
);

    logic signed [DATA_W-1:0] a_pe_in       [N-1:0][N-1:0];
    logic                     a_valid_pe_in [N-1:0][N-1:0];
    logic signed [DATA_W-1:0] b_pe_in       [N-1:0][N-1:0];
    logic                     b_valid_pe_in [N-1:0][N-1:0];

    logic signed [DATA_W-1:0] a_pipe        [N-1:0][N:0];
    logic                     a_valid_pipe  [N-1:0][N:0];
    logic signed [DATA_W-1:0] b_pipe        [N:0][N-1:0];
    logic                     b_valid_pipe  [N:0][N-1:0];

    initial begin
        if (N <= 0) begin
            $error("N must be greater than zero");
        end
    end

    generate
        // Connect the external inputs to the first position of each pipe.
        for (genvar i = 0; i < N; i++) begin : gen_a_input
            assign a_pipe[i][0]       = a_left[i];
            assign a_valid_pipe[i][0] = a_valid_left[i];
        end

        for (genvar j = 0; j < N; j++) begin : gen_b_input
            assign b_pipe[0][j]       = b_top[j];
            assign b_valid_pipe[0][j] = b_valid_top[j];
        end

        for (genvar i = 0; i < N; i++) begin : gen_row
            for (genvar j = 0; j < N; j++) begin : gen_col
                // Each PE reads one pipe position and writes the next position.
                assign a_pe_in[i][j]       = a_pipe[i][j];
                assign a_valid_pe_in[i][j] = a_valid_pipe[i][j];
                assign b_pe_in[i][j]       = b_pipe[i][j];
                assign b_valid_pe_in[i][j] = b_valid_pipe[i][j];

                systolic_pe #(
                    .DATA_W(DATA_W),
                    .ACC_W (ACC_W)
                ) u_pe (
                    .clk        (clk),
                    .rst_n      (rst_n),
                    .acc_clear  (acc_clear),
                    .a_in       (a_pe_in[i][j]),
                    .a_valid_in (a_valid_pe_in[i][j]),
                    .b_in       (b_pe_in[i][j]),
                    .b_valid_in (b_valid_pe_in[i][j]),
                    .a_out      (a_pipe[i][j+1]),
                    .a_valid_out(a_valid_pipe[i][j+1]),
                    .b_out      (b_pipe[i+1][j]),
                    .b_valid_out(b_valid_pipe[i+1][j]),
                    .psum_out   (psum[i][j])
                );
            end
        end
    endgenerate

endmodule
