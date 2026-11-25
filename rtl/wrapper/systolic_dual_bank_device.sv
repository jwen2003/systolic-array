`timescale 1ns/1ps

// Experimental two-bank input Device. Bank 0 preserves the baseline windows;
// bank 1 uses separate windows, so software never races on a WRITE_BANK CSR.
// One result buffer is retained. A bank is owned from accepted START through
// ACK; the other bank remains readable/writable while the Core is RUN or DONE.
module systolic_dual_bank_device #(
    parameter int unsigned N = 2, K = 2, DATA_W = 8, ACC_W = 18,
    parameter bit PACKED_ENABLE = 0
) (
    input logic clk, rst_n,
    input logic wr_en, input logic [31:0] wr_addr, wr_data,
    input logic [3:0] wr_strb, output logic wr_error,
    input logic rd_en, input logic [31:0] rd_addr,
    output logic [31:0] rd_data, output logic rd_error,
    input logic result_read_busy, output logic result_available,
    output logic core_start, input logic core_busy, core_done,
    output logic signed [DATA_W-1:0] a_matrix [N-1:0][K-1:0],
    output logic signed [DATA_W-1:0] b_matrix [K-1:0][N-1:0],
    input logic signed [ACC_W-1:0] core_result [N-1:0][N-1:0]
);
    localparam int unsigned INPUT_WORDS=N*K, RESULT_WORDS=N*N;
    localparam logic [31:0] A0=32'h1000, B0=32'h2000, C0=32'h3000;
    localparam logic [31:0] PA0=32'h4000, PB0=32'h5000;
    localparam logic [31:0] A1=32'h6000, B1=32'h7000;
    localparam logic [31:0] PA1=32'h8000, PB1=32'h9000;
    localparam logic [31:0] INPUT_BYTES=4*INPUT_WORDS;
    localparam logic [31:0] RESULT_BYTES=4*RESULT_WORDS;
    localparam logic [31:0] PACKED_BYTES=4*((INPUT_WORDS+3)/4);
    localparam int unsigned TAIL=INPUT_WORDS%4;
    localparam logic [3:0] TAIL_BAD=TAIL==0 ? 4'b0 : (4'b1111<<TAIL);
    localparam logic [31:0] LAST_PACKED=4*(INPUT_WORDS/4);
    typedef enum logic [1:0] {IDLE,RUN,DONE} state_t;
    state_t state;
    logic active_bank;
    logic signed [DATA_W-1:0] a_bank [1:0][N-1:0][K-1:0];
    logic signed [DATA_W-1:0] b_bank [1:0][K-1:0][N-1:0];
    logic [INPUT_WORDS-1:0] a_written [1:0], b_written [1:0];
    logic ready [1:0], locked [1:0];
    logic [31:0] errors, wr_bits, rd_bits, clear_mask, byte_mask;
    logic start0, start1, ack;
    logic [31:0] a_read [1:0], b_read [1:0], c_read;
    logic packed_hit, packed_tail_bad;

    initial begin
        if (N==0 || K==0 || INPUT_WORDS>1024 || RESULT_WORDS>1024)
            $fatal(1,"Shape exceeds a 4 KiB window");
        if (DATA_W!=8 || ACC_W!=18) $fatal(1,"Only INT8/INT18 is supported");
    end
    assign ready[0]=&a_written[0] && &b_written[0];
    assign ready[1]=&a_written[1] && &b_written[1];
    assign result_available=state==DONE;
    assign locked[0]=(state!=IDLE) && active_bank==0;
    assign locked[1]=(state!=IDLE) && active_bank==1;
    assign wr_error=|wr_bits; assign rd_error=|rd_bits;
    assign byte_mask={{8{wr_strb[3]}},{8{wr_strb[2]}},{8{wr_strb[1]}},{8{wr_strb[0]}}};
    assign clear_mask=(wr_en&&!wr_error&&wr_addr==32'h0010) ? (wr_data&byte_mask&32'hff) : 0;
    assign start0=wr_en&&!wr_error&&wr_addr==32'h0004&&wr_strb[0]&&wr_data[0];
    assign start1=wr_en&&!wr_error&&wr_addr==32'h0004&&wr_strb[0]&&wr_data[1];
    assign ack=wr_en&&!wr_error&&wr_addr==32'h000c&&wr_strb[0]&&wr_data[0]&&state==DONE;
    assign packed_hit=PACKED_ENABLE && ((wr_addr>=PA0&&wr_addr<PA0+PACKED_BYTES)||
        (wr_addr>=PB0&&wr_addr<PB0+PACKED_BYTES)||(wr_addr>=PA1&&wr_addr<PA1+PACKED_BYTES)||
        (wr_addr>=PB1&&wr_addr<PB1+PACKED_BYTES));
    assign packed_tail_bad=|(wr_strb&TAIL_BAD) &&
        (wr_addr==PA0+LAST_PACKED||wr_addr==PB0+LAST_PACKED||
         wr_addr==PA1+LAST_PACKED||wr_addr==PB1+LAST_PACKED);

    always_comb begin
        for (int r=0;r<N;r++) for (int k=0;k<K;k++) a_matrix[r][k]=a_bank[active_bank][r][k];
        for (int k=0;k<K;k++) for (int c=0;c<N;c++) b_matrix[k][c]=b_bank[active_bank][k][c];
        a_read[0]=0; a_read[1]=0; b_read[0]=0; b_read[1]=0; c_read=0;
        for (int bank=0;bank<2;bank++) begin
            for (int r=0;r<N;r++) for (int k=0;k<K;k++)
                a_read[bank] |= {32{rd_addr==((bank==1)?A1:A0)+4*(r*K+k)}} &
                    (a_written[bank][r*K+k] ? {{(32-DATA_W){a_bank[bank][r][k][DATA_W-1]}},a_bank[bank][r][k]} : 0);
            for (int k=0;k<K;k++) for (int c=0;c<N;c++)
                b_read[bank] |= {32{rd_addr==((bank==1)?B1:B0)+4*(k*N+c)}} &
                    (b_written[bank][k*N+c] ? {{(32-DATA_W){b_bank[bank][k][c][DATA_W-1]}},b_bank[bank][k][c]} : 0);
        end
        for (int r=0;r<N;r++) for (int c=0;c<N;c++)
            c_read |= {32{rd_addr==C0+4*(r*N+c)}} & {{(32-ACC_W){core_result[r][c][ACC_W-1]}},core_result[r][c]};
    end

    function automatic logic in_range(input logic [31:0] x, base, bytes);
        return x>=base && x<base+bytes;
    endfunction
    function automatic logic bank_of(input logic [31:0] x);
        return in_range(x,A1,INPUT_BYTES)||in_range(x,B1,INPUT_BYTES)||
               in_range(x,PA1,PACKED_BYTES)||in_range(x,PB1,PACKED_BYTES);
    endfunction

    always_comb begin
        wr_bits=0;
        if (wr_addr[1:0]!=0) wr_bits[5]=1;
        else if (packed_hit) begin
            if (locked[bank_of(wr_addr)]) wr_bits[3]=1;
            else if (packed_tail_bad) wr_bits[2]=1;
        end else if (in_range(wr_addr,A0,INPUT_BYTES)||in_range(wr_addr,B0,INPUT_BYTES)||
                     in_range(wr_addr,A1,INPUT_BYTES)||in_range(wr_addr,B1,INPUT_BYTES)) begin
            if (locked[bank_of(wr_addr)]) wr_bits[3]=1;
        end else if (in_range(wr_addr,C0,RESULT_BYTES)) wr_bits[6]=1;
        else case (wr_addr)
            32'h0004: if (wr_strb[0] && |wr_data[1:0]) begin
                if (&wr_data[1:0] || state!=IDLE || core_busy) wr_bits[0]=1;
                else if ((wr_data[0]&&!ready[0])||(wr_data[1]&&!ready[1])) wr_bits[1]=1;
            end
            32'h000c: if (wr_strb[0] && wr_data[0] && state==DONE && result_read_busy) wr_bits[0]=1;
            32'h0010: ;
            32'h0000,32'h0008,32'h0020,32'h0024,32'h0028,32'h002c: wr_bits[6]=1;
            default: wr_bits[2]=1;
        endcase
    end

    always_comb begin
        rd_data=0; rd_bits=0;
        if (rd_addr[1:0]!=0) rd_bits[5]=1;
        else if (in_range(rd_addr,A0,INPUT_BYTES)) begin if(locked[0]) rd_bits[7]=1; else rd_data=a_read[0]; end
        else if (in_range(rd_addr,B0,INPUT_BYTES)) begin if(locked[0]) rd_bits[7]=1; else rd_data=b_read[0]; end
        else if (in_range(rd_addr,A1,INPUT_BYTES)) begin if(locked[1]) rd_bits[7]=1; else rd_data=a_read[1]; end
        else if (in_range(rd_addr,B1,INPUT_BYTES)) begin if(locked[1]) rd_bits[7]=1; else rd_data=b_read[1]; end
        else if (in_range(rd_addr,C0,RESULT_BYTES)) begin if(state!=DONE) rd_bits[4]=1; else rd_data=c_read; end
        else case(rd_addr)
            32'h0000: rd_data=32'h0000_0300;
            32'h0008: begin
                rd_data[0]=state==RUN; rd_data[1]=state==DONE;
                rd_data[2]=ready[0]; rd_data[3]=|errors; rd_data[4]=ready[1];
                rd_data[5]=(state!=IDLE) && active_bank; rd_data[6]=state!=IDLE;
            end
            32'h0010: rd_data=errors;
            32'h0020: rd_data=N; 32'h0024: rd_data=K;
            32'h0028: rd_data=DATA_W; 32'h002c: rd_data=ACC_W;
            default: rd_bits[2]=1;
        endcase
    end

    always_ff @(posedge clk) begin
        if(!rst_n) begin state<=IDLE; active_bank<=0; core_start<=0;
            a_written[0]<='0; a_written[1]<='0; b_written[0]<='0; b_written[1]<='0; errors<=0;
        end else begin
            core_start<=0;
            errors <= (errors & ~clear_mask) | (wr_en?wr_bits:0) | (rd_en?rd_bits:0);
            if(start0||start1) begin active_bank<=start1; state<=RUN; core_start<=1; end
            else if(state==RUN && core_done) state<=DONE;
            else if(ack) begin
                state<=IDLE;
                if(active_bank==0) begin a_written[0]<='0; b_written[0]<='0; end
                else begin a_written[1]<='0; b_written[1]<='0; end
            end
            if(wr_en&&!wr_error) begin
                for(int bank=0;bank<2;bank++) begin
                    for(int r=0;r<N;r++) for(int k=0;k<K;k++) begin
                        int p; logic [31:0] nb,pb; int lane;
                        p=r*K+k; nb=((bank==1)?A1:A0)+4*p; pb=((bank==1)?PA1:PA0)+4*(p/4); lane=p%4;
                        if(wr_addr==nb&&wr_strb[0]) begin a_bank[bank][r][k]<=$signed(wr_data[DATA_W-1:0]); a_written[bank][p]<=1; end
                        if(PACKED_ENABLE&&wr_addr==pb&&wr_strb[lane]) begin a_bank[bank][r][k]<=$signed(wr_data[8*lane+:DATA_W]); a_written[bank][p]<=1; end
                    end
                    for(int k=0;k<K;k++) for(int c=0;c<N;c++) begin
                        int p; logic [31:0] nb,pb; int lane;
                        p=k*N+c; nb=((bank==1)?B1:B0)+4*p; pb=((bank==1)?PB1:PB0)+4*(p/4); lane=p%4;
                        if(wr_addr==nb&&wr_strb[0]) begin b_bank[bank][k][c]<=$signed(wr_data[DATA_W-1:0]); b_written[bank][p]<=1; end
                        if(PACKED_ENABLE&&wr_addr==pb&&wr_strb[lane]) begin b_bank[bank][k][c]<=$signed(wr_data[8*lane+:DATA_W]); b_written[bank][p]<=1; end
                    end
                end
            end
        end
    end
endmodule
