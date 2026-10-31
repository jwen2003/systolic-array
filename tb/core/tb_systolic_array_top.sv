`timescale 1ns/1ps

// Self-checking baseline Top test for complete operations, exact completion
// timing, result hold, and accumulator replacement on a second operation.
// Matrices and start are driven away from active sampling edges; $fatal reports
// a protocol or result mismatch, and the final message means all Top scenarios
// and both parameter instances passed.
module tb_systolic_array_top;

    localparam int DATA_W = 8;
    localparam int ACC_W  = 18;

    localparam int N_BASE = 2;
    localparam int K_BASE = 2;

    localparam int N_RECT = 2;
    localparam int K_RECT = 3;

    logic                              clk;
    logic                              rst_n;

    logic                              start_base;
    logic signed [DATA_W-1:0]          a_matrix_base [N_BASE-1:0][K_BASE-1:0];
    logic signed [DATA_W-1:0]          b_matrix_base [K_BASE-1:0][N_BASE-1:0];
    logic                              busy_base;
    logic                              done_base;
    logic signed [ACC_W-1:0]           result_base [N_BASE-1:0][N_BASE-1:0];

    logic                              start_rect;
    logic signed [DATA_W-1:0]          a_matrix_rect [N_RECT-1:0][K_RECT-1:0];
    logic signed [DATA_W-1:0]          b_matrix_rect [K_RECT-1:0][N_RECT-1:0];
    logic                              busy_rect;
    logic                              done_rect;
    logic signed [ACC_W-1:0]           result_rect [N_RECT-1:0][N_RECT-1:0];

    int test_count;

    systolic_array_top #(
        .N     (N_BASE),
        .K     (K_BASE),
        .DATA_W(DATA_W),
        .ACC_W (ACC_W)
    ) dut_base (
        .clk     (clk),
        .rst_n   (rst_n),
        .start   (start_base),
        .a_matrix(a_matrix_base),
        .b_matrix(b_matrix_base),
        .busy    (busy_base),
        .done    (done_base),
        .result  (result_base)
    );

    systolic_array_top #(
        .N     (N_RECT),
        .K     (K_RECT),
        .DATA_W(DATA_W),
        .ACC_W (ACC_W)
    ) dut_rect (
        .clk     (clk),
        .rst_n   (rst_n),
        .start   (start_rect),
        .a_matrix(a_matrix_rect),
        .b_matrix(b_matrix_rect),
        .busy    (busy_rect),
        .done    (done_rect),
        .result  (result_rect)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check_base_result(
        input logic signed [ACC_W-1:0] expected_00,
        input logic signed [ACC_W-1:0] expected_01,
        input logic signed [ACC_W-1:0] expected_10,
        input logic signed [ACC_W-1:0] expected_11,
        input string                   test_name
    );
        begin
            if ((result_base[0][0] !== expected_00)
                || (result_base[0][1] !== expected_01)
                || (result_base[1][0] !== expected_10)
                || (result_base[1][1] !== expected_11)) begin
                $fatal(1,
                       "[%s] expected [[%0d, %0d], [%0d, %0d]], got [[%0d, %0d], [%0d, %0d]]",
                       test_name,
                       expected_00, expected_01,
                       expected_10, expected_11,
                       result_base[0][0], result_base[0][1],
                       result_base[1][0], result_base[1][1]);
            end

            test_count++;
            $display("PASS %0d: %s", test_count, test_name);
        end
    endtask

    task automatic check_rect_result(
        input logic signed [ACC_W-1:0] expected_00,
        input logic signed [ACC_W-1:0] expected_01,
        input logic signed [ACC_W-1:0] expected_10,
        input logic signed [ACC_W-1:0] expected_11,
        input string                   test_name
    );
        begin
            if ((result_rect[0][0] !== expected_00)
                || (result_rect[0][1] !== expected_01)
                || (result_rect[1][0] !== expected_10)
                || (result_rect[1][1] !== expected_11)) begin
                $fatal(1,
                       "[%s] expected [[%0d, %0d], [%0d, %0d]], got [[%0d, %0d], [%0d, %0d]]",
                       test_name,
                       expected_00, expected_01,
                       expected_10, expected_11,
                       result_rect[0][0], result_rect[0][1],
                       result_rect[1][0], result_rect[1][1]);
            end

            test_count++;
            $display("PASS %0d: %s", test_count, test_name);
        end
    endtask

    task automatic start_base_operation;
        begin
            @(negedge clk);
            start_base = 1'b1;
            @(posedge clk);
            #1;

            if ((busy_base !== 1'b1) || (done_base !== 1'b0)) begin
                $fatal(1, "Base operation was not accepted");
            end

            @(negedge clk);
            start_base = 1'b0;
        end
    endtask

    task automatic start_rect_operation;
        begin
            @(negedge clk);
            start_rect = 1'b1;
            @(posedge clk);
            #1;

            if ((busy_rect !== 1'b1) || (done_rect !== 1'b0)) begin
                $fatal(1, "Rectangular operation was not accepted");
            end

            @(negedge clk);
            start_rect = 1'b0;
        end
    endtask

    task automatic wait_for_base_done(
        input int expected_run_cycles
    );
        int observed_run_cycles;
        begin
            observed_run_cycles = 0;

            while (done_base !== 1'b1) begin
                @(posedge clk);
                #1;
                observed_run_cycles++;

                if (observed_run_cycles > expected_run_cycles) begin
                    $fatal(1, "Base operation timed out");
                end
            end

            if (observed_run_cycles != expected_run_cycles) begin
                $fatal(1,
                       "Base operation expected %0d RUN cycles, observed %0d",
                       expected_run_cycles, observed_run_cycles);
            end
            if (busy_base !== 1'b0) begin
                $fatal(1, "Base busy must be low when done is asserted");
            end
        end
    endtask

    task automatic wait_for_rect_done(
        input int expected_run_cycles
    );
        int observed_run_cycles;
        begin
            observed_run_cycles = 0;

            while (done_rect !== 1'b1) begin
                @(posedge clk);
                #1;
                observed_run_cycles++;

                if (observed_run_cycles > expected_run_cycles) begin
                    $fatal(1, "Rectangular operation timed out");
                end
            end

            if (observed_run_cycles != expected_run_cycles) begin
                $fatal(1,
                       "Rectangular operation expected %0d RUN cycles, observed %0d",
                       expected_run_cycles, observed_run_cycles);
            end
            if (busy_rect !== 1'b0) begin
                $fatal(1, "Rectangular busy must be low when done is asserted");
            end
        end
    endtask

    initial begin
        test_count = 0;
        rst_n      = 1'b0;
        start_base = 1'b0;
        start_rect = 1'b0;

        // Initialize every matrix element before releasing reset.
        for (int i = 0; i < N_BASE; i++) begin
            for (int k = 0; k < K_BASE; k++) begin
                a_matrix_base[i][k] = '0;
            end
        end
        for (int k = 0; k < K_BASE; k++) begin
            for (int j = 0; j < N_BASE; j++) begin
                b_matrix_base[k][j] = '0;
            end
        end
        for (int i = 0; i < N_RECT; i++) begin
            for (int k = 0; k < K_RECT; k++) begin
                a_matrix_rect[i][k] = '0;
            end
        end
        for (int k = 0; k < K_RECT; k++) begin
            for (int j = 0; j < N_RECT; j++) begin
                b_matrix_rect[k][j] = '0;
            end
        end

        // Apply one synchronous reset edge to both top-level instances.
        @(posedge clk);
        #1;
        if ((busy_base !== 1'b0) || (done_base !== 1'b0)
            || (busy_rect !== 1'b0) || (done_rect !== 1'b0)) begin
            $fatal(1, "Top-level control outputs did not reset");
        end
        check_base_result(18'sd0, 18'sd0, 18'sd0, 18'sd0,
                          "base reset results");
        check_rect_result(18'sd0, 18'sd0, 18'sd0, 18'sd0,
                          "rectangular reset results");

        @(negedge clk);
        rst_n = 1'b1;

        // Operation 1: signed 2x2 matrix multiplication.
        // A = [[2, -3], [4, 5]]
        // B = [[-1, 6], [7, -2]]
        // C = [[-23, 18], [31, 14]]
        a_matrix_base[0][0] = 8'sd2;
        a_matrix_base[0][1] = -8'sd3;
        a_matrix_base[1][0] = 8'sd4;
        a_matrix_base[1][1] = 8'sd5;

        b_matrix_base[0][0] = -8'sd1;
        b_matrix_base[0][1] = 8'sd6;
        b_matrix_base[1][0] = 8'sd7;
        b_matrix_base[1][1] = -8'sd2;

        start_base_operation();
        wait_for_base_done(K_BASE + (2 * N_BASE) - 2);
        check_base_result(-18'sd23, 18'sd18, 18'sd31, 18'sd14,
                          "base operation 1 result");

        // Idle clocks must not modify the completed result.
        repeat (2) begin
            @(posedge clk);
            #1;
        end
        if (done_base !== 1'b0) begin
            $fatal(1, "Base done must be a single-cycle pulse");
        end
        check_base_result(-18'sd23, 18'sd18, 18'sd31, 18'sd14,
                          "base idle result hold");

        // Operation 2 proves that cycle-zero clear removes prior results.
        // A = [[-2, 3], [5, -4]]
        // B = [[6, 7], [-8, 9]]
        // C = [[-36, 13], [62, -1]]
        a_matrix_base[0][0] = -8'sd2;
        a_matrix_base[0][1] = 8'sd3;
        a_matrix_base[1][0] = 8'sd5;
        a_matrix_base[1][1] = -8'sd4;

        b_matrix_base[0][0] = 8'sd6;
        b_matrix_base[0][1] = 8'sd7;
        b_matrix_base[1][0] = -8'sd8;
        b_matrix_base[1][1] = 8'sd9;

        start_base_operation();
        wait_for_base_done(K_BASE + (2 * N_BASE) - 2);
        check_base_result(-18'sd36, 18'sd13, 18'sd62, -18'sd1,
                          "base operation 2 result");

        // Rectangular inner dimension: A is 2x3 and B is 3x2.
        // C = [[-44, 8], [139, -54]]
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

        start_rect_operation();
        wait_for_rect_done(K_RECT + (2 * N_RECT) - 2);
        check_rect_result(-18'sd44, 18'sd8, 18'sd139, -18'sd54,
                          "rectangular operation result");

        $display("All %0d systolic_array_top tests passed.", test_count);
        $finish;
    end

endmodule
