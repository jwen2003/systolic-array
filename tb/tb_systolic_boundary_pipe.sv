module tb_systolic_boundary_pipe;

    timeunit 1ns;
    timeprecision 1ps;

    localparam int N      = 2;
    localparam int DATA_W = 8;

    logic                         clk;
    logic                         rst_n;
    logic                         clear;
    logic signed [DATA_W-1:0]     a_in        [N-1:0];
    logic                         a_valid_in  [N-1:0];
    logic signed [DATA_W-1:0]     b_in        [N-1:0];
    logic                         b_valid_in  [N-1:0];
    logic signed [DATA_W-1:0]     a_out       [N-1:0];
    logic                         a_valid_out [N-1:0];
    logic signed [DATA_W-1:0]     b_out       [N-1:0];
    logic                         b_valid_out [N-1:0];

    int test_count;

    systolic_boundary_pipe #(
        .N      (N),
        .DATA_W (DATA_W)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .clear       (clear),
        .a_in        (a_in),
        .a_valid_in  (a_valid_in),
        .b_in        (b_in),
        .b_valid_in  (b_valid_in),
        .a_out       (a_out),
        .a_valid_out (a_valid_out),
        .b_out       (b_out),
        .b_valid_out (b_valid_out)
    );

    always #5 clk <= ~clk;

    task automatic drive_inputs(
        input logic signed [DATA_W-1:0] a0,
        input logic                     av0,
        input logic signed [DATA_W-1:0] a1,
        input logic                     av1,
        input logic signed [DATA_W-1:0] b0,
        input logic                     bv0,
        input logic signed [DATA_W-1:0] b1,
        input logic                     bv1
    );
        @(negedge clk);
        a_in[0]       = a0;
        a_valid_in[0] = av0;
        a_in[1]       = a1;
        a_valid_in[1] = av1;
        b_in[0]       = b0;
        b_valid_in[0] = bv0;
        b_in[1]       = b1;
        b_valid_in[1] = bv1;
    endtask

    task automatic check_outputs(
        input logic signed [DATA_W-1:0] a0,
        input logic                     av0,
        input logic signed [DATA_W-1:0] a1,
        input logic                     av1,
        input logic signed [DATA_W-1:0] b0,
        input logic                     bv0,
        input logic signed [DATA_W-1:0] b1,
        input logic                     bv1,
        input string                    label
    );
        #1;
        if (a_out[0] !== a0 || a_valid_out[0] !== av0
                || a_out[1] !== a1 || a_valid_out[1] !== av1
                || b_out[0] !== b0 || b_valid_out[0] !== bv0
                || b_out[1] !== b1 || b_valid_out[1] !== bv1) begin
            $error("FAIL %s: A0=%0d/%0b A1=%0d/%0b B0=%0d/%0b B1=%0d/%0b",
                   label, a_out[0], a_valid_out[0], a_out[1], a_valid_out[1],
                   b_out[0], b_valid_out[0], b_out[1], b_valid_out[1]);
            $fatal(1);
        end
        test_count++;
        $display("PASS %0d: %s", test_count, label);
    endtask

    task automatic sample_and_check(
        input logic signed [DATA_W-1:0] a0,
        input logic                     av0,
        input logic signed [DATA_W-1:0] a1,
        input logic                     av1,
        input logic signed [DATA_W-1:0] b0,
        input logic                     bv0,
        input logic signed [DATA_W-1:0] b1,
        input logic                     bv1,
        input string                    label
    );
        @(posedge clk);
        check_outputs(a0, av0, a1, av1, b0, bv0, b1, bv1, label);
    endtask

    initial begin
        clk        = 1'b0;
        rst_n      = 1'b1;
        clear      = 1'b0;
        test_count = 0;
        for (int lane = 0; lane < N; lane++) begin
            a_in[lane]       = '0;
            a_valid_in[lane] = 1'b0;
            b_in[lane]       = '0;
            b_valid_in[lane] = 1'b0;
        end

        // Reset is sampled synchronously at the rising edge.
        @(negedge clk);
        rst_n = 1'b0;
        a_in[0] = 8'sd12;
        a_valid_in[0] = 1'b1;
        b_in[1] = -8'sd9;
        b_valid_in[1] = 1'b1;
        sample_and_check('0, 1'b0, '0, 1'b0, '0, 1'b0, '0, 1'b0,
                         "synchronous reset clears every lane");

        // Reset has priority over clear.
        @(negedge clk);
        clear = 1'b1;
        a_in[1] = 8'sd33;
        a_valid_in[1] = 1'b1;
        sample_and_check('0, 1'b0, '0, 1'b0, '0, 1'b0, '0, 1'b0,
                         "reset priority over clear");

        @(negedge clk);
        rst_n = 1'b1;
        clear = 1'b0;

        // Observe the old output before the next rising-edge sample.
        a_in[0] = 8'sd7;
        a_valid_in[0] = 1'b1;
        a_in[1] = -8'sd8;
        a_valid_in[1] = 1'b1;
        b_in[0] = 8'sh80;
        b_valid_in[0] = 1'b1;
        b_in[1] = 8'sh7f;
        b_valid_in[1] = 1'b1;
        check_outputs('0, 1'b0, '0, 1'b0, '0, 1'b0, '0, 1'b0,
                      "outputs remain old before sample");
        sample_and_check(8'sd7, 1'b1, -8'sd8, 1'b1, -8'sd128, 1'b1, 8'sd127, 1'b1,
                         "all lanes valid with signed extrema");

        drive_inputs(-8'sd3, 1'b1, 8'sd44, 1'b1,
                     8'sd55, 1'b0, -8'sd66, 1'b0);
        sample_and_check(-8'sd3, 1'b1, 8'sd44, 1'b1,
                         8'sd55, 1'b0, -8'sd66, 1'b0,
                         "A-only valid forwarding");

        drive_inputs(8'sd21, 1'b0, -8'sd22, 1'b0,
                     -8'sd23, 1'b1, 8'sd24, 1'b1);
        sample_and_check(8'sd21, 1'b0, -8'sd22, 1'b0,
                         -8'sd23, 1'b1, 8'sd24, 1'b1,
                         "B-only valid forwarding");

        drive_inputs(8'sd31, 1'b1, -8'sd32, 1'b0,
                     8'sd33, 1'b0, -8'sd34, 1'b1);
        sample_and_check(8'sd31, 1'b1, -8'sd32, 1'b0,
                         8'sd33, 1'b0, -8'sd34, 1'b1,
                         "lane-independent valid forwarding");

        // Consecutive samples exercise bubble-free operation.
        drive_inputs(8'sd41, 1'b1, 8'sd42, 1'b1,
                     -8'sd43, 1'b1, -8'sd44, 1'b1);
        sample_and_check(8'sd41, 1'b1, 8'sd42, 1'b1,
                         -8'sd43, 1'b1, -8'sd44, 1'b1,
                         "continuous capture cycle 1");
        drive_inputs(-8'sd51, 1'b1, -8'sd52, 1'b1,
                     8'sd53, 1'b1, 8'sd54, 1'b1);
        sample_and_check(-8'sd51, 1'b1, -8'sd52, 1'b1,
                         8'sd53, 1'b1, 8'sd54, 1'b1,
                         "continuous capture cycle 2");

        // Clear discards valid input at its sampling edge.
        @(negedge clk);
        clear = 1'b1;
        a_in[0] = 8'sd61;
        a_valid_in[0] = 1'b1;
        a_in[1] = 8'sd62;
        a_valid_in[1] = 1'b1;
        b_in[0] = 8'sd63;
        b_valid_in[0] = 1'b1;
        b_in[1] = 8'sd64;
        b_valid_in[1] = 1'b1;
        sample_and_check('0, 1'b0, '0, 1'b0, '0, 1'b0, '0, 1'b0,
                         "clear discards current input");

        // Deasserting clear restores normal one-cycle capture.
        drive_inputs(-8'sd71, 1'b1, 8'sd72, 1'b0,
                     8'sd73, 1'b0, -8'sd74, 1'b1);
        clear = 1'b0;
        sample_and_check(-8'sd71, 1'b1, 8'sd72, 1'b0,
                         8'sd73, 1'b0, -8'sd74, 1'b1,
                         "capture resumes after clear");

        $display("All %0d systolic_boundary_pipe directed checks passed.", test_count);
        $finish;
    end

endmodule
