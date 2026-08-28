`timescale 1ns/1ps

module systolic_controller #(
    parameter int N       = 2,
    parameter int K       = 2,
    parameter int CYCLE_W = ((K + (2 * N) - 2) <= 1)
                            ? 1
                            : $clog2(K + (2 * N) - 2)
) (
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   start,

    output logic                   busy,
    output logic                   done,
    output logic                   acc_clear,
    output logic [CYCLE_W-1:0]     cycle_idx
);

    localparam int TOTAL_CYCLES     = K + (2 * N) - 2;
    localparam int LAST_CYCLE       = TOTAL_CYCLES - 1;
    localparam int REQUIRED_CYCLE_W = (TOTAL_CYCLES <= 1)
                                      ? 1
                                      : $clog2(TOTAL_CYCLES);
    localparam logic [CYCLE_W-1:0] LAST_CYCLE_VALUE = CYCLE_W'(LAST_CYCLE);

    initial begin
        if (N <= 0) begin
            $error("N must be greater than zero");
        end
        if (K <= 0) begin
            $error("K must be greater than zero");
        end
        if (CYCLE_W < REQUIRED_CYCLE_W) begin
            $error("CYCLE_W is too small for the configured operation length");
        end
    end

    // The first active cycle clears every accumulator and may accept a MAC.
    assign acc_clear = busy && (cycle_idx == '0);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            busy      <= 1'b0;
            done      <= 1'b0;
            cycle_idx <= '0;
        end else begin
            // Completion is reported as a single-cycle pulse.
            done <= 1'b0;

            if (!busy) begin
                if (start) begin
                    busy      <= 1'b1;
                    cycle_idx <= '0;
                end
            end else if (cycle_idx == LAST_CYCLE_VALUE) begin
                busy <= 1'b0;
                done <= 1'b1;
            end else begin
                cycle_idx <= cycle_idx + 1'b1;
            end
        end
    end

endmodule
