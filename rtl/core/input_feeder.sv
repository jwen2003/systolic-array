`timescale 1ns/1ps

// Combinational boundary scheduler for the baseline array. It reads complete
// matrices and derives skewed row/column injections from the current cycle.
// The matrices are not stored here and must remain stable for the enabled RUN
// window; this module neither accepts commands nor generates completion.
module input_feeder #(
    parameter int N       = 2,
    parameter int K       = 2,
    parameter int DATA_W  = 8,
    parameter int CYCLE_W = ((K + (2 * N) - 2) <= 1)
                            ? 1
                            : $clog2(K + (2 * N) - 2)
) (
    input  logic                               enable,
    input  logic [CYCLE_W-1:0]                 cycle_idx,

    input  logic signed [DATA_W-1:0]           a_matrix [N-1:0][K-1:0],
    input  logic signed [DATA_W-1:0]           b_matrix [K-1:0][N-1:0],

    output logic signed [DATA_W-1:0]           a_left       [N-1:0],
    output logic                                a_valid_left [N-1:0],

    output logic signed [DATA_W-1:0]           b_top        [N-1:0],
    output logic                                b_valid_top  [N-1:0]
);

    localparam int TOTAL_CYCLES     = K + (2 * N) - 2;
    localparam int REQUIRED_CYCLE_W = (TOTAL_CYCLES <= 1)
                                      ? 1
                                      : $clog2(TOTAL_CYCLES);

    integer unsigned cycle_value;

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
        if (CYCLE_W <= 0) begin
            $error("CYCLE_W must be greater than zero");
        end
        if (CYCLE_W < REQUIRED_CYCLE_W) begin
            $error("CYCLE_W is too small for the configured operation length");
        end
    end

    always_comb begin
        cycle_value = int'($unsigned(cycle_idx));

        // Invalid lanes carry zero data to keep waveforms deterministic.
        // enable qualifies every lane so an idle feeder cannot inject a MAC.
        for (int i = 0; i < N; i++) begin
            a_left[i]       = '0;
            a_valid_left[i] = 1'b0;

            // Row i injects A[i][k] during cycles i through i + K - 1.
            if (enable
                && (cycle_value >= i)
                && (cycle_value < (i + K))) begin
                a_left[i]       = a_matrix[i][cycle_value - i];
                a_valid_left[i] = 1'b1;
            end
        end

        for (int j = 0; j < N; j++) begin
            b_top[j]       = '0;
            b_valid_top[j] = 1'b0;

            // Column j injects B[k][j] during cycles j through j + K - 1.
            if (enable
                && (cycle_value >= j)
                && (cycle_value < (j + K))) begin
                b_top[j]       = b_matrix[cycle_value - j][j];
                b_valid_top[j] = 1'b1;
            end
        end
    end

endmodule
