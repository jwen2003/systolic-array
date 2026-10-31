`timescale 1ns/1ps

// Unit test: exercise the device-side bus, not AXI handshakes or V1 arithmetic.
// The core is represented by controlled busy/done/result inputs.
// N != K deliberately exposes row-major stride mistakes.
module tb_systolic_device;
    localparam int unsigned N = 2;
    localparam int unsigned K = 3;
    localparam logic [31:0] COMMAND = 32'h0004;
    localparam logic [31:0] STATUS = 32'h0008;
    localparam logic [31:0] ACK = 32'h000c;
    localparam logic [31:0] ERRORS = 32'h0010;
    localparam logic [31:0] A = 32'h1000;
    localparam logic [31:0] B = 32'h2000;
    localparam logic [31:0] C = 32'h3000;

    logic clk = 0;
    logic rst_n = 0;
    logic wr_en = 0, rd_en = 0;
    logic [31:0] wr_addr = 0, wr_data = 0, rd_addr = 0;
    logic [3:0] wr_strb = 0;
    logic wr_error, rd_error;
    logic [31:0] rd_data;
    logic core_start, core_busy = 0, core_done = 0;
    logic signed [7:0] a_matrix [N-1:0][K-1:0];
    logic signed [7:0] b_matrix [K-1:0][N-1:0];
    logic signed [17:0] core_result [N-1:0][N-1:0];
    int unsigned checks = 0;
    int unsigned starts;
    logic last_start;

    systolic_device #(.N(N), .K(K)) dut (.*);

    // Use procedural delays to avoid driving on the DUT's sampling edge.
    initial forever #5 clk = ~clk;

    task automatic check(input bit condition, input string description);
        checks++;
        if (!condition) $fatal(1, "check %0d: %s", checks, description);
    endtask

    // Each call is exactly one device request attempt at one rising edge.
    // Read data is checked BEFORE that edge, matching the slave's sampling.
    task automatic access_bus(
        input bit we, input logic [31:0] wa, wd, input logic [3:0] ws,
        input bit re, input logic [31:0] ra,
        input bit expected_we, expected_re,
        input logic [31:0] expected_data
    );
        @(negedge clk);
        wr_en = we; wr_addr = wa; wr_data = wd; wr_strb = ws;
        rd_en = re; rd_addr = ra;
        #1;
        if (we) check(wr_error === expected_we, $sformatf("write response @%h", wa));
        if (re) begin
            check(rd_error === expected_re, $sformatf("read response @%h", ra));
            check(rd_data === expected_data, $sformatf("read @%h: got %h expected %h",
                                                      ra, rd_data, expected_data));
        end
        @(posedge clk);
        #1;
        @(negedge clk);
        wr_en = 0; rd_en = 0;
    endtask

    task automatic write_word(input logic [31:0] addr, data,
                              input logic [3:0] strb = 4'hf,
                              input bit error_expected = 0);
        access_bus(1, addr, data, strb, 0, 0, error_expected, 0, 0);
    endtask

    task automatic read_word(input logic [31:0] addr, expected,
                             input bit error_expected = 0);
        access_bus(0, 0, 0, 0, 1, addr, 0, error_expected, expected);
    endtask

    task automatic idle_cycles(input int unsigned count);
        repeat (count) begin @(posedge clk); #1; end
    endtask

    task automatic reset_device;
        @(negedge clk);
        rst_n = 0; wr_en = 0; rd_en = 0; core_busy = 0; core_done = 0;
        idle_cycles(2);
        @(negedge clk); rst_n = 1;
        idle_cycles(1);
        check(core_start === 0, "reset clears core_start");
        read_word(STATUS, 0);
        read_word(ERRORS, 0);
    endtask

    task automatic load_inputs(input int signed bias);
        for (int unsigned x = 0; x < N*K; x++) begin
            write_word(A + 4*x, 32'(int'(x) + bias));
            write_word(B + 4*x, 32'(-int'(x) - bias));
        end
        for (int unsigned x = 0; x < N*K; x++) begin
            check(a_matrix[x/K][x%K] === 8'(int'(x)+bias), "A row-major core port");
            check(b_matrix[x/N][x%N] === 8'(-int'(x)-bias), "B row-major core port");
            read_word(A + 4*x, 32'(int'(x)+bias));
            read_word(B + 4*x, 32'(-int'(x)-bias));
        end
    endtask

    task automatic finish_core;
        @(negedge clk); core_busy = 0; core_done = 1;
        @(posedge clk); #1;
        @(negedge clk); core_done = 0;
    endtask

    // Observe exactly the pulse a synchronous V1 core would sample.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            starts <= 0;
            last_start <= 0;
        end else begin
            if (core_start) starts <= starts + 1;
            assert (!(core_start && last_start))
                else $fatal(1, "core_start lasted more than one cycle");
            last_start <= core_start;
        end
    end

    initial begin
        // Signed extremes and distinct values verify C indexing/sign extension.
        core_result[0][0] = -18'sd131072;
        core_result[0][1] = 18'sd131071;
        core_result[1][0] = -18'sd7;
        core_result[1][1] = 18'sd42;
        reset_device();
        read_word(32'h0000, 32'h0000_0200);
        read_word(32'h0020, N); read_word(32'h0024, K);
        read_word(32'h0028, 8); read_word(32'h002c, 18);
        read_word(A, 0); read_word(B, 0);

        // Repeated writes cannot substitute for loading distinct elements.
        repeat (4) write_word(A, 32'h80);
        read_word(A, 32'hffff_ff80);
        read_word(STATUS, 0);
        write_word(COMMAND, 1, 4'hf, 1);
        read_word(ERRORS, 32'h02);
        check(starts == 0, "incomplete start never reaches core");
        write_word(ERRORS, 32'hff, 4'h0);
        read_word(ERRORS, 32'h02);
        write_word(ERRORS, 32'hff, 4'h2);
        read_word(ERRORS, 32'h02);
        write_word(ERRORS, 32'h02, 4'h1);
        read_word(ERRORS, 0);

        // Highest valid word, first invalid word, alignment and permissions.
        write_word(A + 4*N*K, 1, 4'hf, 1);
        read_word(B + 4*N*K, 0, 1);
        read_word(C + 4*N*N, 0, 1);
        write_word(A+1, 1, 4'hf, 1);
        read_word(C+1, 0, 1);
        write_word(STATUS, 1, 4'hf, 1);
        write_word(C, 1, 4'hf, 1);
        read_word(COMMAND, 0, 1); read_word(ACK, 0, 1);
        read_word(C, 0, 1);
        read_word(ERRORS, 32'h74);
        write_word(ERRORS, 32'hffff_ffff);
        read_word(ERRORS, 0);

        // An illegal address on idle pins must not create an error.
        @(negedge clk); wr_addr = 32'hffff_ffff; rd_addr = 32'hffff_ffff;
        idle_cycles(3);
        read_word(ERRORS, 0);
        write_word(ACK, 1); read_word(STATUS, 0);
        write_word(COMMAND, 0); write_word(COMMAND, 1, 4'h0);
        check(starts == 0, "masked/no-op command does not start");

        load_inputs(1);
        read_word(STATUS, 4);
        // WSTRB upper bytes cannot change the low INT8 byte.
        write_word(A, 32'hffff_ffff, 4'he);
        read_word(A, 1);
        write_word(A, 32'hffff_ff80, 4'h1);
        read_word(A, 32'hffff_ff80);

        // Unexpected core_busy also prevents start while device is LOAD.
        @(negedge clk); core_busy = 1;
        write_word(COMMAND, 1, 4'hf, 1);
        read_word(ERRORS, 1);
        @(negedge clk); core_busy = 0;
        // Historical error does not block a legal command.
        write_word(COMMAND, 1);
        check(core_start === 1, "accepted START produces registered pulse");
        read_word(STATUS, 13); // RUN + INPUTS_READY + sticky ERROR
        check(starts == 1, "exactly one core start");
        check(core_start === 0, "start pulse cleared");
        // Device remains RUN even before the core asserts busy.
        idle_cycles(3); read_word(STATUS, 13);
        @(negedge clk); core_busy = 1;
        write_word(COMMAND, 1, 4'hf, 1);
        write_word(A, 99, 4'hf, 1);
        write_word(B, 99, 4'hf, 1);
        check(a_matrix[0][0] === -8'sd128, "RUN rejects A overwrite");
        check(b_matrix[0][0] === -8'sd1, "RUN rejects B overwrite");
        read_word(A, 0, 1); read_word(B, 0, 1);
        read_word(C, 0, 1);
        write_word(ACK, 1); read_word(STATUS, 13);
        read_word(ERRORS, 32'h99);

        // Different errors on read/write channels must both survive one edge.
        write_word(ERRORS, 32'hff);
        access_bus(1, A, 2, 4'hf, 1, C, 1, 1, 0);
        read_word(ERRORS, 32'h18);
        // Same bit cleared and re-raised: the new error wins.
        access_bus(1, ERRORS, 32'hff, 4'h1, 1, C, 0, 1, 0);
        read_word(ERRORS, 32'h10);
        write_word(ERRORS, 32'hff);
        read_word(STATUS, 5);

        finish_core();
        read_word(STATUS, 6);
        idle_cycles(12); read_word(STATUS, 6);
        read_word(C, 32'hfffe_0000);
        read_word(C+4, 32'h0001_ffff);
        read_word(C+8, 32'hffff_fff9);
        read_word(C+12, 42);
        write_word(COMMAND, 1, 4'hf, 1);
        write_word(A, 7, 4'hf, 1);
        read_word(A, 0, 1);
        write_word(ERRORS, 32'hff);
        read_word(STATUS, 6); // clearing errors does not release DONE
        read_word(C+12, 42);
        write_word(ACK, 1, 4'h0); read_word(STATUS, 6);
        // A read accepted with ACK still sees the old DONE snapshot.
        access_bus(1, ACK, 1, 4'h1, 1, C+12, 0, 0, 42);
        read_word(STATUS, 0);
        read_word(A, 0); read_word(B, 0);
        read_word(C, 0, 1);
        write_word(COMMAND, 1, 4'hf, 1);
        read_word(ERRORS, 32'h12);

        // Second operation requires new inputs, can run with historical errors.
        load_inputs(10);
        write_word(COMMAND, 1);
        @(negedge clk); core_busy = 1;
        idle_cycles(3);
        check(starts == 2, "second operation starts once");
        core_result[1][1] = -18'sd23;
        finish_core();
        read_word(C+12, 32'hffff_ffe9);
        write_word(ACK, 1);
        read_word(ERRORS, 32'h12); // ACK does not clear sticky errors

        // Reset recovery from RUN and DONE; payload reset is not assumed.
        load_inputs(20); write_word(COMMAND, 1);
        reset_device();
        read_word(A, 0); read_word(B, 0);
        write_word(COMMAND, 1, 4'hf, 1);
        check(starts == 0, "reset invalidates written maps");
        write_word(ERRORS, 32'hff);
        load_inputs(30); write_word(COMMAND, 1);
        finish_core(); read_word(STATUS, 6);
        reset_device(); read_word(C, 0, 1);
        $display("PASS tb_systolic_device: %0d checks", checks);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "watchdog timeout");
    end
endmodule
