`timescale 1ns/1ps

// Testbench for AXI4-Lite Slave with CDC FIFO (Write and Read Paths)
// Tests: write to registers, read back and verify data
// Clock domains: ACLK and CORE_CLK at different frequencies

module tb_axi4lite_slave_top;

    // Parameters
    localparam AXI_ADDR_WIDTH = 32;
    localparam AXI_DATA_WIDTH = 32;
    localparam AXI_STRB_WIDTH = AXI_DATA_WIDTH/8;

    // Clock and reset
    logic ACLK;
    logic ARESETn;
    logic CORE_CLK;
    logic CORE_RESETn;

    // AXI4-Lite interface
    logic [AXI_ADDR_WIDTH-1:0] AWADDR;
    logic AWVALID;
    logic AWREADY;
    logic [AXI_DATA_WIDTH-1:0] WDATA;
    logic [AXI_STRB_WIDTH-1:0] WSTRB;
    logic WVALID;
    logic WREADY;
    logic [1:0] BRESP;
    logic BVALID;
    logic BREADY;
    logic [AXI_ADDR_WIDTH-1:0] ARADDR;
    logic ARVALID;
    logic ARREADY;
    logic [AXI_DATA_WIDTH-1:0] RDATA;
    logic [1:0] RRESP;
    logic RVALID;
    logic RREADY;

    // Clock generation
    initial begin
        ACLK = 0;
        forever #5 ACLK = ~ACLK; // 100 MHz
    end

    initial begin
        CORE_CLK = 0;
        // CORE_CLK at 75 MHz (non-integer ratio to ACLK)
        forever #(1000.0/150.0/2) CORE_CLK = ~CORE_CLK;
    end

    // Reset sequence
    initial begin
        ARESETn = 0;
        CORE_RESETn = 0;
        #20;
        ARESETn = 1;
        CORE_RESETn = 1;
    end

    // Instantiate DUT
    axi4lite_slave_top #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .FIFO_DEPTH(8)
    ) dut (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .AWADDR(AWADDR),
        .AWVALID(AWVALID),
        .AWREADY(AWREADY),
        .WDATA(WDATA),
        .WSTRB(WSTRB),
        .WVALID(WVALID),
        .WREADY(WREADY),
        .BRESP(BRESP),
        .BVALID(BVALID),
        .BREADY(BREADY),
        .ARADDR(ARADDR),
        .ARVALID(ARVALID),
        .ARREADY(ARREADY),
        .RDATA(RDATA),
        .RRESP(RRESP),
        .RVALID(RVALID),
        .RREADY(RREADY),
        .CORE_CLK(CORE_CLK),
        .CORE_RESETn(CORE_RESETn)
    );

    // Test sequence
    initial begin
        // Initialize signals
        AWADDR = '0;
        AWVALID = 0;
        WDATA = '0;
        WSTRB = '0;
        WVALID = 0;
        BREADY = 1; // always ready to accept response
        ARADDR = '0;
        ARVALID = 0;
        RREADY = 1; // always ready to accept read data

        // Wait for reset deassertion
        wait(ARESETn);
        @(posedge ACLK);
        $display("Reset deasserted at time %0t", $time);

        // Test 1: Write to register 0
        $display("Test 1: Writing 32'hA5A5A5A5 to register 0");
        @(posedge ACLK);
        AWADDR = 32'h0; // register 0
        WDATA = 32'hA5A5A5A5;
        WSTRB = 4'hF; // all bytes
        AWVALID = 1;
        WVALID = 1;
        wait(AWREADY && WREADY);
        @(posedge ACLK);
        AWVALID = 0;
        WVALID = 0;
        $display("Write accepted, waiting for response...");
        wait(BVALID);
        @(posedge ACLK);
        BREADY = 0;
        @(posedge ACLK);
        BREADY = 1;
        $display("Write response received at time %0t", $time);

        // Test 2: Write to register 4 (word-aligned)
        $display("Test 2: Writing 32'h12345678 to register 4");
        @(posedge ACLK);
        AWADDR = 32'h10; // register 4 (0x10 byte address)
        WDATA = 32'h12345678;
        WSTRB = 4'hF;
        AWVALID = 1;
        WVALID = 1;
        wait(AWREADY && WREADY);
        @(posedge ACLK);
        AWVALID = 0;
        WVALID = 0;
        wait(BVALID);
        @(posedge ACLK);
        BREADY = 0;
        @(posedge ACLK);
        BREADY = 1;

        // Test 3: Write to register 15 with byte strobe
        $display("Test 3: Writing 32'hF0F0F0F0 to register 15, bytes 1-2");
        @(posedge ACLK);
        AWADDR = 32'h3C; // register 15 (0x3C byte address)
        WDATA = 32'hF0F0F0F0;
        WSTRB = 4'h6; // bytes 1-2 (bits 15:8 and 23:16)
        AWVALID = 1;
        WVALID = 1;
        wait(AWREADY && WREADY);
        @(posedge ACLK);
        AWVALID = 0;
        WVALID = 0;
        wait(BVALID);
        @(posedge ACLK);
        BREADY = 0;
        @(posedge ACLK);
        BREADY = 1;

        // Test 4: Back-to-back writes
        $display("Test 4: Back-to-back writes to registers 1 and 2");
        @(posedge ACLK);
        // First write
        AWADDR = 32'h4;  // register 1
        WDATA = 32'hDEADBEEF;
        WSTRB = 4'hF;
        AWVALID = 1;
        WVALID = 1;
        wait(AWREADY && WREADY);
        @(posedge ACLK);
        // Second write (first write still in progress)
        AWADDR = 32'h8;  // register 2
        WDATA = 32'hCAFEBABE;
        WSTRB = 4'hF;
        // Keep first write valid until accepted
        wait(AWREADY && WREADY);
        @(posedge ACLK);
        AWVALID = 0;
        WVALID = 0;
        // Wait for both responses
        wait(BVALID);
        @(posedge ACLK);
        BREADY = 0;
        @(posedge ACLK);
        BREADY = 1;
        wait(BVALID);
        @(posedge ACLK);
        BREADY = 0;
        @(posedge ACLK);
        BREADY = 1;

        // Test 5: Read back what we wrote to verify
        $display("Test 5: Read back written data");
        // Read register 0 (should be A5A5A5A5)
        @(posedge ACLK);
        ARADDR = 32'h0;
        ARVALID = 1;
        wait(ARREADY);
        @(posedge ACLK);
        ARVALID = 0;
        wait(RVALID);
        @(posedge ACLK);
        if (RDATA === 32'hA5A5A5A5) begin
            $display("Read from reg 0: OK (got %h)", RDATA);
        end else begin
            $display("Read from reg 0: ERROR (got %h, expected A5A5A5A5)", RDATA);
        end
        @(posedge ACLK);
        if (RVALID) begin
            RREADY = 0;
            @(posedge ACLK);
            RREADY = 1;
        end

        // Read register 4 (should be 12345678)
        @(posedge ACLK);
        ARADDR = 32'h10; // register 4
        ARVALID = 1;
        wait(ARREADY);
        @(posedge ACLK);
        ARVALID = 0;
        wait(RVALID);
        @(posedge ACLK);
        if (RDATA === 32'h12345678) begin
            $display("Read from reg 4: OK (got %h)", RDATA);
        end else begin
            $display("Read from reg 4: ERROR (got %h, expected 12345678)", RDATA);
        end
        @(posedge ACLK);
        if (RVALID) begin
            RREADY = 0;
            @(posedge ACLK);
            RREADY = 1;
        end

        // Read register 15 (should have F0F0 in bytes 1-2, rest 0)
        @(posedge ACLK);
        ARADDR = 32'h3C; // register 15
        ARVALID = 1;
        wait(ARREADY);
        @(posedge ACLK);
        ARVALID = 0;
        wait(RVALID);
        @(posedge ACLK);
        // Expected: bytes 1-2 = F0F0, bytes 0 and 3 = 00 (since we only wrote bytes 1-2)
        // So: 00F0F000
        if (RDATA === 32'h00F0F000) begin
            $display("Read from reg 15: OK (got %h)", RDATA);
        end else begin
            $display("Read from reg 15: ERROR (got %h, expected 00F0F000)", RDATA);
        end
        @(posedge ACLK);
        if (RVALID) begin
            RREADY = 0;
            @(posedge ACLK);
            RREADY = 1;
        end

        // Test 6: Back-to-back write then read same address (check for CDC race)
        $display("Test 6: Write then read same address immediately");
        // Write to register 8
        @(posedge ACLK);
        AWADDR = 32'h20; // register 8
        WDATA = 32'h11223344;
        WSTRB = 4'hF;
        AWVALID = 1;
        WVALID = 1;
        wait(AWREADY && WREADY);
        @(posedge ACLK);
        AWVALID = 0;
        WVALID = 0;
        wait(BVALID);
        @(posedge ACLK);
        BREADY = 0;
        @(posedge ACLK);
        BREADY = 1;
        // Now immediately read it back
        @(posedge ACLK);
        ARADDR = 32'h20; // register 8
        ARVALID = 1;
        wait(ARREADY);
        @(posedge ACLK);
        ARVALID = 0;
        wait(RVALID);
        @(posedge ACLK);
        if (RDATA === 32'h11223344) begin
            $display("Write-then-read same addr: OK (got %h)", RDATA);
        end else begin
            $display("Write-then-read same addr: ERROR (got %h, expected 11223344)", RDATA);
        end
        @(posedge ACLK);
        if (RVALID) begin
            RREADY = 0;
            @(posedge ACLK);
            RREADY = 1;
        end

        $display("All tests completed at time %0t", $time);
        #100;
        $finish;
    end

    // Simple monitor
    initial begin
        $display("Monitor: ACLK=%0t CORE_CLK=%0t", $time, $time);
        forever begin
            @(posedge ACLK);
            if (AWVALID && AWREADY && WVALID && WREADY) begin
                $display("Write transaction: addr=%h data=%h strb=%h", AWADDR, WDATA, WSTRB);
            end
            if (BVALID && BREADY) begin
                $display("Write response: resp=%h", BRESP);
            end
            if (ARVALID && ARREADY) begin
                $display("Read transaction: addr=%h", ARADDR);
            end
            if (RVALID && RREADY) begin
                $display("Read response: data=%h resp=%h", RDATA, RRESP);
            end
        end
    end

    // Waveform dump
    initial begin
        $dumpfile("tb_axi4lite_slave_top.vcd");
        $dumpvars(0, tb_axi4lite_slave_top);
    end

endmodule