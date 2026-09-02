module systolic_boundary_pipe #(
    parameter int N      = 2,
    parameter int DATA_W = 8
) (
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic                         clear,

    input  logic signed [DATA_W-1:0]     a_in        [N-1:0],
    input  logic                         a_valid_in  [N-1:0],
    input  logic signed [DATA_W-1:0]     b_in        [N-1:0],
    input  logic                         b_valid_in  [N-1:0],

    output logic signed [DATA_W-1:0]     a_out       [N-1:0],
    output logic                         a_valid_out [N-1:0],
    output logic signed [DATA_W-1:0]     b_out       [N-1:0],
    output logic                         b_valid_out [N-1:0]
);

    timeunit 1ns;
    timeprecision 1ps;

    initial begin
        if (N <= 0) begin
            $error("N must be greater than zero");
        end
        if (DATA_W <= 0) begin
            $error("DATA_W must be greater than zero");
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int lane = 0; lane < N; lane++) begin
                a_out[lane]       <= '0;
                a_valid_out[lane] <= 1'b0;
                b_out[lane]       <= '0;
                b_valid_out[lane] <= 1'b0;
            end
        end else if (clear) begin
            for (int lane = 0; lane < N; lane++) begin
                a_out[lane]       <= '0;
                a_valid_out[lane] <= 1'b0;
                b_out[lane]       <= '0;
                b_valid_out[lane] <= 1'b0;
            end
        end else begin
            for (int lane = 0; lane < N; lane++) begin
                a_out[lane]       <= a_in[lane];
                a_valid_out[lane] <= a_valid_in[lane];
                b_out[lane]       <= b_in[lane];
                b_valid_out[lane] <= b_valid_in[lane];
            end
        end
    end

endmodule
