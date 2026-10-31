`timescale 1ns/1ps

// Unit-level protocol test for axi_lite_slave. The mock device below provides
// two simple registers so the test can verify AXI4-Lite channel ordering,
// backpressure, byte strobes, and error propagation without using the V1 core.
module tb_axi_lite_slave;

    localparam logic [1:0] RESP_OKAY   = 2'b00;
    localparam logic [1:0] RESP_SLVERR = 2'b10;

    logic        clk;
    logic        rst_n;
    logic [31:0] s_axi_awaddr;
    logic [2:0]  s_axi_awprot;
    logic        s_axi_awvalid;
    logic        s_axi_awready;
    logic [31:0] s_axi_wdata;
    logic [3:0]  s_axi_wstrb;
    logic        s_axi_wvalid;
    logic        s_axi_wready;
    logic [1:0]  s_axi_bresp;
    logic        s_axi_bvalid;
    logic        s_axi_bready;
    logic [31:0] s_axi_araddr;
    logic [2:0]  s_axi_arprot;
    logic        s_axi_arvalid;
    logic        s_axi_arready;
    logic [31:0] s_axi_rdata;
    logic [1:0]  s_axi_rresp;
    logic        s_axi_rvalid;
    logic        s_axi_rready;
    logic        wr_en;
    logic [31:0] wr_addr;
    logic [31:0] wr_data;
    logic [3:0]  wr_strb;
    logic        wr_error;
    logic        rd_en;
    logic [31:0] rd_addr;
    logic [31:0] rd_data;
    logic        rd_error;

    logic [31:0] mock_reg0;
    logic [31:0] mock_reg1;
    int unsigned check_count;
    int unsigned write_attempt_count;
    int unsigned accepted_write_count;
    int unsigned read_request_count;

    axi_lite_slave dut (.*);

    // A blocking assignment is intentional in this testbench-only clock source.
    /* verilator lint_off BLKSEQ */
    always #5 clk = ~clk;
    /* verilator lint_on BLKSEQ */

    // The mock device accepts aligned accesses to offsets 0x0 and 0x4 only.
    always_comb begin
        wr_error = (wr_addr[1:0] != 2'b00)
                || ((wr_addr != 32'h0000_0000) && (wr_addr != 32'h0000_0004));
        rd_error = (rd_addr[1:0] != 2'b00)
                || ((rd_addr != 32'h0000_0000) && (rd_addr != 32'h0000_0004));

        unique case (rd_addr)
            32'h0000_0000: rd_data = mock_reg0;
            32'h0000_0004: rd_data = mock_reg1;
            default:       rd_data = 32'hdead_beef;
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mock_reg0          <= 32'h1122_3344;
            mock_reg1          <= 32'h5566_7788;
            write_attempt_count <= 0;
            accepted_write_count <= 0;
            read_request_count <= 0;
        end else begin
            if (wr_en) begin
                write_attempt_count <= write_attempt_count + 1;
                if (!wr_error) begin
                    accepted_write_count <= accepted_write_count + 1;
                    for (int byte_index = 0; byte_index < 4; byte_index++) begin
                        if (wr_strb[byte_index]) begin
                            if (wr_addr == 32'h0000_0000) begin
                                mock_reg0[byte_index*8 +: 8] <= wr_data[byte_index*8 +: 8];
                            end else begin
                                mock_reg1[byte_index*8 +: 8] <= wr_data[byte_index*8 +: 8];
                            end
                        end
                    end
                end
            end
            if (rd_en) begin
                read_request_count <= read_request_count + 1;
            end
        end
    end

    task automatic check(input logic condition, input string message);
        check_count++;
        if (!condition) begin
            $fatal(1, "CHECK %0d FAILED: %s", check_count, message);
        end
    endtask

    task automatic drive_master_idle;
        s_axi_awaddr  = '0;
        s_axi_awprot  = '0;
        s_axi_awvalid = 1'b0;
        s_axi_wdata   = '0;
        s_axi_wstrb   = '0;
        s_axi_wvalid  = 1'b0;
        s_axi_bready  = 1'b0;
        s_axi_araddr  = '0;
        s_axi_arprot  = '0;
        s_axi_arvalid = 1'b0;
        s_axi_rready  = 1'b0;
    endtask

    task automatic apply_reset;
        @(negedge clk);
        rst_n = 1'b0;
        @(posedge clk);
        #1;
        check(!s_axi_awready && !s_axi_wready && !s_axi_arready,
              "request ready signals must be low during synchronous reset");
        check(!s_axi_bvalid && !s_axi_rvalid,
              "response valid signals must clear on reset");
        check((mock_reg0 == 32'h1122_3344) && (mock_reg1 == 32'h5566_7788),
              "mock device reset values must be visible");
        @(negedge clk);
        rst_n = 1'b1;
        #1;
        check(s_axi_awready && s_axi_wready && s_axi_arready,
              "all request channels must be ready after reset release");
    endtask

    task automatic send_aw(input logic [31:0] address);
        @(negedge clk);
        s_axi_awaddr  = address;
        s_axi_awvalid = 1'b1;
        check(s_axi_awready, "AW channel must accept an address when empty");
        @(posedge clk);
        @(negedge clk);
        s_axi_awvalid = 1'b0;
        check(!s_axi_awready, "AW channel must stop after storing one address");
    endtask

    task automatic send_w(input logic [31:0] data, input logic [3:0] strobe);
        @(negedge clk);
        s_axi_wdata  = data;
        s_axi_wstrb  = strobe;
        s_axi_wvalid = 1'b1;
        check(s_axi_wready, "W channel must accept data when empty");
        @(posedge clk);
        @(negedge clk);
        s_axi_wvalid = 1'b0;
        check(!s_axi_wready, "W channel must stop after storing one payload");
    endtask

    task automatic complete_write_response(
        input logic [1:0] expected_resp,
        input int unsigned hold_cycles
    );
        while (!s_axi_bvalid) begin
            @(posedge clk);
            #1;
        end
        check(s_axi_bresp == expected_resp, "BRESP must match the device result");
        check(!s_axi_awready && !s_axi_wready,
              "new write requests must be blocked by an outstanding response");

        repeat (hold_cycles) begin
            logic [1:0] held_resp;
            held_resp = s_axi_bresp;
            @(posedge clk);
            #1;
            check(s_axi_bvalid && (s_axi_bresp == held_resp),
                  "BVALID and BRESP must remain stable under backpressure");
        end

        @(negedge clk);
        s_axi_bready = 1'b1;
        @(posedge clk);
        #1;
        check(!s_axi_bvalid, "BVALID must clear after the response handshake");
        @(negedge clk);
        s_axi_bready = 1'b0;
        #1;
        check(s_axi_awready && s_axi_wready,
              "write channels must reopen after the response is consumed");
    endtask

    task automatic write_aw_first(
        input logic [31:0] address,
        input logic [31:0] data,
        input logic [3:0] strobe,
        input logic [1:0] expected_resp
    );
        send_aw(address);
        check(!wr_en, "an address alone must not issue a device write");
        send_w(data, strobe);
        complete_write_response(expected_resp, 2);
    endtask

    task automatic write_w_first(
        input logic [31:0] address,
        input logic [31:0] data,
        input logic [3:0] strobe,
        input logic [1:0] expected_resp
    );
        send_w(data, strobe);
        check(!wr_en, "write data alone must not issue a device write");
        send_aw(address);
        complete_write_response(expected_resp, 1);
    endtask

    task automatic write_together(
        input logic [31:0] address,
        input logic [31:0] data,
        input logic [3:0] strobe,
        input logic [1:0] expected_resp
    );
        @(negedge clk);
        s_axi_awaddr  = address;
        s_axi_awvalid = 1'b1;
        s_axi_wdata   = data;
        s_axi_wstrb   = strobe;
        s_axi_wvalid  = 1'b1;
        check(s_axi_awready && s_axi_wready,
              "AW and W must be independently ready for a joint request");
        @(posedge clk);
        @(negedge clk);
        s_axi_awvalid = 1'b0;
        s_axi_wvalid  = 1'b0;
        check(wr_en, "a stored address and payload must generate one write attempt");
        complete_write_response(expected_resp, 0);
    endtask

    task automatic read_transaction(
        input logic [31:0] address,
        input logic [31:0] expected_data,
        input logic [1:0] expected_resp,
        input int unsigned hold_cycles
    );
        @(negedge clk);
        s_axi_araddr  = address;
        s_axi_arvalid = 1'b1;
        #1;
        check(s_axi_arready, "AR channel must accept a request when no response is pending");
        check(rd_en, "AR handshake must assert the device read enable");
        @(posedge clk);
        #1;
        check(s_axi_rvalid, "RVALID must assert after an AR handshake");
        check(s_axi_rresp == expected_resp, "RRESP must match the device result");
        check(s_axi_rdata == expected_data, "RDATA must capture the device snapshot");
        @(negedge clk);
        s_axi_arvalid = 1'b0;
        check(!s_axi_arready, "ARREADY must remain low while RVALID is pending");

        repeat (hold_cycles) begin
            logic [31:0] held_data;
            logic [1:0]  held_resp;
            held_data = s_axi_rdata;
            held_resp = s_axi_rresp;
            @(posedge clk);
            #1;
            check(s_axi_rvalid && (s_axi_rdata == held_data) && (s_axi_rresp == held_resp),
                  "read response must remain stable under backpressure");
        end

        @(negedge clk);
        s_axi_rready = 1'b1;
        @(posedge clk);
        #1;
        check(!s_axi_rvalid, "RVALID must clear after the response handshake");
        @(negedge clk);
        s_axi_rready = 1'b0;
        #1;
        check(s_axi_arready, "AR channel must reopen after response consumption");
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b1;
        check_count = 0;
        drive_master_idle();

        apply_reset();

        write_aw_first(32'h0000_0000, 32'haabb_ccdd, 4'b1111, RESP_OKAY);
        check(mock_reg0 == 32'haabb_ccdd, "AW-first write must update register zero");
        check((write_attempt_count == 1) && (accepted_write_count == 1),
              "AW-first transaction must issue exactly one accepted write");

        write_w_first(32'h0000_0004, 32'h1234_5678, 4'b1111, RESP_OKAY);
        check(mock_reg1 == 32'h1234_5678, "W-first write must update register one");
        check((write_attempt_count == 2) && (accepted_write_count == 2),
              "W-first transaction must issue exactly one accepted write");

        write_together(32'h0000_0000, 32'h55ee_77aa, 4'b0101, RESP_OKAY);
        check(mock_reg0 == 32'haaee_ccaa, "WSTRB must update only selected byte lanes");
        check((write_attempt_count == 3) && (accepted_write_count == 3),
              "joint AW/W transaction must issue exactly one accepted write");

        write_together(32'h0000_0002, 32'hffff_ffff, 4'b1111, RESP_SLVERR);
        check(mock_reg0 == 32'haaee_ccaa, "misaligned write must not change device state");
        check((write_attempt_count == 4) && (accepted_write_count == 3),
              "failed write must be counted as an attempt but not accepted");

        read_transaction(32'h0000_0000, 32'haaee_ccaa, RESP_OKAY, 2);
        check(read_request_count == 1, "successful read must issue one device request");
        read_transaction(32'h0000_0004, 32'h1234_5678, RESP_OKAY, 0);
        check(read_request_count == 2, "second read must issue one additional request");
        read_transaction(32'h0000_0008, 32'h0000_0000, RESP_SLVERR, 1);
        check(read_request_count == 3, "failing read must still issue one device request");

        // Reset must abort a captured but incomplete write request.
        send_aw(32'h0000_0000);
        check(!wr_en, "incomplete write must remain pending before reset");
        apply_reset();
        check((write_attempt_count == 0) && (accepted_write_count == 0)
              && (read_request_count == 0),
              "mock counters must reset with the adapter");
        check(!wr_en && !s_axi_bvalid && !s_axi_rvalid,
              "reset must discard all pending protocol state");

        $display("PASS: axi_lite_slave completed %0d checks", check_count);
        $finish;
    end

endmodule
