`timescale 1ns/1ps

// Self-checking bare-array test using a manually skewed N2/K2 wavefront. It
// checks spatial A/B propagation and the expected psum after each rising edge,
// including drain, hold, and broadcast clear. Any $fatal is a cycle-level
// topology failure; the final message means the full directed wavefront passed.
module tb_systolic_array;

    localparam int N      = 2;
    localparam int DATA_W = 8;
    localparam int ACC_W  = 18;

    logic                             clk;
    logic                             rst_n;
    logic                             acc_clear;

    logic signed [DATA_W-1:0]         a_left       [N-1:0];
    logic                             a_valid_left [N-1:0];
    logic signed [DATA_W-1:0]         b_top        [N-1:0];
    logic                             b_valid_top  [N-1:0];

    logic signed [ACC_W-1:0]          psum         [N-1:0][N-1:0];

    systolic_array #(
        .N     (N),
        .DATA_W(DATA_W),
        .ACC_W (ACC_W)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .acc_clear   (acc_clear),
        .a_left      (a_left),
        .a_valid_left(a_valid_left),
        .b_top       (b_top),
        .b_valid_top (b_valid_top),
        .psum        (psum)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check_psum(
        input logic signed [ACC_W-1:0] expected_00,
        input logic signed [ACC_W-1:0] expected_01,
        input logic signed [ACC_W-1:0] expected_10,
        input logic signed [ACC_W-1:0] expected_11,
        input string                   test_name
    );
        begin
            if (psum[0][0] !== expected_00) begin
                $fatal(1,
                       "[%s] psum[0][0]: expected %0d, got %0d",
                       test_name, expected_00, psum[0][0]);
            end
            if (psum[0][1] !== expected_01) begin
                $fatal(1,
                       "[%s] psum[0][1]: expected %0d, got %0d",
                       test_name, expected_01, psum[0][1]);
            end
            if (psum[1][0] !== expected_10) begin
                $fatal(1,
                       "[%s] psum[1][0]: expected %0d, got %0d",
                       test_name, expected_10, psum[1][0]);
            end
            if (psum[1][1] !== expected_11) begin
                $fatal(1,
                       "[%s] psum[1][1]: expected %0d, got %0d",
                       test_name, expected_11, psum[1][1]);
            end

            $display(
                "PASS: %s, psum = [[%0d, %0d], [%0d, %0d]]",
                test_name,
                psum[0][0], psum[0][1],
                psum[1][0], psum[1][1]
            );
        end
    endtask

    task automatic drive_cycle(
        input logic signed [DATA_W-1:0] next_a_row0,
        input logic                     next_a_valid_row0,
        input logic signed [DATA_W-1:0] next_a_row1,
        input logic                     next_a_valid_row1,
        input logic signed [DATA_W-1:0] next_b_col0,
        input logic                     next_b_valid_col0,
        input logic signed [DATA_W-1:0] next_b_col1,
        input logic                     next_b_valid_col1,
        input logic                     next_acc_clear
    );
        begin
            @(negedge clk);

            a_left[0]       = next_a_row0;
            a_valid_left[0] = next_a_valid_row0;
            a_left[1]       = next_a_row1;
            a_valid_left[1] = next_a_valid_row1;

            b_top[0]        = next_b_col0;
            b_valid_top[0]  = next_b_valid_col0;
            b_top[1]        = next_b_col1;
            b_valid_top[1]  = next_b_valid_col1;

            acc_clear       = next_acc_clear;

            @(posedge clk);
            #1;
        end
    endtask

    task automatic drive_idle_cycle(
        input logic next_acc_clear
    );
        begin
            drive_cycle(
                '0, 1'b0,
                '0, 1'b0,
                '0, 1'b0,
                '0, 1'b0,
                next_acc_clear
            );
        end
    endtask

    initial begin
        rst_n       = 1'b0;
        acc_clear   = 1'b0;

        a_left[0]       = '0;
        a_valid_left[0] = 1'b0;
        a_left[1]       = '0;
        a_valid_left[1] = 1'b0;
        b_top[0]        = '0;
        b_valid_top[0]  = 1'b0;
        b_top[1]        = '0;
        b_valid_top[1]  = 1'b0;

        // Apply one synchronous reset edge to every PE.
        @(posedge clk);
        #1;
        check_psum(18'sd0, 18'sd0, 18'sd0, 18'sd0,
                   "synchronous reset");

        rst_n = 1'b1;

        // Compute A * B with manually skewed boundary inputs.
        // A = [[2, -3], [4, 5]]
        // B = [[-1, 6], [7, -2]]
        // C = [[-23, 18], [31, 14]]

        // Cycle 0: only PE00 receives a valid operand pair.
        drive_cycle(
            8'sd2,  1'b1,
            '0,     1'b0,
            -8'sd1, 1'b1,
            '0,     1'b0,
            1'b1
        );
        check_psum(-18'sd2, 18'sd0, 18'sd0, 18'sd0,
                   "first wavefront element");

        // Cycle 1: PE00, PE01, and PE10 execute MACs.
        drive_cycle(
            -8'sd3, 1'b1,
            8'sd4,  1'b1,
            8'sd7,  1'b1,
            8'sd6,  1'b1,
            1'b0
        );
        check_psum(-18'sd23, 18'sd12, -18'sd4, 18'sd0,
                   "wavefront reaches off-diagonal PEs");

        // Cycle 2: PE01 and PE10 finish while PE11 starts.
        drive_cycle(
            '0,     1'b0,
            8'sd5,  1'b1,
            '0,     1'b0,
            -8'sd2, 1'b1,
            1'b0
        );
        check_psum(-18'sd23, 18'sd18, 18'sd31, 18'sd24,
                   "wavefront reaches PE11");

        // Cycle 3: no new boundary data is injected; PE11 drains the array.
        drive_idle_cycle(1'b0);
        check_psum(-18'sd23, 18'sd18, 18'sd31, 18'sd14,
                   "final drain cycle");

        // An additional idle cycle must not change any result.
        drive_idle_cycle(1'b0);
        check_psum(-18'sd23, 18'sd18, 18'sd31, 18'sd14,
                   "post-completion hold");

        // A broadcast clear with no valid data must clear every accumulator.
        drive_idle_cycle(1'b1);
        check_psum(18'sd0, 18'sd0, 18'sd0, 18'sd0,
                   "broadcast accumulator clear");

        $display("All systolic_array tests passed.");
        $finish;
    end

endmodule
