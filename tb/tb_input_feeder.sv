`timescale 1ns/1ps

module tb_input_feeder;

    localparam int DATA_W = 8;

    localparam int N_BASE       = 2;
    localparam int K_BASE       = 2;
    localparam int CYCLE_W_BASE = 3;

    localparam int N_RECT       = 2;
    localparam int K_RECT       = 3;
    localparam int CYCLE_W_RECT = 3;

    logic [CYCLE_W_BASE-1:0]       cycle_idx_base;
    logic                          enable_base;
    logic signed [DATA_W-1:0]      a_matrix_base [N_BASE-1:0][K_BASE-1:0];
    logic signed [DATA_W-1:0]      b_matrix_base [K_BASE-1:0][N_BASE-1:0];
    logic signed [DATA_W-1:0]      a_left_base [N_BASE-1:0];
    logic                          a_valid_left_base [N_BASE-1:0];
    logic signed [DATA_W-1:0]      b_top_base [N_BASE-1:0];
    logic                          b_valid_top_base [N_BASE-1:0];

    logic [CYCLE_W_RECT-1:0]       cycle_idx_rect;
    logic                          enable_rect;
    logic signed [DATA_W-1:0]      a_matrix_rect [N_RECT-1:0][K_RECT-1:0];
    logic signed [DATA_W-1:0]      b_matrix_rect [K_RECT-1:0][N_RECT-1:0];
    logic signed [DATA_W-1:0]      a_left_rect [N_RECT-1:0];
    logic                          a_valid_left_rect [N_RECT-1:0];
    logic signed [DATA_W-1:0]      b_top_rect [N_RECT-1:0];
    logic                          b_valid_top_rect [N_RECT-1:0];

    int test_count;

    input_feeder #(
        .N      (N_BASE),
        .K      (K_BASE),
        .DATA_W (DATA_W),
        .CYCLE_W(CYCLE_W_BASE)
    ) dut_base (
        .enable       (enable_base),
        .cycle_idx    (cycle_idx_base),
        .a_matrix     (a_matrix_base),
        .b_matrix     (b_matrix_base),
        .a_left       (a_left_base),
        .a_valid_left (a_valid_left_base),
        .b_top        (b_top_base),
        .b_valid_top  (b_valid_top_base)
    );

    input_feeder #(
        .N      (N_RECT),
        .K      (K_RECT),
        .DATA_W (DATA_W),
        .CYCLE_W(CYCLE_W_RECT)
    ) dut_rect (
        .enable       (enable_rect),
        .cycle_idx    (cycle_idx_rect),
        .a_matrix     (a_matrix_rect),
        .b_matrix     (b_matrix_rect),
        .a_left       (a_left_rect),
        .a_valid_left (a_valid_left_rect),
        .b_top        (b_top_rect),
        .b_valid_top  (b_valid_top_rect)
    );

    task automatic check_base_cycle(
        input logic [CYCLE_W_BASE-1:0]      next_cycle,
        input logic signed [DATA_W-1:0]     expected_a0,
        input logic                         expected_a0_valid,
        input logic signed [DATA_W-1:0]     expected_a1,
        input logic                         expected_a1_valid,
        input logic signed [DATA_W-1:0]     expected_b0,
        input logic                         expected_b0_valid,
        input logic signed [DATA_W-1:0]     expected_b1,
        input logic                         expected_b1_valid,
        input string                        test_name
    );
        begin
            cycle_idx_base = next_cycle;
            #1;

            if ((a_left_base[0] !== expected_a0)
                || (a_valid_left_base[0] !== expected_a0_valid)
                || (a_left_base[1] !== expected_a1)
                || (a_valid_left_base[1] !== expected_a1_valid)
                || (b_top_base[0] !== expected_b0)
                || (b_valid_top_base[0] !== expected_b0_valid)
                || (b_top_base[1] !== expected_b1)
                || (b_valid_top_base[1] !== expected_b1_valid)) begin
                $fatal(1,
                       "[%s] unexpected feeder outputs at cycle %0d",
                       test_name, next_cycle);
            end

            test_count++;
            $display("PASS %0d: %s", test_count, test_name);
        end
    endtask

    task automatic check_rect_cycle(
        input logic [CYCLE_W_RECT-1:0]      next_cycle,
        input logic signed [DATA_W-1:0]     expected_a0,
        input logic                         expected_a0_valid,
        input logic signed [DATA_W-1:0]     expected_a1,
        input logic                         expected_a1_valid,
        input logic signed [DATA_W-1:0]     expected_b0,
        input logic                         expected_b0_valid,
        input logic signed [DATA_W-1:0]     expected_b1,
        input logic                         expected_b1_valid,
        input string                        test_name
    );
        begin
            cycle_idx_rect = next_cycle;
            #1;

            if ((a_left_rect[0] !== expected_a0)
                || (a_valid_left_rect[0] !== expected_a0_valid)
                || (a_left_rect[1] !== expected_a1)
                || (a_valid_left_rect[1] !== expected_a1_valid)
                || (b_top_rect[0] !== expected_b0)
                || (b_valid_top_rect[0] !== expected_b0_valid)
                || (b_top_rect[1] !== expected_b1)
                || (b_valid_top_rect[1] !== expected_b1_valid)) begin
                $fatal(1,
                       "[%s] unexpected feeder outputs at cycle %0d",
                       test_name, next_cycle);
            end

            test_count++;
            $display("PASS %0d: %s", test_count, test_name);
        end
    endtask

    initial begin
        test_count     = 0;
        enable_base    = 1'b1;
        enable_rect    = 1'b1;
        cycle_idx_base = '0;
        cycle_idx_rect = '0;

        // Base case: A is 2x2 and B is 2x2.
        a_matrix_base[0][0] = 8'sd2;
        a_matrix_base[0][1] = -8'sd3;
        a_matrix_base[1][0] = 8'sd4;
        a_matrix_base[1][1] = 8'sd5;

        b_matrix_base[0][0] = -8'sd1;
        b_matrix_base[0][1] = 8'sd6;
        b_matrix_base[1][0] = 8'sd7;
        b_matrix_base[1][1] = -8'sd2;

        // Rectangular inner dimension: A is 2x3 and B is 3x2.
        a_matrix_rect[0][0] = 8'sd1;
        a_matrix_rect[0][1] = -8'sd2;
        a_matrix_rect[0][2] = 8'sd3;
        a_matrix_rect[1][0] = 8'sd4;
        a_matrix_rect[1][1] = 8'sd5;
        a_matrix_rect[1][2] = -8'sd6;

        b_matrix_rect[0][0] = 8'sd7;
        b_matrix_rect[0][1] = -8'sd8;
        b_matrix_rect[1][0] = 8'sd9;
        b_matrix_rect[1][1] = 8'sd10;
        b_matrix_rect[2][0] = -8'sd11;
        b_matrix_rect[2][1] = 8'sd12;

        // Allow matrix initialization to propagate through both feeders.
        #1;

        // A disabled feeder must not inject data even when cycle zero is selected.
        enable_base = 1'b0;
        check_base_cycle(
            3'd0,
            8'sd0, 1'b0, 8'sd0, 1'b0,
            8'sd0, 1'b0, 8'sd0, 1'b0,
            "disabled feeder"
        );
        enable_base = 1'b1;

        check_base_cycle(
            3'd0,
            8'sd2, 1'b1, 8'sd0, 1'b0,
            -8'sd1, 1'b1, 8'sd0, 1'b0,
            "2x2 cycle 0"
        );
        check_base_cycle(
            3'd1,
            -8'sd3, 1'b1, 8'sd4, 1'b1,
            8'sd7, 1'b1, 8'sd6, 1'b1,
            "2x2 cycle 1"
        );
        check_base_cycle(
            3'd2,
            8'sd0, 1'b0, 8'sd5, 1'b1,
            8'sd0, 1'b0, -8'sd2, 1'b1,
            "2x2 cycle 2"
        );
        check_base_cycle(
            3'd3,
            8'sd0, 1'b0, 8'sd0, 1'b0,
            8'sd0, 1'b0, 8'sd0, 1'b0,
            "2x2 post-injection cycle"
        );
        check_base_cycle(
            3'd7,
            8'sd0, 1'b0, 8'sd0, 1'b0,
            8'sd0, 1'b0, 8'sd0, 1'b0,
            "2x2 out-of-range cycle"
        );

        check_rect_cycle(
            3'd0,
            8'sd1, 1'b1, 8'sd0, 1'b0,
            8'sd7, 1'b1, 8'sd0, 1'b0,
            "2x3 cycle 0"
        );
        check_rect_cycle(
            3'd1,
            -8'sd2, 1'b1, 8'sd4, 1'b1,
            8'sd9, 1'b1, -8'sd8, 1'b1,
            "2x3 cycle 1"
        );
        check_rect_cycle(
            3'd2,
            8'sd3, 1'b1, 8'sd5, 1'b1,
            -8'sd11, 1'b1, 8'sd10, 1'b1,
            "2x3 cycle 2"
        );
        check_rect_cycle(
            3'd3,
            8'sd0, 1'b0, -8'sd6, 1'b1,
            8'sd0, 1'b0, 8'sd12, 1'b1,
            "2x3 final injection cycle"
        );
        check_rect_cycle(
            3'd4,
            8'sd0, 1'b0, 8'sd0, 1'b0,
            8'sd0, 1'b0, 8'sd0, 1'b0,
            "2x3 post-injection cycle"
        );

        $display("All %0d input_feeder tests passed.", test_count);
        $finish;
    end

endmodule
