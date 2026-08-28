`timescale 1ns/1ps

module systolic_pe #(
    parameter int DATA_W = 8,
    parameter int ACC_W  = 18
) (
    input  logic                      clk,
    input  logic                      rst_n,
    input  logic                      acc_clear,

    input  logic signed [DATA_W-1:0]  a_in,
    input  logic                      a_valid_in,

    input  logic signed [DATA_W-1:0]  b_in,
    input  logic                      b_valid_in,

    output logic signed [DATA_W-1:0]  a_out,
    output logic                      a_valid_out,

    output logic signed [DATA_W-1:0]  b_out,
    output logic                      b_valid_out,

    output logic signed [ACC_W-1:0]   psum_out
);

    localparam int PROD_W = 2 * DATA_W;

    logic signed [PROD_W-1:0] product;
    logic signed [ACC_W-1:0]  product_ext;
    logic                     mac_valid;

    // The accumulator must be wide enough to hold one full-width product.
    initial begin
        if (DATA_W <= 0) begin
            $error("DATA_W must be greater than zero");
        end
        if (ACC_W < PROD_W) begin
            $error("ACC_W must be greater than or equal to 2 * DATA_W");
        end
    end

    // Multiplication is combinational in the baseline PE.
    assign product = $signed(a_in) * $signed(b_in);

    // Explicitly sign-extend the product to the accumulator width.
    assign product_ext = {
        {(ACC_W - PROD_W){product[PROD_W-1]}},
        product
    };

    assign mac_valid = a_valid_in && b_valid_in;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            a_out       <= '0;
            a_valid_out <= 1'b0;
            b_out       <= '0;
            b_valid_out <= 1'b0;
            psum_out    <= '0;
        end else begin
            // Data and valid bits advance independently by one PE per cycle.
            a_out       <= a_in;
            a_valid_out <= a_valid_in;
            b_out       <= b_in;
            b_valid_out <= b_valid_in;

            // Clearing starts a new accumulation and may accept its first MAC.
            if (acc_clear) begin
                if (mac_valid) begin
                    psum_out <= product_ext;
                end else begin
                    psum_out <= '0;
                end
            end else if (mac_valid) begin
                psum_out <= psum_out + product_ext;
            end
        end
    end

endmodule
