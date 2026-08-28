`timescale 1ns/1ps

module tb_systolic_array_random #(
    parameter int          N                = 2,
    parameter int          K                = 2,
    parameter int          DATA_W           = 8,
    parameter int          ACC_W            = 18,
    parameter int          NUM_RANDOM_TESTS = 100,
    parameter int unsigned SEED             = 32'h5a17_c3e9
);

    localparam int TOTAL_CYCLES = K + (2 * N) - 2;

    logic                             clk;
    logic                             rst_n;
    logic                             start;
    logic signed [DATA_W-1:0]         a_matrix [N-1:0][K-1:0];
    logic signed [DATA_W-1:0]         b_matrix [K-1:0][N-1:0];
    logic                             busy;
    logic                             done;
    logic signed [ACC_W-1:0]          result   [N-1:0][N-1:0];
    logic signed [ACC_W-1:0]          expected [N-1:0][N-1:0];

    logic [31:0] rng_state;
    int unsigned completed_tests;

    systolic_array_top #(
        .N     (N),
        .K     (K),
        .DATA_W(DATA_W),
        .ACC_W (ACC_W)
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

    // Use a local PRNG so identical seeds generate identical matrices.
    function automatic logic [31:0] next_random;
        logic [31:0] value;
        begin
            value = rng_state;
            value = value ^ (value << 13);
            value = value ^ (value >> 17);
            value = value ^ (value << 5);
            rng_state = value;
            return value;
        end
    endfunction

    task automatic generate_random_matrices;
        begin
            for (int i = 0; i < N; i++) begin
                for (int k = 0; k < K; k++) begin
                    a_matrix[i][k] = DATA_W'(next_random());
                end
            end

            for (int k = 0; k < K; k++) begin
                for (int j = 0; j < N; j++) begin
                    b_matrix[k][j] = DATA_W'(next_random());
                end
            end
        end
    endtask

    task automatic calculate_expected;
        longint signed sum;
        longint signed product;
        begin
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    sum = 0;
                    for (int k = 0; k < K; k++) begin
                        product = longint'($signed(a_matrix[i][k]))
                                  * longint'($signed(b_matrix[k][j]));
                        sum = sum + product;
                    end
                    expected[i][j] = ACC_W'(sum);
                end
            end
        end
    endtask

    task automatic print_failure_context(
        input int unsigned operation_idx
    );
        begin
            $display("Failure context: operation=%0d seed=0x%08x N=%0d K=%0d",
                     operation_idx, SEED, N, K);

            $display("Matrix A:");
            for (int i = 0; i < N; i++) begin
                $write("  [");
                for (int k = 0; k < K; k++) begin
                    $write("%0d%s", a_matrix[i][k], (k == (K - 1)) ? "" : ", ");
                end
                $display("]");
            end

            $display("Matrix B:");
            for (int k = 0; k < K; k++) begin
                $write("  [");
                for (int j = 0; j < N; j++) begin
                    $write("%0d%s", b_matrix[k][j], (j == (N - 1)) ? "" : ", ");
                end
                $display("]");
            end

            $display("Expected / actual result:");
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    $display("  C[%0d][%0d]: expected=%0d actual=%0d",
                             i, j, expected[i][j], result[i][j]);
                end
            end
        end
    endtask

    task automatic check_all_results(
        input int unsigned operation_idx
    );
        begin
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    if (result[i][j] !== expected[i][j]) begin
                        print_failure_context(operation_idx);
                        $fatal(1, "Result mismatch at C[%0d][%0d]", i, j);
                    end
                end
            end
        end
    endtask

    task automatic run_operation(
        input int unsigned operation_idx
    );
        int observed_run_cycles;
        begin
            generate_random_matrices();
            calculate_expected();

            @(negedge clk);
            start = 1'b1;

            @(posedge clk);
            #1;
            if ((busy !== 1'b1) || (done !== 1'b0)) begin
                print_failure_context(operation_idx);
                $fatal(1, "Operation was not accepted from IDLE");
            end

            @(negedge clk);
            start = 1'b0;

            observed_run_cycles = 0;
            while (done !== 1'b1) begin
                @(posedge clk);
                #1;
                observed_run_cycles++;

                if (observed_run_cycles > TOTAL_CYCLES) begin
                    print_failure_context(operation_idx);
                    $fatal(1, "Operation timed out after %0d RUN cycles",
                           observed_run_cycles);
                end

                if ((done !== 1'b1) && (busy !== 1'b1)) begin
                    print_failure_context(operation_idx);
                    $fatal(1, "busy deasserted before the final RUN cycle");
                end
            end

            if (observed_run_cycles != TOTAL_CYCLES) begin
                print_failure_context(operation_idx);
                $fatal(1, "Expected %0d RUN cycles, observed %0d",
                       TOTAL_CYCLES, observed_run_cycles);
            end
            if (busy !== 1'b0) begin
                print_failure_context(operation_idx);
                $fatal(1, "busy must be low when done is asserted");
            end

            check_all_results(operation_idx);
            completed_tests++;
        end
    endtask

    task automatic wait_random_idle(
        input int unsigned operation_idx
    );
        logic [31:0] random_word;
        int unsigned idle_cycles;
        begin
            random_word = next_random();
            idle_cycles = int'(random_word % 32'd4);

            for (int cycle = 0; cycle < idle_cycles; cycle++) begin
                @(posedge clk);
                #1;
                if ((busy !== 1'b0) || (done !== 1'b0)) begin
                    print_failure_context(operation_idx);
                    $fatal(1, "Control outputs did not return to IDLE");
                end
                check_all_results(operation_idx);
            end
        end
    endtask

    initial begin
        if (N <= 0) begin
            $fatal(1, "N must be greater than zero");
        end
        if (K <= 0) begin
            $fatal(1, "K must be greater than zero");
        end
        if ((DATA_W <= 0) || (DATA_W > 32)) begin
            $fatal(1, "DATA_W must be in the range 1 through 32");
        end
        if (ACC_W < (2 * DATA_W)) begin
            $fatal(1, "ACC_W must be greater than or equal to 2 * DATA_W");
        end
        if (NUM_RANDOM_TESTS <= 0) begin
            $fatal(1, "NUM_RANDOM_TESTS must be greater than zero");
        end
        if ((DATA_W == 8) && (ACC_W == 18) && (K > 4)) begin
            $fatal(1, "The full-range 8-bit baseline requires K <= 4 for ACC_W=18");
        end

        completed_tests = 0;
        rst_n           = 1'b0;
        start           = 1'b0;
        rng_state       = (SEED == 0) ? 32'h1 : SEED;

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

        $display("Random regression: N=%0d K=%0d DATA_W=%0d ACC_W=%0d tests=%0d seed=0x%08x",
                 N, K, DATA_W, ACC_W, NUM_RANDOM_TESTS, SEED);

        // Apply a synchronous reset before the first operation.
        @(posedge clk);
        #1;
        rst_n = 1'b1;

        for (int unsigned operation_idx = 0;
             operation_idx < NUM_RANDOM_TESTS;
             operation_idx++) begin
            run_operation(operation_idx);
            wait_random_idle(operation_idx);
        end

        $display("All %0d random systolic array operations passed for N=%0d K=%0d seed=0x%08x.",
                 completed_tests, N, K, SEED);
        $finish;
    end

endmodule
