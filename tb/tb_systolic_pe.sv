`timescale 1ns/1ps

// Self-checking directed test for signed PE arithmetic, extreme operands,
// clear/MAC priority, accumulator hold, and independent A/B forwarding.
// Stimulus changes on falling edges and checks registered state after rising
// edges. Any $fatal is a contract failure; the final message means all directed
// PE checks completed without a mismatch.
module tb_systolic_pe;

    localparam int DATA_W = 8;
    localparam int ACC_W  = 18;

    logic                     clk;
    logic                     rst_n;
    logic                     acc_clear;

    logic signed [DATA_W-1:0] a_in;
    logic                     a_valid_in;
    logic signed [DATA_W-1:0] b_in;
    logic                     b_valid_in;

    logic signed [DATA_W-1:0] a_out;
    logic                     a_valid_out;
    logic signed [DATA_W-1:0] b_out;
    logic                     b_valid_out;
    logic signed [ACC_W-1:0]  psum_out;

    int test_count;

    systolic_pe #(
        .DATA_W(DATA_W),
        .ACC_W (ACC_W)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .acc_clear  (acc_clear),
        .a_in       (a_in),
        .a_valid_in (a_valid_in),
        .b_in       (b_in),
        .b_valid_in (b_valid_in),
        .a_out      (a_out),
        .a_valid_out(a_valid_out),
        .b_out      (b_out),
        .b_valid_out(b_valid_out),
        .psum_out   (psum_out)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check_equal(
        input logic                    condition,
        input string                   signal_name,
        input string                   test_name
    );
        begin
            if (!condition) begin
                $fatal(1, "[%s] %s mismatch", test_name, signal_name);
            end
        end
    endtask

    task automatic drive_and_check(
        input logic signed [DATA_W-1:0] next_a,
        input logic                     next_a_valid,
        input logic signed [DATA_W-1:0] next_b,
        input logic                     next_b_valid,
        input logic                     next_acc_clear,
        input logic signed [ACC_W-1:0]  expected_psum,
        input string                    test_name
    );
        begin
            @(negedge clk);
            a_in       = next_a;
            a_valid_in = next_a_valid;
            b_in       = next_b;
            b_valid_in = next_b_valid;
            acc_clear  = next_acc_clear;

            @(posedge clk);
            #1;

            check_equal(a_out === next_a, "a_out", test_name);
            check_equal(a_valid_out === next_a_valid,
                        "a_valid_out", test_name);
            check_equal(b_out === next_b, "b_out", test_name);
            check_equal(b_valid_out === next_b_valid,
                        "b_valid_out", test_name);
            check_equal(psum_out === expected_psum,
                        "psum_out", test_name);

            test_count++;
            $display("PASS %0d: %s", test_count, test_name);
        end
    endtask

    task automatic apply_reset_and_check(
        input string test_name
    );
        begin
            @(negedge clk);
            rst_n       = 1'b0;
            acc_clear   = 1'b1;
            a_in        = -8'sd4;
            a_valid_in  = 1'b1;
            b_in        = 8'sd3;
            b_valid_in  = 1'b1;

            @(posedge clk);
            #1;

            check_equal(a_out === '0, "a_out", test_name);
            check_equal(a_valid_out === 1'b0,
                        "a_valid_out", test_name);
            check_equal(b_out === '0, "b_out", test_name);
            check_equal(b_valid_out === 1'b0,
                        "b_valid_out", test_name);
            check_equal(psum_out === '0, "psum_out", test_name);

            test_count++;
            $display("PASS %0d: %s", test_count, test_name);
        end
    endtask

    initial begin
        test_count  = 0;
        rst_n       = 1'b0;
        acc_clear   = 1'b0;
        a_in        = '0;
        a_valid_in  = 1'b0;
        b_in        = '0;
        b_valid_in  = 1'b0;

        // Reset has priority over forwarding, clear, and MAC.
        apply_reset_and_check("reset priority");

        rst_n       = 1'b1;
        acc_clear   = 1'b0;
        a_valid_in  = 1'b0;
        b_valid_in  = 1'b0;

        // Clear may accept a valid zero product as the first MAC.
        drive_and_check(
            8'sd0, 1'b1, 8'sd17, 1'b1, 1'b1,
            18'sd0, "zero product with clear"
        );

        // Exercise all signed multiplication combinations.
        drive_and_check(
            8'sd2, 1'b1, 8'sd3, 1'b1, 1'b1,
            18'sd6, "positive times positive"
        );
        drive_and_check(
            8'sd4, 1'b1, -8'sd5, 1'b1, 1'b0,
            -18'sd14, "positive times negative"
        );
        drive_and_check(
            -8'sd3, 1'b1, -8'sd7, 1'b1, 1'b0,
            18'sd7, "negative times negative"
        );

        // One-sided valid data must advance without changing the accumulator.
        drive_and_check(
            8'sd5, 1'b1, 8'sd99, 1'b0, 1'b0,
            18'sd7, "A-only valid forwarding"
        );
        drive_and_check(
            -8'sd42, 1'b0, 8'sd6, 1'b1, 1'b0,
            18'sd7, "B-only valid forwarding"
        );
        drive_and_check(
            8'sd77, 1'b0, -8'sd88, 1'b0, 1'b0,
            18'sd7, "both inputs invalid hold"
        );

        // Clear without a valid pair discards the old partial sum.
        drive_and_check(
            8'sd12, 1'b1, 8'sd34, 1'b0, 1'b1,
            18'sd0, "clear without valid MAC"
        );

        // Clear and MAC in the same cycle start from the current product.
        drive_and_check(
            -8'sd4, 1'b1, 8'sd3, 1'b1, 1'b1,
            -18'sd12, "clear with first MAC"
        );

        // Consecutive valid cycles must accumulate without bubbles.
        drive_and_check(
            8'sd2, 1'b1, 8'sd3, 1'b1, 1'b0,
            -18'sd6, "continuous MAC cycle 1"
        );
        drive_and_check(
            -8'sd2, 1'b1, 8'sd5, 1'b1, 1'b0,
            -18'sd16, "continuous MAC cycle 2"
        );

        // Four maximum positive products must fit in the 18-bit accumulator.
        drive_and_check(
            8'sh80, 1'b1, 8'sh80, 1'b1, 1'b1,
            18'sd16384, "maximum product 1"
        );
        drive_and_check(
            8'sh80, 1'b1, 8'sh80, 1'b1, 1'b0,
            18'sd32768, "maximum product 2"
        );
        drive_and_check(
            8'sh80, 1'b1, 8'sh80, 1'b1, 1'b0,
            18'sd49152, "maximum product 3"
        );
        drive_and_check(
            8'sh80, 1'b1, 8'sh80, 1'b1, 1'b0,
            18'sd65536, "maximum product 4"
        );

        // Reasserting reset must discard all accumulated and forwarded state.
        apply_reset_and_check("reset after active operation");

        $display("All %0d systolic_pe tests passed.", test_count);
        $finish;
    end

endmodule
