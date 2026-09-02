`timescale 1ns/1ps

// Self-checking N2/K2 Registered Boundary integration test. It proves RUN zero
// performs no MAC, traces the delayed wavefront through the RUN-four final
// commit, aligns done with final psums, and checks a clean second operation.
// Falling-edge stimulus avoids DUT races; any $fatal is a contract failure and
// the final message means every directed integration checkpoint passed.
module tb_systolic_array_pipelined_top;

    localparam int N       = 2;
    localparam int K       = 2;
    localparam int DATA_W  = 8;
    localparam int ACC_W   = 18;
    localparam int CYCLE_W = 3;

    logic                            clk;
    logic                            rst_n;
    logic                            start;
    logic signed [DATA_W-1:0]        a_matrix [N-1:0][K-1:0];
    logic signed [DATA_W-1:0]        b_matrix [K-1:0][N-1:0];
    logic                            busy;
    logic                            done;
    logic signed [ACC_W-1:0]         result   [N-1:0][N-1:0];

    int test_count;

    systolic_array_pipelined_top #(
        .N      (N),
        .K      (K),
        .DATA_W (DATA_W),
        .ACC_W  (ACC_W),
        .CYCLE_W(CYCLE_W)
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .start   (start),
        .a_matrix(a_matrix),
        .b_matrix(b_matrix),
        .busy    (busy),
        .done    (done),
        .result  (result)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check_state(
        input logic                    expected_busy,
        input logic                    expected_done,
        input logic                    expected_clear,
        input logic [CYCLE_W-1:0]      expected_cycle,
        input logic signed [ACC_W-1:0] expected_00,
        input logic signed [ACC_W-1:0] expected_01,
        input logic signed [ACC_W-1:0] expected_10,
        input logic signed [ACC_W-1:0] expected_11,
        input string                   test_name
    );
        begin
            if ((busy !== expected_busy)
                || (done !== expected_done)
                || (dut.acc_clear !== expected_clear)
                || (dut.cycle_idx !== expected_cycle)
                || (result[0][0] !== expected_00)
                || (result[0][1] !== expected_01)
                || (result[1][0] !== expected_10)
                || (result[1][1] !== expected_11)) begin
                $fatal(1,
                       "[%s] expected ctrl=%0b/%0b/%0b/%0d result=[[%0d,%0d],[%0d,%0d]], got ctrl=%0b/%0b/%0b/%0d result=[[%0d,%0d],[%0d,%0d]]",
                       test_name,
                       expected_busy, expected_done,
                       expected_clear, expected_cycle,
                       expected_00, expected_01, expected_10, expected_11,
                       busy, done, dut.acc_clear, dut.cycle_idx,
                       result[0][0], result[0][1],
                       result[1][0], result[1][1]);
            end

            test_count++;
            $display("PASS %0d: %s", test_count, test_name);
        end
    endtask

    task automatic check_boundary_valid(
        input logic  expected_a0,
        input logic  expected_a1,
        input logic  expected_b0,
        input logic  expected_b1,
        input string test_name
    );
        begin
            if ((dut.boundary_a_valid[0] !== expected_a0)
                || (dut.boundary_a_valid[1] !== expected_a1)
                || (dut.boundary_b_valid[0] !== expected_b0)
                || (dut.boundary_b_valid[1] !== expected_b1)) begin
                $fatal(1,
                       "[%s] expected A valid=%0b%0b B valid=%0b%0b, got A valid=%0b%0b B valid=%0b%0b",
                       test_name,
                       expected_a1, expected_a0, expected_b1, expected_b0,
                       dut.boundary_a_valid[1], dut.boundary_a_valid[0],
                       dut.boundary_b_valid[1], dut.boundary_b_valid[0]);
            end

            test_count++;
            $display("PASS %0d: %s", test_count, test_name);
        end
    endtask

    task automatic load_first_matrices;
        begin
            // A = [[2, -3], [4, 5]]
            // B = [[-1, 6], [7, -2]]
            a_matrix[0][0] = 8'sd2;
            a_matrix[0][1] = -8'sd3;
            a_matrix[1][0] = 8'sd4;
            a_matrix[1][1] = 8'sd5;

            b_matrix[0][0] = -8'sd1;
            b_matrix[0][1] = 8'sd6;
            b_matrix[1][0] = 8'sd7;
            b_matrix[1][1] = -8'sd2;
        end
    endtask

    task automatic load_second_matrices;
        begin
            // A = [[-2, 3], [5, -4]]
            // B = [[6, 7], [-8, 9]]
            a_matrix[0][0] = -8'sd2;
            a_matrix[0][1] = 8'sd3;
            a_matrix[1][0] = 8'sd5;
            a_matrix[1][1] = -8'sd4;

            b_matrix[0][0] = 8'sd6;
            b_matrix[0][1] = 8'sd7;
            b_matrix[1][0] = -8'sd8;
            b_matrix[1][1] = 8'sd9;
        end
    endtask

    initial begin
        test_count = 0;
        rst_n      = 1'b0;
        start      = 1'b0;

        for (int i = 0; i < N; i++) begin
            for (int k = 0; k < K; k++) begin
                a_matrix[i][k] = '0;
            end
        end
        for (int k = 0; k < K; k++) begin
            for (int j = 0; j < N; j++) begin
                b_matrix[k][j] = '0;
            end
        end

        // One active reset edge synchronously clears control, boundary, and PEs.
        @(posedge clk);
        #1;
        check_state(1'b0, 1'b0, 1'b0, 3'd0,
                    18'sd0, 18'sd0, 18'sd0, 18'sd0,
                    "synchronous reset");
        check_boundary_valid(1'b0, 1'b0, 1'b0, 1'b0,
                             "boundary reset");

        @(negedge clk);
        rst_n = 1'b1;
        load_first_matrices();
        start = 1'b1;

        // Start acceptance exposes RUN zero while the idle boundary remains clear.
        @(posedge clk);
        #1;
        check_state(1'b1, 1'b0, 1'b1, 3'd0,
                    18'sd0, 18'sd0, 18'sd0, 18'sd0,
                    "operation 1 start acceptance");
        check_boundary_valid(1'b0, 1'b0, 1'b0, 1'b0,
                             "operation 1 boundary clear at acceptance");

        @(negedge clk);
        start = 1'b0;

        // RUN zero captures feeder cycle zero while accumulator clear wins in PEs.
        @(posedge clk);
        #1;
        check_state(1'b1, 1'b0, 1'b0, 3'd1,
                    18'sd0, 18'sd0, 18'sd0, 18'sd0,
                    "operation 1 after RUN 0");
        check_boundary_valid(1'b1, 1'b0, 1'b1, 1'b0,
                             "operation 1 feeder cycle 0 captured");

        // An extra start pulse during RUN must not restart the controller.
        @(negedge clk);
        start = 1'b1;

        @(posedge clk);
        #1;
        check_state(1'b1, 1'b0, 1'b0, 3'd2,
                    -18'sd2, 18'sd0, 18'sd0, 18'sd0,
                    "operation 1 after RUN 1");

        @(negedge clk);
        start = 1'b0;

        @(posedge clk);
        #1;
        check_state(1'b1, 1'b0, 1'b0, 3'd3,
                    -18'sd23, 18'sd12, -18'sd4, 18'sd0,
                    "operation 1 after RUN 2");

        @(posedge clk);
        #1;
        check_state(1'b1, 1'b0, 1'b0, 3'd4,
                    -18'sd23, 18'sd18, 18'sd31, 18'sd24,
                    "operation 1 after RUN 3");

        // The final MAC and done become visible after the same RUN-four edge.
        @(posedge clk);
        #1;
        check_state(1'b0, 1'b1, 1'b0, 3'd4,
                    -18'sd23, 18'sd18, 18'sd31, 18'sd14,
                    "operation 1 after RUN 4 completion");

        // Idle clears only boundary state; completed sums remain observable.
        @(posedge clk);
        #1;
        check_state(1'b0, 1'b0, 1'b0, 3'd4,
                    -18'sd23, 18'sd18, 18'sd31, 18'sd14,
                    "operation 1 idle result hold");
        check_boundary_valid(1'b0, 1'b0, 1'b0, 1'b0,
                             "operation 1 idle boundary clear");

        @(negedge clk);
        load_second_matrices();
        start = 1'b1;

        // The second acceptance sees no residual valid data in the boundary.
        @(posedge clk);
        #1;
        check_state(1'b1, 1'b0, 1'b1, 3'd0,
                    -18'sd23, 18'sd18, 18'sd31, 18'sd14,
                    "operation 2 start acceptance");
        check_boundary_valid(1'b0, 1'b0, 1'b0, 1'b0,
                             "operation 2 starts with empty boundary");

        @(negedge clk);
        start = 1'b0;

        // RUN zero clears old sums and captures the new feeder values.
        @(posedge clk);
        #1;
        check_state(1'b1, 1'b0, 1'b0, 3'd1,
                    18'sd0, 18'sd0, 18'sd0, 18'sd0,
                    "operation 2 after RUN 0 clear");
        check_boundary_valid(1'b1, 1'b0, 1'b1, 1'b0,
                             "operation 2 feeder cycle 0 captured");

        repeat (3) begin
            @(posedge clk);
            #1;
        end

        if ((busy !== 1'b1) || (done !== 1'b0)
            || (dut.cycle_idx !== 3'd4)) begin
            $fatal(1, "Operation 2 did not reach active RUN cycle 4");
        end

        @(posedge clk);
        #1;
        check_state(1'b0, 1'b1, 1'b0, 3'd4,
                    -18'sd36, 18'sd13, 18'sd62, -18'sd1,
                    "operation 2 final result");

        $display("All %0d systolic_array_pipelined_top tests passed.",
                 test_count);
        $finish;
    end

endmodule
