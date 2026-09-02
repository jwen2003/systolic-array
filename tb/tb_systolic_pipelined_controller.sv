`timescale 1ns/1ps

module tb_systolic_pipelined_controller;

    localparam int N_BASE       = 2;
    localparam int K_BASE       = 2;
    localparam int CYCLE_W_BASE = 3;

    localparam int N_UNIT       = 1;
    localparam int K_UNIT       = 1;
    localparam int CYCLE_W_UNIT = 1;

    logic                    clk;
    logic                    rst_n;

    logic                    start_base;
    logic                    busy_base;
    logic                    done_base;
    logic                    acc_clear_base;
    logic [CYCLE_W_BASE-1:0] cycle_idx_base;

    logic                    start_unit;
    logic                    busy_unit;
    logic                    done_unit;
    logic                    acc_clear_unit;
    logic [CYCLE_W_UNIT-1:0] cycle_idx_unit;

    int test_count;

    systolic_pipelined_controller #(
        .N      (N_BASE),
        .K      (K_BASE),
        .CYCLE_W(CYCLE_W_BASE)
    ) dut_base (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start_base),
        .busy     (busy_base),
        .done     (done_base),
        .acc_clear(acc_clear_base),
        .cycle_idx(cycle_idx_base)
    );

    systolic_pipelined_controller #(
        .N      (N_UNIT),
        .K      (K_UNIT),
        .CYCLE_W(CYCLE_W_UNIT)
    ) dut_unit (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start_unit),
        .busy     (busy_unit),
        .done     (done_unit),
        .acc_clear(acc_clear_unit),
        .cycle_idx(cycle_idx_unit)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check_base(
        input logic                    expected_busy,
        input logic                    expected_done,
        input logic                    expected_acc_clear,
        input logic [CYCLE_W_BASE-1:0] expected_cycle_idx,
        input string                   test_name
    );
        begin
            if ((busy_base !== expected_busy)
                || (done_base !== expected_done)
                || (acc_clear_base !== expected_acc_clear)
                || (cycle_idx_base !== expected_cycle_idx)) begin
                $fatal(1,
                       "[%s] expected busy=%0b done=%0b clear=%0b cycle=%0d, got busy=%0b done=%0b clear=%0b cycle=%0d",
                       test_name,
                       expected_busy, expected_done,
                       expected_acc_clear, expected_cycle_idx,
                       busy_base, done_base,
                       acc_clear_base, cycle_idx_base);
            end

            test_count++;
            $display("PASS %0d: %s", test_count, test_name);
        end
    endtask

    task automatic check_unit(
        input logic                    expected_busy,
        input logic                    expected_done,
        input logic                    expected_acc_clear,
        input logic [CYCLE_W_UNIT-1:0] expected_cycle_idx,
        input string                   test_name
    );
        begin
            if ((busy_unit !== expected_busy)
                || (done_unit !== expected_done)
                || (acc_clear_unit !== expected_acc_clear)
                || (cycle_idx_unit !== expected_cycle_idx)) begin
                $fatal(1,
                       "[%s] expected busy=%0b done=%0b clear=%0b cycle=%0d, got busy=%0b done=%0b clear=%0b cycle=%0d",
                       test_name,
                       expected_busy, expected_done,
                       expected_acc_clear, expected_cycle_idx,
                       busy_unit, done_unit,
                       acc_clear_unit, cycle_idx_unit);
            end

            test_count++;
            $display("PASS %0d: %s", test_count, test_name);
        end
    endtask

    initial begin
        test_count = 0;
        rst_n      = 1'b0;
        start_base = 1'b1;
        start_unit = 1'b1;

        // Synchronous reset overrides start for both configurations.
        @(posedge clk);
        #1;
        check_base(1'b0, 1'b0, 1'b0, 3'd0, "base reset priority");
        check_unit(1'b0, 1'b0, 1'b0, 1'd0, "unit reset priority");

        @(negedge clk);
        rst_n      = 1'b1;
        start_base = 1'b0;
        start_unit = 1'b0;

        // Idle holds the reset count without producing control pulses.
        @(posedge clk);
        #1;
        check_base(1'b0, 1'b0, 1'b0, 3'd0, "base idle hold");
        check_unit(1'b0, 1'b0, 1'b0, 1'd0, "unit idle hold");

        @(negedge clk);
        start_base = 1'b1;
        start_unit = 1'b1;

        // Both configurations accept start and expose RUN cycle zero.
        @(posedge clk);
        #1;
        check_base(1'b1, 1'b0, 1'b1, 3'd0, "base start acceptance");
        check_unit(1'b1, 1'b0, 1'b1, 1'd0, "unit start acceptance");

        @(negedge clk);
        start_unit = 1'b0;

        // Holding base start high must not restart an active operation.
        @(posedge clk);
        #1;
        check_base(1'b1, 1'b0, 1'b0, 3'd1, "base busy start ignored at cycle 1");
        check_unit(1'b1, 1'b0, 1'b0, 1'd1, "unit final cycle remains active");

        @(posedge clk);
        #1;
        check_base(1'b1, 1'b0, 1'b0, 3'd2, "base busy start ignored at cycle 2");
        check_unit(1'b0, 1'b1, 1'b0, 1'd1, "unit completion pulse");

        @(negedge clk);
        start_base = 1'b0;

        @(posedge clk);
        #1;
        check_base(1'b1, 1'b0, 1'b0, 3'd3, "base cycle 3 active");
        check_unit(1'b0, 1'b0, 1'b0, 1'd1, "unit done pulse clears");

        // Reaching cycle four must not complete until its ending edge.
        @(posedge clk);
        #1;
        check_base(1'b1, 1'b0, 1'b0, 3'd4, "base final cycle active");

        @(posedge clk);
        #1;
        check_base(1'b0, 1'b1, 1'b0, 3'd4, "base completion pulse");

        @(posedge clk);
        #1;
        check_base(1'b0, 1'b0, 1'b0, 3'd4, "base post-completion idle");

        // A completed controller accepts another one-cycle request.
        @(negedge clk);
        start_base = 1'b1;
        start_unit = 1'b1;

        @(posedge clk);
        #1;
        check_base(1'b1, 1'b0, 1'b1, 3'd0, "base second start acceptance");
        check_unit(1'b1, 1'b0, 1'b1, 1'd0, "unit second start acceptance");

        @(negedge clk);
        start_base = 1'b0;
        start_unit = 1'b0;

        $display("All %0d systolic_pipelined_controller tests passed.", test_count);
        $finish;
    end

endmodule
