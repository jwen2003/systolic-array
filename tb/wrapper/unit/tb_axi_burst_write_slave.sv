`timescale 1ns/1ps

module tb_axi_burst_write_slave;
    logic clk = 0, rst_n = 0;
    logic [31:0] s_axi_awaddr = 0;
    logic [7:0] s_axi_awlen = 0;
    logic [2:0] s_axi_awsize = 2;
    logic [1:0] s_axi_awburst = 1;
    logic s_axi_awvalid = 0, s_axi_awready;
    logic [31:0] s_axi_wdata = 0;
    logic [3:0] s_axi_wstrb = 1;
    logic s_axi_wlast = 0, s_axi_wvalid = 0, s_axi_wready;
    logic [1:0] s_axi_bresp;
    logic s_axi_bvalid, s_axi_bready = 0;
    logic wr_grant = 1, active, wr_en, wr_error;
    logic [31:0] wr_addr, wr_data;
    logic [3:0] wr_strb;
    logic inject_error = 0;
    logic [31:0] error_addr = 0;
    int unsigned attempts, commits, cycles, last_commit;
    int unsigned checks = 0;
    logic [31:0] seen_addr [0:63], seen_data [0:63];
    logic [3:0] seen_strb [0:63];
    axi_burst_write_slave #(.INPUT_WORDS(34)) dut (.*);
    initial forever #5 clk = ~clk;
    assign wr_error = inject_error && wr_addr == error_addr;

    task automatic check(input bit condition, input string message);
        checks++;
        if (!condition) $fatal(1, "check %0d: %s", checks, message);
    endtask

    // Simple device model, driven only by public request pins.
    always_ff @(posedge clk) begin
        if (!rst_n) begin attempts <= 0; commits <= 0; cycles <= 0; last_commit <= 0; end
        else begin
            cycles <= cycles+1;
            if (wr_en) begin
                attempts <= attempts+1;
                if (!wr_error) begin
                    assert (commits < 64) else $fatal(1, "device log overflow");
                    seen_addr[commits] <= wr_addr;
                    seen_data[commits] <= wr_data;
                    seen_strb[commits] <= wr_strb;
                    commits <= commits+1;
                    last_commit <= cycles;
                end
            end
        end
    end

    task automatic reset_dut;
        @(negedge clk); rst_n = 0;
        s_axi_awvalid = 0; s_axi_wvalid = 0; s_axi_bready = 0;
        inject_error = 0; wr_grant = 1;
        repeat (2) @(posedge clk);
        @(negedge clk); rst_n = 1;
        #1;
        check(s_axi_awready && !s_axi_wready && !s_axi_bvalid && !active,
              "reset returns idle");
    endtask

    task automatic address(input logic [31:0] addr, input int unsigned beats,
                           input logic [2:0] size = 2, input logic [1:0] burst = 1);
        @(negedge clk);
        s_axi_awaddr = addr; s_axi_awlen = 8'(beats-1);
        s_axi_awsize = size; s_axi_awburst = burst; s_axi_awvalid = 1;
        do @(posedge clk); while (!s_axi_awready);
        @(negedge clk); s_axi_awvalid = 0;
    endtask

    task automatic beat(input logic [31:0] data, input bit last,
                        input int unsigned stalls = 0);
        // Returns just after the accepting edge so sequential calls can send
        // adjacent beats with NO accidental testbench bubble.
        @(negedge clk);
        s_axi_wdata = data; s_axi_wlast = last; s_axi_wvalid = 1;
        wr_grant = stalls == 0;
        repeat (stalls) begin
            @(posedge clk); #1;
            check(!s_axi_wready && !wr_en, "no write without grant");
        end
        if (stalls != 0) begin @(negedge clk); wr_grant = 1; end
        do @(posedge clk); while (!s_axi_wready);
        #1;
    endtask

    task automatic response(input logic [1:0] expected, input int unsigned stalls = 0);
        @(negedge clk); s_axi_wvalid = 0;
        #1;
        check(s_axi_bvalid && s_axi_bresp === expected && active, "burst response");
        repeat (stalls) begin
            @(posedge clk); #1;
            check(s_axi_bvalid && s_axi_bresp === expected && !s_axi_awready && !wr_en,
                  "response held; no new request");
        end
        @(negedge clk); s_axi_bready = 1;
        @(posedge clk); #1;
        check(!s_axi_bvalid && s_axi_awready && !active, "one response consumed");
        @(negedge clk); s_axi_bready = 0;
    endtask

    task automatic rejected_descriptor(input logic [31:0] addr, input int unsigned count,
                                       input logic [2:0] size = 2,
                                       input logic [1:0] burst = 1);
        int unsigned before_attempts;
        before_attempts = attempts;
        address(addr,count,size,burst);
        for (int unsigned x = 0; x < count; x++) beat(x,x == count-1);
        response(2'b10);
        check(attempts == before_attempts, "bad descriptor has no device effects");
    endtask

    initial begin
        int unsigned first_cycle, before_count, before_attempts;
        reset_dut();
        // W may arrive before AW: no premature write/handshake permitted.
        @(negedge clk); s_axi_wvalid = 1; s_axi_wdata = 99; s_axi_wlast = 1;
        repeat (2) begin @(posedge clk); #1; check(!s_axi_wready && !wr_en, "W before AW waits"); end
        address(32'h1000,1);
        // The held W=99 is accepted at the next edge; do not replace it first.
        @(posedge clk); #1;
        response(0,3);
        check(commits == 1 && seen_data[0] == 99, "early W preserved");

        // Maximum burst: exactly one write on each of 16 consecutive edges.
        before_count = commits;
        address(32'h1000,16);
        first_cycle = 0;
        for (int unsigned x = 0; x < 16; x++) begin
            s_axi_wstrb = 4'(x%16);
            beat(32'h80+x,x == 15);
            if (x == 0) first_cycle = last_commit;
            else check(last_commit == first_cycle+x, "one beat per cycle");
            check(seen_addr[before_count+x] == 32'h1000+4*x, "incremented address");
            check(seen_data[before_count+x] == 32'h80+x, "data pairing");
            check(seen_strb[before_count+x] == 4'(x%16), "WSTRB preserved");
        end
        response(0);
        check(commits == before_count+16, "16 writes exactly once");

        address(32'h2000,4);
        before_count = commits;
        beat(11,0); beat(22,0,2);
        // Master bubble: remove VALID only AFTER previous handshake.
        @(negedge clk); s_axi_wvalid = 0;
        repeat (3) begin @(posedge clk); #1; check(!wr_en, "master bubble causes no write"); end
        beat(33,0); beat(44,1);
        response(0);
        check(commits == before_count+4, "stalls do not duplicate or lose writes");
        for (int unsigned x = 0; x < 4; x++)
            check(seen_addr[before_count+x] == 32'h2000+4*x, "stall preserves address sequence");

        // Tail at the exact exclusive end of the 34-word buffer.
        address(32'h1080,2); beat(1,0); beat(2,1); response(0);
        rejected_descriptor(32'h1084,2); // runs off end
        rejected_descriptor(32'h1001,1); // misaligned
        rejected_descriptor(32'h1000,1,1); // narrow transfer unsupported
        rejected_descriptor(32'h1000,1,2,0); // FIXED unsupported
        rejected_descriptor(32'h1000,17); // >maximum, still drain declared count
        rejected_descriptor(32'h1ffc,2); // window/4 KiB crossing
        rejected_descriptor(32'hffff_fffc,2); // address wrap
        rejected_descriptor(32'h0004,1); // CSR not on this port

        // Final-beat device error must be included in the ONE response.
        address(32'h2000,2);
        inject_error = 1; error_addr = 32'h2004;
        before_count = commits; before_attempts = attempts;
        beat(1,0); beat(2,1); response(2'b10);
        check(attempts == before_attempts+2 && commits == before_count+1, "last-beat error included");
        inject_error = 0;
        // A middle error must not terminate the transaction or block later beats.
        address(32'h2000,3);
        inject_error = 1; error_addr = 32'h2004;
        before_count = commits;
        beat(1,0); beat(2,0); beat(3,1); response(2'b10);
        check(commits == before_count+2, "later valid beat survives device error");
        inject_error = 0;

        // Malformed WLAST: drain AWLEN; suppress mismatch and later writes.
        address(32'h1000,3); before_count = commits;
        beat(1,0); beat(2,1); beat(3,1); response(2'b10);
        check(commits == before_count+1, "early WLAST suppression");
        address(32'h1000,1); before_count = commits;
        beat(1,0); response(2'b10);
        check(commits == before_count, "missing final WLAST suppression");
        address(32'h1000,1); beat(55,1); response(0);

        // Reset an incomplete transfer and a held error response.
        address(32'h1000,4); beat(1,0); reset_dut();
        check(commits == 0 && attempts == 0, "reset cancels pending transaction");
        address(32'h1000,1); beat(1,0);
        reset_dut();
        address(32'h1000,1); beat(77,1); response(0);
        $display("PASS tb_axi_burst_write_slave: %0d checks",checks);
        $finish;
    end
    initial begin #100000; $fatal(1,"watchdog timeout"); end
endmodule
