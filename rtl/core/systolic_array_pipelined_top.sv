`timescale 1ns/1ps

// Experimental Registered Boundary Top, kept separate from the default
// baseline. Data flows matrix -> Feeder -> Boundary register -> bare Array,
// adding one RUN cycle and preventing a raw Feeder-to-multiplier bypass.
// Idle !busy clears only Boundary state. PE accumulators are cleared solely by
// Controller acc_clear; clearing them with !busy would destroy readable results.
module systolic_array_pipelined_top #(
    parameter int N       = 2,
    parameter int K       = 2,
    parameter int DATA_W  = 8,
    parameter int ACC_W   = 18,
    parameter int CYCLE_W = ((K + (2 * N) - 1) <= 1)
                            ? 1
                            : $clog2(K + (2 * N) - 1)
) (
    input  logic                            clk,
    input  logic                            rst_n,
    input  logic                            start,

    input  logic signed [DATA_W-1:0]        a_matrix [N-1:0][K-1:0],
    input  logic signed [DATA_W-1:0]        b_matrix [K-1:0][N-1:0],

    output logic                            busy,
    output logic                            done,
    output logic signed [ACC_W-1:0]         result   [N-1:0][N-1:0]
);

    localparam int TOTAL_RUN_CYCLES = K + (2 * N) - 1;
    localparam int REQUIRED_CYCLE_W = (TOTAL_RUN_CYCLES <= 1)
                                      ? 1
                                      : $clog2(TOTAL_RUN_CYCLES);

    logic [CYCLE_W-1:0]       cycle_idx;
    logic                     acc_clear;

    logic signed [DATA_W-1:0] feeder_a       [N-1:0];
    logic                     feeder_a_valid [N-1:0];
    logic signed [DATA_W-1:0] feeder_b       [N-1:0];
    logic                     feeder_b_valid [N-1:0];

    logic signed [DATA_W-1:0] boundary_a       [N-1:0];
    logic                     boundary_a_valid [N-1:0];
    logic signed [DATA_W-1:0] boundary_b       [N-1:0];
    logic                     boundary_b_valid [N-1:0];

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
        if (CYCLE_W < REQUIRED_CYCLE_W) begin
            $error("CYCLE_W is too small for the configured operation length");
        end
    end

    systolic_pipelined_controller #(
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
        .a_left       (feeder_a),
        .a_valid_left (feeder_a_valid),
        .b_top        (feeder_b),
        .b_valid_top  (feeder_b_valid)
    );

    // The boundary stays clear while idle and captures feeder cycle zero in RUN.
    systolic_boundary_pipe #(
        .N     (N),
        .DATA_W(DATA_W)
    ) u_boundary (
        .clk        (clk),
        .rst_n      (rst_n),
        .clear      (!busy),
        .a_in       (feeder_a),
        .a_valid_in (feeder_a_valid),
        .b_in       (feeder_b),
        .b_valid_in (feeder_b_valid),
        .a_out      (boundary_a),
        .a_valid_out(boundary_a_valid),
        .b_out      (boundary_b),
        .b_valid_out(boundary_b_valid)
    );

    systolic_array #(
        .N     (N),
        .DATA_W(DATA_W),
        .ACC_W (ACC_W)
    ) u_array (
        .clk         (clk),
        .rst_n       (rst_n),
        .acc_clear   (acc_clear),
        .a_left      (boundary_a),
        .a_valid_left(boundary_a_valid),
        .b_top       (boundary_b),
        .b_valid_top (boundary_b_valid),
        .psum        (result)
    );

endmodule
