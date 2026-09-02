`timescale 1ns/1ps

module tb_systolic_array_pipelined_random #(
    parameter int          N                = 2,
    parameter int          K                = 2,
    parameter int          DATA_W           = 8,
    parameter int          ACC_W            = 18,
    parameter int          NUM_RANDOM_TESTS = 100,
    parameter int unsigned SEED             = 32'h5a17_c3e9
);

    localparam int TOTAL_RUN_CYCLES = K + (2 * N) - 1;
    localparam int LAST_CYCLE   = TOTAL_RUN_CYCLES - 1;
    localparam int NUM_CORNERS  = 9;
    localparam int CYCLE_W      = (TOTAL_RUN_CYCLES <= 1) ? 1 : $clog2(TOTAL_RUN_CYCLES);

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
    int unsigned active_operation_idx;
    int unsigned mac_count [N-1:0][N-1:0];
    logic prev_valid;
    logic prev_busy;
    logic prev_done;
    logic [CYCLE_W-1:0] prev_cycle_idx;
    logic signed [DATA_W-1:0] stable_a [N-1:0][K-1:0];
    logic signed [DATA_W-1:0] stable_b [K-1:0][N-1:0];

    systolic_array_pipelined_top #(
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

    // Check the exact A/B/k identity consumed by every PE each RUN cycle.
    task automatic check_cycle_pairing(
        input int cycle_value
    );
        int k_value;
        begin
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    k_value = cycle_value - 1 - i - j;

                    if ((k_value >= 0) && (k_value < K)) begin
                        if ((dut.u_array.a_valid_pe_in[i][j] !== 1'b1)
                            || (dut.u_array.b_valid_pe_in[i][j] !== 1'b1)) begin
                            $fatal(1,
                                   "Pairing valid mismatch: operation=%0d cycle=%0d PE[%0d][%0d] k=%0d a_valid=%0b b_valid=%0b",
                                   active_operation_idx, cycle_value, i, j, k_value,
                                   dut.u_array.a_valid_pe_in[i][j],
                                   dut.u_array.b_valid_pe_in[i][j]);
                        end

                        if (dut.u_array.a_pe_in[i][j] !== a_matrix[i][k_value]) begin
                            $fatal(1,
                                   "A pairing mismatch: operation=%0d cycle=%0d PE[%0d][%0d] k=%0d expected=%0d actual=%0d",
                                   active_operation_idx, cycle_value, i, j, k_value,
                                   a_matrix[i][k_value], dut.u_array.a_pe_in[i][j]);
                        end

                        if (dut.u_array.b_pe_in[i][j] !== b_matrix[k_value][j]) begin
                            $fatal(1,
                                   "B pairing mismatch: operation=%0d cycle=%0d PE[%0d][%0d] k=%0d expected=%0d actual=%0d",
                                   active_operation_idx, cycle_value, i, j, k_value,
                                   b_matrix[k_value][j], dut.u_array.b_pe_in[i][j]);
                        end
                    end else begin
                        if ((dut.u_array.a_valid_pe_in[i][j] !== 1'b0)
                            || (dut.u_array.b_valid_pe_in[i][j] !== 1'b0)) begin
                            $fatal(1,
                                   "Unexpected PE activity: operation=%0d cycle=%0d PE[%0d][%0d] k=%0d a_valid=%0b b_valid=%0b",
                                   active_operation_idx, cycle_value, i, j, k_value,
                                   dut.u_array.a_valid_pe_in[i][j],
                                   dut.u_array.b_valid_pe_in[i][j]);
                        end
                    end
                end
            end
        end
    endtask

    always @(posedge clk) begin
        if (rst_n && busy) begin
            check_cycle_pairing(int'($unsigned(dut.cycle_idx)));
        end
    end

    // Check the frozen system protocol without adding logic to the DUT.
    always @(posedge clk) begin
        #1;
        if (!rst_n) begin
            if ((busy !== 1'b0) || (done !== 1'b0)
                || (dut.cycle_idx !== '0) || (dut.acc_clear !== 1'b0)) begin
                $fatal(1, "Protocol reset mismatch");
            end
            for (int i = 0; i < N; i++) begin
                if ((dut.boundary_a[i] !== '0)
                    || (dut.boundary_a_valid[i] !== 1'b0)
                    || (dut.boundary_b[i] !== '0)
                    || (dut.boundary_b_valid[i] !== 1'b0)) begin
                    $fatal(1, "Boundary lane %0d did not reset", i);
                end
                for (int j = 0; j < N; j++) begin
                    if ((result[i][j] !== '0)
                        || (dut.u_array.a_pipe[i][j+1] !== '0)
                        || (dut.u_array.a_valid_pipe[i][j+1] !== 1'b0)
                        || (dut.u_array.b_pipe[i+1][j] !== '0)
                        || (dut.u_array.b_valid_pipe[i+1][j] !== 1'b0)) begin
                        $fatal(1, "PE[%0d][%0d] state did not reset", i, j);
                    end
                end
            end
            prev_valid <= 1'b0;
        end else begin
            if (dut.acc_clear !== (busy && (dut.cycle_idx == '0))) begin
                $fatal(1, "acc_clear protocol mismatch");
            end
            if (done && busy) begin
                $fatal(1, "done and busy must not be high together");
            end
            if (prev_valid && prev_done && done) begin
                $fatal(1, "done must be a single-cycle pulse");
            end
            if (prev_valid && prev_busy) begin
                if (int'($unsigned(prev_cycle_idx)) == LAST_CYCLE) begin
                    if (!done || busy || (dut.cycle_idx !== prev_cycle_idx)) begin
                        $fatal(1, "Final-cycle completion protocol mismatch");
                    end
                end else if (!busy || done
                             || (int'($unsigned(dut.cycle_idx))
                                 != (int'($unsigned(prev_cycle_idx)) + 1))) begin
                    $fatal(1, "RUN cycle progression mismatch");
                end
            end

            for (int i = 0; i < N; i++) begin
                if (!busy
                    && (dut.feeder_a_valid[i] || dut.feeder_b_valid[i])) begin
                    $fatal(1, "Raw feeder valid asserted while idle on lane %0d", i);
                end
                if (!busy
                    && (dut.boundary_a_valid[i] || dut.boundary_b_valid[i])) begin
                    $fatal(1, "Boundary valid asserted while idle on lane %0d", i);
                end
            end

            if (busy && (!prev_valid || !prev_busy)) begin
                for (int i = 0; i < N; i++) begin
                    for (int k = 0; k < K; k++) stable_a[i][k] <= a_matrix[i][k];
                end
                for (int k = 0; k < K; k++) begin
                    for (int j = 0; j < N; j++) stable_b[k][j] <= b_matrix[k][j];
                end
            end else if (busy) begin
                for (int i = 0; i < N; i++) begin
                    for (int k = 0; k < K; k++) begin
                        if (a_matrix[i][k] !== stable_a[i][k])
                            $fatal(1, "A changed during RUN at [%0d][%0d]", i, k);
                    end
                end
                for (int k = 0; k < K; k++) begin
                    for (int j = 0; j < N; j++) begin
                        if (b_matrix[k][j] !== stable_b[k][j])
                            $fatal(1, "B changed during RUN at [%0d][%0d]", k, j);
                    end
                end
            end

            prev_valid <= 1'b1;
            prev_busy <= busy;
            prev_done <= done;
            prev_cycle_idx <= dut.cycle_idx;
        end
    end

    // Count committed MAC operations at every PE without modifying the RTL.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    mac_count[i][j] <= 0;
                end
            end
        end else if (dut.acc_clear) begin
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    if (dut.u_array.a_valid_pe_in[i][j]
                        && dut.u_array.b_valid_pe_in[i][j]) begin
                        $fatal(1,
                               "RUN 0 MAC detected: operation=%0d PE[%0d][%0d]",
                               active_operation_idx, i, j);
                    end
                    mac_count[i][j] <= 0;
                end
            end
        end else begin
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    if (dut.u_array.a_valid_pe_in[i][j]
                        && dut.u_array.b_valid_pe_in[i][j]) begin
                        mac_count[i][j] <= mac_count[i][j] + 1;
                    end
                end
            end
        end
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

    task automatic generate_corner_matrices(input int unsigned corner_idx);
        begin
            for (int i = 0; i < N; i++) begin
                for (int k = 0; k < K; k++) begin
                    case (corner_idx)
                        0: a_matrix[i][k] = '0;
                        1: a_matrix[i][k] = (i == k) ? DATA_W'(1) : '0;
                        2: a_matrix[i][k] = ((i == 0) && (k == 0)) ? DATA_W'(7) : '0;
                        3: a_matrix[i][k] = DATA_W'(1);
                        4: a_matrix[i][k] = ((i + k) % 2 == 0) ? DATA_W'(1) : -DATA_W'(1);
                        5: a_matrix[i][k] = DATA_W'(127);
                        6: a_matrix[i][k] = -DATA_W'(128);
                        7: a_matrix[i][k] = ((i + k) % 2 == 0) ? DATA_W'(127) : -DATA_W'(128);
                        default: a_matrix[i][k] = (i == 0) ? '0 : DATA_W'(i + k + 1);
                    endcase
                end
            end
            for (int k = 0; k < K; k++) begin
                for (int j = 0; j < N; j++) begin
                    case (corner_idx)
                        0: b_matrix[k][j] = '0;
                        1: b_matrix[k][j] = DATA_W'(k * N + j + 1);
                        2: b_matrix[k][j] = ((k == 0) && (j == 0)) ? -DATA_W'(9) : '0;
                        3: b_matrix[k][j] = DATA_W'(1);
                        4: b_matrix[k][j] = ((k + j) % 2 == 0) ? -DATA_W'(1) : DATA_W'(1);
                        5: b_matrix[k][j] = DATA_W'(127);
                        6: b_matrix[k][j] = -DATA_W'(128);
                        7: b_matrix[k][j] = ((k + j) % 2 == 0) ? -DATA_W'(128) : DATA_W'(127);
                        default: b_matrix[k][j] = (j == (N - 1)) ? '0 : -DATA_W'(k + j + 1);
                    endcase
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
                    $display("  C[%0d][%0d]: expected=%0d actual=%0d mac_count=%0d",
                             i, j, expected[i][j], result[i][j], mac_count[i][j]);
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

    task automatic check_mac_counts(
        input int unsigned operation_idx
    );
        begin
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    if (mac_count[i][j] != K) begin
                        print_failure_context(operation_idx);
                        $fatal(1,
                               "PE[%0d][%0d] expected %0d MAC operations, observed %0d",
                               i, j, K, mac_count[i][j]);
                    end
                end
            end
        end
    endtask

    task automatic run_loaded_operation(
        input int unsigned operation_idx
    );
        int observed_run_cycles;
        begin
            active_operation_idx = operation_idx;
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

                if (observed_run_cycles > TOTAL_RUN_CYCLES) begin
                    print_failure_context(operation_idx);
                    $fatal(1, "Operation timed out after %0d RUN cycles",
                           observed_run_cycles);
                end

                if ((done !== 1'b1) && (busy !== 1'b1)) begin
                    print_failure_context(operation_idx);
                    $fatal(1, "busy deasserted before the final RUN cycle");
                end
            end

            if (observed_run_cycles != TOTAL_RUN_CYCLES) begin
                print_failure_context(operation_idx);
                $fatal(1, "Expected %0d RUN cycles, observed %0d",
                       TOTAL_RUN_CYCLES, observed_run_cycles);
            end
            if (busy !== 1'b0) begin
                print_failure_context(operation_idx);
                $fatal(1, "busy must be low when done is asserted");
            end

            check_all_results(operation_idx);
            check_mac_counts(operation_idx);
            completed_tests++;
        end
    endtask

    task automatic run_random_operation(input int unsigned operation_idx);
        begin
            generate_random_matrices();
            run_loaded_operation(operation_idx);
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
        active_operation_idx = 0;
        prev_valid       = 1'b0;
        prev_busy        = 1'b0;
        prev_done        = 1'b0;
        prev_cycle_idx   = '0;
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

        $display("Pipelined random regression: N=%0d K=%0d DATA_W=%0d ACC_W=%0d tests=%0d seed=0x%08x",
                 N, K, DATA_W, ACC_W, NUM_RANDOM_TESTS, SEED);
        $display("Structural monitor enabled: every PE must commit exactly K MAC operations.");
        $display("Pairing monitor enabled: every PE must receive the expected A[i][k] and B[k][j] each cycle.");
        $display("Protocol monitor enabled: controller, feeder, reset, and input-stability contracts are checked.");

        // Apply a synchronous reset before the first operation.
        @(posedge clk);
        #1;
        rst_n = 1'b1;

        for (int unsigned corner_idx = 0; corner_idx < NUM_CORNERS; corner_idx++) begin
            generate_corner_matrices(corner_idx);
            run_loaded_operation(corner_idx);
            wait_random_idle(corner_idx);
        end

        for (int unsigned operation_idx = 0;
             operation_idx < NUM_RANDOM_TESTS;
             operation_idx++) begin
            run_random_operation(NUM_CORNERS + operation_idx);
            wait_random_idle(NUM_CORNERS + operation_idx);
        end

        $display("All %0d corner/random pipelined systolic array operations passed for N=%0d K=%0d seed=0x%08x.",
                 completed_tests, N, K, SEED);
        $finish;
    end

endmodule


