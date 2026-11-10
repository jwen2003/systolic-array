`timescale 1ns/1ps

// Unit test for the constant-address packed Device decoder at N=2, K=17.
// The mock core is idle; this test inspects storage and written maps directly.
module tb_systolic_device_packed_decode;
    localparam int unsigned N = 2;
    localparam int unsigned K = 17;
    localparam int unsigned WORDS = N*K;
    localparam logic [31:0] A = 32'h1000;
    localparam logic [31:0] PA = 32'h4000;
    localparam logic [31:0] PB = 32'h5000;

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

    systolic_device #(.N(N), .K(K), .PACKED_ENABLE(1'b1)) dut (.*);

    initial forever #5 clk = ~clk;

    task automatic check(input bit condition, input string description);
        checks++;
        if (!condition) $fatal(1, "check %0d: %s", checks, description);
    endtask

    task automatic reset_device;
        @(negedge clk);
        rst_n = 0;
        wr_en = 0;
        rd_en = 0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
        @(posedge clk);
        #1;
        check(core_start === 0 && rd_error === 0 && rd_data === 32'h0000_0200,
              "reset leaves idle core and valid VERSION read view");
    endtask

    task automatic write_word(
        input logic [31:0] addr,
        input logic [31:0] data,
        input logic [3:0] strb,
        input bit expected_error = 0
    );
        @(negedge clk);
        wr_en = 1;
        wr_addr = addr;
        wr_data = data;
        wr_strb = strb;
        #1;
        check(wr_error === expected_error, $sformatf("write response @%h", addr));
        @(posedge clk);
        #1;
        @(negedge clk);
        wr_en = 0;
        wr_strb = 0;
    endtask

    initial begin
        for (int unsigned row = 0; row < N; row++)
            for (int unsigned col = 0; col < N; col++)
                core_result[row][col] = '0;

        reset_device();

        // Seed the cross-row packed word through legacy addresses, then reset
        // only the validity maps. Word 4 contains A[0][16], A[1][0..2].
        for (int unsigned p = 16; p < 20; p++)
            write_word(A + 4*p, 32'h40 + p, 4'h1);
        reset_device();
        write_word(PA + 4*4, 32'hd4_c3_b2_a1, 4'b0010);
        check(a_matrix[0][16] === 8'h50, "single lane preserves A[0][16]");
        check(a_matrix[1][0] === -8'sd78, "single lane writes cross-row A[1][0]");
        check(a_matrix[1][1] === 8'h52 && a_matrix[1][2] === 8'h53,
              "single lane preserves unselected A elements");
        check(dut.a_written[17] && $countones(dut.a_written) == 1,
              "single lane sets only fixed A bitmap bit");

        write_word(PA + 4*4, 32'h84_73_62_51, 4'b1101);
        check(a_matrix[0][16] === 8'h51, "multi-lane writes lane 0");
        check(a_matrix[1][0] === -8'sd78, "multi-lane preserves lane 1");
        check(a_matrix[1][1] === 8'h73, "multi-lane writes lane 2");
        check(a_matrix[1][2] === -8'sd124, "multi-lane writes lane 3");
        check($countones(dut.a_written) == 4, "multi-lane updates independent A bits");

        // N2/K17 has two legal lanes in its final packed word. Invalid lanes
        // reject the whole beat, including an otherwise valid asserted lane.
        reset_device();
        write_word(PA + 4*8, 32'h44_33_22_11, 4'b0001);
        check(a_matrix[1][15] === 8'h11 && dut.a_written[32],
              "A tail lane 0 writes element 32");
        check(!dut.a_written[33], "A tail lane 1 remains unwritten");
        write_word(PA + 4*8, 32'hff_ff_ff_ff, 4'b0000);
        check(a_matrix[1][15] === 8'h11 && $countones(dut.a_written) == 1,
              "zero strobe has no A side effect");
        write_word(PA + 4*8, 32'h88_77_66_55, 4'b0110, 1);
        check(a_matrix[1][15] === 8'h11 && !dut.a_written[33]
              && $countones(dut.a_written) == 1,
              "invalid A tail lane rejects entire beat");
        write_word(PA + 4*8, 32'h00_00_80_00, 4'b0010);
        check(a_matrix[1][16] === -8'sd128 && dut.a_written[33],
              "A final legal lane writes signed byte and bitmap");

        reset_device();
        write_word(PB + 4*8, 32'h00_00_7f_81, 4'b0011);
        check(b_matrix[16][0] === -8'sd127 && b_matrix[16][1] === 8'sd127,
              "B final word maps fixed coordinates and signed bytes");
        check(dut.b_written[32] && dut.b_written[33]
              && $countones(dut.b_written) == 2,
              "B final word updates fixed bitmap bits");
        write_word(PB + 4*8, 32'h12_34_56_78, 4'b1001, 1);
        check(b_matrix[16][0] === -8'sd127 && b_matrix[16][1] === 8'sd127
              && $countones(dut.b_written) == 2,
              "invalid B tail lane rejects valid lane side effect");

        write_word(32'h1000_4000, 32'h0403_0201, 4'hf, 1);
        check($countones(dut.a_written) == 0 && $countones(dut.b_written) == 2,
              "high address alias cannot reach packed storage");

        check(WORDS == 34, "test shape retains expected non-divisible packed tail");
        $display("PASS tb_systolic_device_packed_decode: %0d checks", checks);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "timeout");
    end
endmodule
