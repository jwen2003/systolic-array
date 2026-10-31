`timescale 1ns/1ps

// Real AXI slave + device + V1 core. No force, mock core, or direct buffer writes.
// Directed integration checks; protocol and device unit tests remain separate.
module tb_systolic_axi_lite_top #(
    parameter int unsigned N = 2,
    parameter int unsigned K = 3
);
    logic clk = 0, rst_n = 0;
    logic [31:0] s_axi_awaddr = 0, s_axi_wdata = 0, s_axi_araddr = 0;
    logic [2:0] s_axi_awprot = 0, s_axi_arprot = 0;
    logic [3:0] s_axi_wstrb = 4'hf;
    logic s_axi_awvalid = 0, s_axi_awready;
    logic s_axi_wvalid = 0, s_axi_wready;
    logic [1:0] s_axi_bresp, s_axi_rresp;
    logic s_axi_bvalid, s_axi_bready = 0;
    logic s_axi_arvalid = 0, s_axi_arready;
    logic [31:0] s_axi_rdata;
    logic s_axi_rvalid, s_axi_rready = 0;
    int signed host_a [N][K], host_b [K][N];
    int unsigned checks = 0, starts, completions;
    logic [31:0] value;

    systolic_axi_lite_top #(.N(N), .K(K)) dut (.*);
    initial forever #5 clk = ~clk;

    task automatic check(input bit condition, input string message);
        checks++;
        if (!condition) $fatal(1, "check %0d: %s", checks, message);
    endtask

    task automatic send_aw(input logic [31:0] address, input int unsigned delay_cycles);
        repeat (delay_cycles) @(negedge clk);
        @(negedge clk); s_axi_awaddr = address; s_axi_awvalid = 1;
        do @(posedge clk); while (!s_axi_awready);
        @(negedge clk); s_axi_awvalid = 0;
    endtask

    task automatic send_w(input logic [31:0] data, input int unsigned delay_cycles);
        repeat (delay_cycles) @(negedge clk);
        @(negedge clk); s_axi_wdata = data; s_axi_wvalid = 1;
        do @(posedge clk); while (!s_axi_wready);
        @(negedge clk); s_axi_wvalid = 0;
    endtask

    // order: 0 simultaneous, 1 AW first, 2 W first. Payload held until handshake.
    task automatic axi_write(input logic [31:0] address, data,
                             input int unsigned order = 0,
                             input int unsigned stall = 0,
                             input logic [1:0] response = 2'b00);
        fork
            send_aw(address, order == 2 ? 2 : 0);
            send_w(data, order == 1 ? 2 : 0);
        join
        do @(posedge clk); while (!s_axi_bvalid);
        check(s_axi_bresp === response, $sformatf("BRESP @%h", address));
        repeat (stall) begin
            @(posedge clk); #1;
            check(s_axi_bvalid && s_axi_bresp === response, "B response held");
        end
        @(negedge clk); s_axi_bready = 1;
        @(posedge clk); #1;
        check(!s_axi_bvalid, "B response consumed once");
        @(negedge clk); s_axi_bready = 0;
    endtask

    task automatic axi_read(input logic [31:0] address,
                            output logic [31:0] data,
                            input int unsigned stall = 0,
                            input logic [1:0] response = 2'b00);
        @(negedge clk); s_axi_araddr = address; s_axi_arvalid = 1;
        do @(posedge clk); while (!s_axi_arready);
        @(negedge clk); s_axi_arvalid = 0;
        do @(posedge clk); while (!s_axi_rvalid);
        data = s_axi_rdata;
        check(s_axi_rresp === response, $sformatf("RRESP @%h", address));
        repeat (stall) begin
            @(posedge clk); #1;
            check(s_axi_rvalid && s_axi_rdata === data && s_axi_rresp === response,
                  "R response held");
        end
        @(negedge clk); s_axi_rready = 1;
        @(posedge clk); #1;
        check(!s_axi_rvalid, "R response consumed once");
        @(negedge clk); s_axi_rready = 0;
    endtask

    task automatic expect_read(input logic [31:0] address, expected,
                               input logic [1:0] response = 2'b00);
        logic [31:0] actual;
        axi_read(address, actual, 2, response);
        check(actual === expected,
              $sformatf("read @%h got %h expected %h", address, actual, expected));
    endtask

    function automatic logic [31:0] golden(input int unsigned row, col);
        int signed sum;
        logic [17:0] wrapped;
        if (row >= N || col >= N) $fatal(1, "golden index out of range");
        sum = 0;
        for (int unsigned k = 0; k < K; k++) sum += host_a[row][k]*host_b[k][col];
        wrapped = 18'(sum);
        return {{14{wrapped[17]}}, wrapped};
    endfunction

    task automatic load_matrices(input int unsigned operation);
        for (int unsigned i = 0; i < N; i++)
            for (int unsigned k = 0; k < K; k++) begin
                // Signed extrema on operation 0, different signed data on 1.
                host_a[i][k] = operation == 0 ? (((i+k)%2 == 0) ? -128 : 127)
                                             : (int'(i)*3 - int'(k)*2 + 7);
                axi_write(32'h1000 + 4*(i*K+k), 32'(host_a[i][k]), (i+k)%3);
            end
        for (int unsigned k = 0; k < K; k++)
            for (int unsigned j = 0; j < N; j++) begin
                host_b[k][j] = operation == 0 ? (((k+j)%2 == 0) ? -128 : 127)
                                             : (int'(k) - int'(j)*4 - 3);
                axi_write(32'h2000 + 4*(k*N+j), 32'(host_b[k][j]), (k+j)%3);
            end
    endtask

    // Passive observation only: check no duplicate command/completion internally.
    always_ff @(posedge clk) begin
        if (!rst_n) begin starts <= 0; completions <= 0; end
        else begin
            if (dut.core_start) starts <= starts + 1;
            if (dut.core_done) completions <= completions + 1;
        end
    end

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk); rst_n = 1;
        expect_read(32'h0020, N); expect_read(32'h0024, K);
        expect_read(32'h0008, 0);
        // Error propagation really crosses the adapter's B/R channels.
        axi_write(32'h0004, 1, 1, 2, 2'b10);
        expect_read(32'h0010, 2);
        axi_write(32'h0010, 32'hff);
        expect_read(32'h3000, 0, 2'b10);
        expect_read(32'h0010, 16);
        axi_write(32'h0010, 32'hff);

        for (int unsigned op = 0; op < 2; op++) begin
            load_matrices(op);
            expect_read(32'h0008, 4);
            // Keep BREADY low while the core runs. B acknowledgement is NOT
            // compute completion, and response backpressure cannot stall core.
            axi_write(32'h0004, 1, op+1, K+2*N+5);
            axi_read(32'h0008, value);
            check(value === 6, "DONE persists after delayed write response");
            check(starts == op+1 && completions == op+1, "one start/completion per task");
            for (int unsigned i = 0; i < N; i++)
                for (int unsigned j = 0; j < N; j++) begin
                    axi_read(32'h3000 + 4*(i*N+j), value, 3);
                    check(value === golden(i,j),
                          $sformatf("operation %0d C[%0d][%0d] got %h expected %h",
                                    op, i, j, value, golden(i,j)));
                end
            axi_write(32'h0004, 1, 0, 2, 2'b10);
            expect_read(32'h0010, 1);
            axi_write(32'h0010, 32'hff);
            expect_read(32'h0008, 6);
            expect_read(32'h3000, golden(0,0));
            axi_write(32'h000c, 1);
            expect_read(32'h0008, 0);
            expect_read(32'h1000, 0); // written map invalidated, not payload reset
            expect_read(32'h2000, 0);
        end
        check(starts == 2 && completions == 2, "no duplicate starts or completions");
        expect_read(32'h0010, 0);
        $display("PASS tb_systolic_axi_lite_top N=%0d K=%0d: %0d checks", N, K, checks);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "AXI integration watchdog timeout");
    end
endmodule
