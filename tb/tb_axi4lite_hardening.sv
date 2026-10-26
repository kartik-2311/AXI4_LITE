`timescale 1ns/1ps
module tb_axi4lite_hardening;
    parameter integer AH = 5, CH = 7;
    parameter integer ALIGN = 0, OOR = 0;
    reg ACLK=0, CORE_CLK=0, ARESETn=0, CORE_RESETn=0;
    always #AH ACLK=~ACLK;
    always #CH CORE_CLK=~CORE_CLK;
    reg [31:0] AWADDR=0, WDATA=0, ARADDR=0;
    reg [3:0] WSTRB=0;
    reg AWVALID=0, WVALID=0, ARVALID=0, BREADY=0, RREADY=0;
    wire AWREADY,WREADY,ARREADY,BVALID,RVALID;
    wire [1:0] BRESP,RRESP;
    wire [31:0] RDATA;
    axi4lite_slave_top #(
`ifdef POLICY
        .STRICT_ALIGN(ALIGN), .OOR_RESP(OOR),
`endif
        .FIFO_DEPTH(8)) dut (.*);

    integer seed=32'h41584934, rng=32'h41584934;
    integer mode=0, hold_inputs=0, n, wp=0, we=0, bp=0, ap=0, re=0, rp=0;
    reg [31:0] ra[0:1023];
    reg [31:0] wa[0:1023], wd[0:1023], expected_r[0:1023];
    reg [3:0] ws[0:1023];
    reg [1:0] expected_rr[0:1023];
    reg [31:0] model[0:15];
    integer i;
    initial for(i=0;i<16;i=i+1) model[i]=0;

    function integer random20;
        begin
            rng = rng * 1664525 + 1013904223;
            random20 = (rng & 32'h7fffffff) % 21;
        end
    endfunction
    function [1:0] response(input [31:0] addr);
        begin
            response = addr>=64 ? OOR : ((ALIGN && addr[1:0]!=0) ? 2 : 0);
        end
    endfunction
    task fail(input string message);
        begin
            $display("FAIL seed=%h ratio=%0d:%0d t=%0t mode=%0d AW=%0d EXEC=%0d B=%0d AR=%0d RE=%0d R=%0d %s",
                     seed,CH,AH,$time,mode,wp,we,bp,ap,re,rp,message);
            $fatal(1,"hardening checker failed");
        end
    endtask

    // Procedural protocol checker: the legacy simulator excludes concurrent SVA.
    reg stalled_b=0, stalled_r=0;
    reg [1:0] held_b, held_rr;
    reg [31:0] held_r;
    integer aw_count=0, w_count=0;
    always @(posedge ACLK) begin
        if (!ARESETn) begin
            wp=0; bp=0; ap=0; rp=0; aw_count=0; w_count=0;
            stalled_b=0; stalled_r=0;
        end else begin
            if (stalled_b && (!BVALID || BRESP!==held_b)) fail("P2 B stall stability");
            if (stalled_r && (!RVALID || RDATA!==held_r || RRESP!==held_rr)) fail("P2 R stall stability");
            stalled_b=BVALID && !BREADY; held_b=BRESP;
            stalled_r=RVALID && !RREADY; held_r=RDATA; held_rr=RRESP;
            if (AWVALID && AWREADY) begin wa[aw_count]=AWADDR; aw_count=aw_count+1; end
            if (WVALID && WREADY) begin wd[w_count]=WDATA; ws[w_count]=WSTRB; w_count=w_count+1; end
            wp=(aw_count<w_count ? aw_count : w_count);
            if (BVALID) begin
                if (bp>=we || bp>=wp) fail("P1 B before core execution or duplicate");
                if (BRESP!==response(wa[bp])) fail("P6 BRESP");
                if (BREADY) bp=bp+1;
            end
            if (ARVALID && ARREADY) begin ra[ap]=ARADDR; ap=ap+1; end
            if (RVALID && RREADY) begin
                if (rp>=ap || rp>=re) fail("P5 duplicate/unrequested R");
                if (RDATA!==expected_r[rp] || RRESP!==expected_rr[rp]) fail("P5 read data/order/response");
                rp=rp+1;
            end
            if (dut.wr_en && dut.wr_full) fail("P3 write FIFO overflow");
            if (dut.rd_req_en && dut.rd_req_full) fail("P3 request FIFO overflow");
        end
    end
    always @(posedge CORE_CLK) begin : core_reference
        integer byte_lane;
        reg [31:0] address;
        reg [1:0] resp;
        if (!CORE_RESETn) begin
            we=0; re=0;
            for(integer k=0;k<16;k=k+1) model[k]=0;
        end else begin
            if (dut.rd_resp_en && dut.rd_resp_full) fail("P3 response FIFO overflow");
            if (!dut.wr_empty) begin
                if (we>=wp) fail("P1 unaccepted/duplicate core write");
                if ({dut.wr_addr_core,dut.wr_data_core,dut.wr_strb_core} !== {wa[we],wd[we],ws[we]})
                    fail("P4 payload changed after handshake");
                address=wa[we]; resp=response(address);
                if (resp==0 && address<64)
                    for(byte_lane=0;byte_lane<4;byte_lane=byte_lane+1)
                        if(ws[we][byte_lane]) model[address[5:2]][byte_lane*8+:8]=wd[we][byte_lane*8+:8];
                we=we+1;
            end else if (!dut.rd_req_empty && dut.u_read_req_fifo.rd_en) begin
                if(re>=ap || dut.rd_addr_core!==ra[re]) fail("P5 AR payload changed after handshake");
                address=dut.rd_addr_core; resp=response(address);
                expected_r[re]=(resp==0 && address<64) ? model[address[5:2]] : 0;
                expected_rr[re]=resp; re=re+1;
            end
            #1;
            for(integer k=0;k<16;k=k+1)
                if(dut.reg_file[k]!==model[k]) fail("core register side effect disagrees with reference");
        end
    end

    task reset_joint;
        begin
            @(negedge ACLK); ARESETn=0; CORE_RESETn=0;
            AWVALID=0; WVALID=0; ARVALID=0; BREADY=0; RREADY=0;
            repeat(5) @(negedge ACLK);
            fork
                begin @(negedge ACLK); ARESETn=1; end
                begin @(negedge CORE_CLK); CORE_RESETn=1; end
            join
            repeat(4) @(negedge ACLK);
        end
    endtask
    task write_request(input [31:0] addr, data, input [3:0] strb, input integer skew);
        begin
            fork
                begin
                    if(skew>0) repeat(skew) @(negedge ACLK);
                    @(negedge ACLK); AWADDR=addr; AWVALID=1;
                    do @(posedge ACLK); while(!AWREADY);
                    @(negedge ACLK); AWVALID=0; if(!hold_inputs) AWADDR=32'hbad0bad0;
                end
                begin
                    if(skew<0) repeat(-skew) @(negedge ACLK);
                    @(negedge ACLK); WDATA=data; WSTRB=strb; WVALID=1;
                    do @(posedge ACLK); while(!WREADY);
                    @(negedge ACLK); WVALID=0; if(!hold_inputs) begin WDATA=32'hdeadbeef; WSTRB=0; end
                end
            join
        end
    endtask
    task write_one(input [31:0] addr, data, input [3:0] strb, input integer skew);
        integer target;
        begin
            target=bp+1;
            write_request(addr,data,strb,skew);
            wait(bp==target);
        end
    endtask
    task read_request(input [31:0] addr);
        begin
            @(negedge ACLK); ARADDR=addr; ARVALID=1;
            do @(posedge ACLK); while(!ARREADY);
            @(negedge ACLK); ARVALID=0; if(!hold_inputs) ARADDR=32'hbad0bad0;
        end
    endtask
    task read_one(input [31:0] addr);
        integer target;
        begin target=rp+1; read_request(addr); wait(rp==target); end
    endtask

    initial begin
        if ($value$plusargs("MODE=%d",mode)) begin end
        if ($value$plusargs("HOLD=%d",hold_inputs)) begin end
        $display("START seed=%h ACLK:CORE_CLK=%0d:%0d mode=%0d STRICT_ALIGN=%0d OOR_RESP=%0d",seed,CH,AH,mode,ALIGN,OOR);
        reset_joint();
        if(mode!=2) begin
            // Long B stall plus sustained attempted writes; only bounded work may enter.
            fork
                begin
                    for(integer j=0;j<24;j=j+1)
                        write_request((j%16)*4,32'h12340000+j,(j%16),j==0 ? 0 : random20()-10);
                end
                begin
                    wait(BVALID); repeat(80) @(negedge ACLK); BREADY=1;
                end
            join
            wait(bp==wp);
            for(integer j=0;j<16;j=j+1) write_one(j*4,32'haabbccdd,15,j%3==0 ? -20 : (j%3==1 ? 20 : 0));
            write_one(3,32'h11223344,5,0);
        end
        if(mode!=1) begin
            fork
                begin
                    for(integer j=0;j<24;j=j+1) read_request((j%16)*4);
                    wait(rp==24);
                end
                begin wait(RVALID); repeat(80) @(negedge ACLK); RREADY=1; end
            join
            if(mode==0) begin
                // Disjoint register sets avoid imposing cross-channel execution order.
                fork
                    begin for(integer j=0;j<20;j=j+1) write_one((j%8)*4,j,15,random20()-10); end
                    begin for(integer j=0;j<20;j=j+1) read_one((8+j%8)*4); end
                join
            end
        end
`ifdef POLICY
        if(mode==0) begin
            @(negedge ACLK); BREADY=0; RREADY=0;
            fork
                begin write_one(65,32'hffffffff,15,0); end
                begin wait(BVALID); repeat(80) @(negedge ACLK); BREADY=1; end
                begin read_one(65); end
                begin wait(RVALID); repeat(80) @(negedge ACLK); RREADY=1; end
            join
            write_one(64,32'hffffffff,15,0); read_one(64);
            write_one(32'h80000000,32'hffffffff,15,0); read_one(32'h80000000);
            write_one(1,32'hffffffff,15,0); read_one(1); read_one(0);
        end
`endif
        // Reset flushes accepted, executing, and stalled responses; new epoch starts clean.
        @(negedge ACLK); BREADY=0; RREADY=0;
        fork
            begin if(mode!=2) write_request(0,32'hcafebabe,15,0); end
            begin if(mode!=1) read_request(4); end
        join
        repeat(2) @(negedge ACLK); reset_joint();
        BREADY=1; RREADY=1;
        if(mode!=2) write_one(0,32'h87654321,15,0);
        if(mode!=1) read_one(0);
        repeat(100) @(negedge ACLK);
        if(wp!=bp || ap!=rp || wp!=we || ap!=re) fail("P3/P5 final accounting");
        $display("PASS seed=%h ratio=%0d:%0d mode=%0d",seed,CH,AH,mode);
        $finish;
    end
    initial begin
        repeat(20000) @(posedge ACLK);
        fail("bounded watchdog: deadlock/lost transaction");
    end
endmodule
