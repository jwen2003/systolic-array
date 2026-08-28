`timescale 1ns/1ps

module systolic_array_top #(
    parameter int N       = 2,
    parameter int K       = 2,
    parameter int DATA_W  = 8,
    parameter int ACC_W   = 18,
    parameter int CYCLE_W = ((K + (2 * N) - 2) <= 1)
                            ? 1
                            : $clog2(K + (2 * N) - 2)
) (
    input  logic                              clk,
    input  logic                              rst_n,
    input  logic                              start,

    input  logic signed [DATA_W-1:0]          a_matrix [N-1:0][K-1:0],
    input  logic signed [DATA_W-1:0]          b_matrix [K-1:0][N-1:0],

    output logic                              busy,
    output logic                              done,
    output logic signed [ACC_W-1:0]           result   [N-1:0][N-1:0]
);

    logic [CYCLE_W-1:0]              cycle_idx;
    logic                            acc_clear;

    logic signed [DATA_W-1:0]        a_left       [N-1:0];
    logic                            a_valid_left [N-1:0];
    logic signed [DATA_W-1:0]        b_top        [N-1:0];
    logic                            b_valid_top  [N-1:0];

    initial begin
        if (N <= 0) begin
            $error("N must be greater than zero");
        end
        if (K <= 0) begin
            $error("K must be greater than zero");
        end
        if (DATA_W <= 0) begin
            $error("DATA_W must be greater than zero");
        end
        if (ACC_W < (2 * DATA_W)) begin
            $error("ACC_W must be greater than or equal to 2 * DATA_W");
        end
    end

    systolic_controller #(
        .N      (N),
        .K      (K),
        .CYCLE_W(CYCLE_W)
    ) u_controller (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start),
        .busy     (busy),
        .done     (done),
        .acc_clear(acc_clear),
        .cycle_idx(cycle_idx)
    );

    input_feeder #(
        .N      (N),
        .K      (K),
        .DATA_W (DATA_W),
        .CYCLE_W(CYCLE_W)
    ) u_feeder (
        .enable       (busy),
        .cycle_idx    (cycle_idx),
        .a_matrix     (a_matrix),
        .b_matrix     (b_matrix),
        .a_left       (a_left),
        .a_valid_left (a_valid_left),
        .b_top        (b_top),
        .b_valid_top  (b_valid_top)
    );

    systolic_array #(
        .N     (N),
        .DATA_W(DATA_W),
        .ACC_W (ACC_W)
    ) u_array (
        .clk         (clk),
        .rst_n       (rst_n),
        .acc_clear   (acc_clear),
        .a_left      (a_left),
        .a_valid_left(a_valid_left),
        .b_top       (b_top),
        .b_valid_top (b_valid_top),
        .psum        (result)
    );

endmodule
