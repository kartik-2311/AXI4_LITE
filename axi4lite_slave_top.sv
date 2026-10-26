`timescale 1ns/1ps

// AXI4-Lite Slave with CDC FIFO bridge (Write and Read Paths)
// ACLK domain: AXI4-Lite interface
// CORE_CLK domain: register bank
// Uses async_fifo for CDC

module axi4lite_slave_top #(
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 32,
    parameter AXI_STRB_WIDTH = AXI_DATA_WIDTH/8,
    // FIFO depth (must be power of two)
    parameter FIFO_DEPTH = 8,
    // Derive FIFO address width from depth
    localparam FIFO_ADDR_WIDTH = $clog2(FIFO_DEPTH)
)(
    // AXI4-Lite signals (ACLK domain)
    input  wire                    ACLK,
    input  wire                    ARESETn, // active-low reset
    // Write address channel
    input  wire [AXI_ADDR_WIDTH-1:0] AWADDR,
    input  wire                    AWVALID,
    output wire                    AWREADY,
    // Write data channel
    input  wire [AXI_DATA_WIDTH-1:0] WDATA,
    input  wire [AXI_STRB_WIDTH-1:0] WSTRB,
    input  wire                    WVALID,
    output wire                    WREADY,
    // Write response channel
    output wire [1:0]              BRESP,
    output wire                    BVALID,
    input  wire                    BREADY,
    // Read address channel
    input  wire [AXI_ADDR_WIDTH-1:0] ARADDR,
    input  wire                    ARVALID,
    output wire                    ARREADY,
    // Read data channel
    output wire [AXI_DATA_WIDTH-1:0] RDATA,
    output wire [1:0]              RRESP,
    output wire                    RVALID,
    input  wire                    RREADY,

    // Core clock domain signals
    input  wire                    CORE_CLK,
    input  wire                    CORE_RESETn // active-low reset for core domain
);

    // ----------------------------------------------------------------
    // Write channel: ACLK -> CORE_CLK via packed FIFO
    // Packed word: {AWADDR, WDATA, WSTRB}
    // ----------------------------------------------------------------
    localparam WRITE_FIFO_WIDTH = AXI_ADDR_WIDTH + AXI_DATA_WIDTH + AXI_STRB_WIDTH;
    logic                     wr_en;
    logic                     wr_full;
    logic [WRITE_FIFO_WIDTH-1:0] wr_data_in;
    logic [WRITE_FIFO_WIDTH-1:0] wr_data_out;
    logic                     wr_empty;

    // Write FIFO (async_fifo) from ACLK to CORE_CLK
    async_fifo #(
        .DATA_WIDTH(WRITE_FIFO_WIDTH),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) u_write_fifo (
        .wr_clk(ACLK),
        .wr_rst_n(ARESETn),
        .wr_en(wr_en),
        .wr_data(wr_data_in),
        .wr_full(wr_full),
        .rd_clk(CORE_CLK),
        .rd_rst_n(CORE_RESETn),
        .rd_en(1'b1), // core side will read when not empty via register bank logic
        .rd_data(wr_data_out),
        .rd_empty(wr_empty)
    );

    // ----------------------------------------------------------------
    // Read request: ACLK -> CORE_CLK (address only)
    // ----------------------------------------------------------------
    logic                     rd_req_en;
    logic                     rd_req_full;
    logic [AXI_ADDR_WIDTH-1:0] rd_req_addr_in;
    logic [AXI_ADDR_WIDTH-1:0] rd_req_addr_out;
    logic                     rd_req_empty;

    async_fifo #(
        .DATA_WIDTH(AXI_ADDR_WIDTH),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) u_read_req_fifo (
        .wr_clk(ACLK),
        .wr_rst_n(ARESETn),
        .wr_en(rd_req_en),
        .wr_data(rd_req_addr_in),
        .wr_full(rd_req_full),
        .rd_clk(CORE_CLK),
        .rd_rst_n(CORE_RESETn),
        .rd_en(1'b1), // core side reads when not empty
        .rd_data(rd_req_addr_out),
        .rd_empty(rd_req_empty)
    );

    // ----------------------------------------------------------------
    // Read response: CORE_CLK -> ACLK (data)
    // ----------------------------------------------------------------
    // We'll pack data and response into one FIFO word for simplicity
    localparam READ_FIFO_WIDTH = AXI_DATA_WIDTH + 2; // [DATA_WIDTH-1:0] data, [1:0] resp
    logic [READ_FIFO_WIDTH-1:0] rd_resp_word_in;
    logic [READ_FIFO_WIDTH-1:0] rd_resp_word_out;
    logic                     rd_resp_en;
    logic                     rd_resp_full;
    logic                     rd_resp_empty;

    async_fifo #(
        .DATA_WIDTH(READ_FIFO_WIDTH),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) u_read_resp_fifo (
        .wr_clk(CORE_CLK),
        .wr_rst_n(CORE_RESETn),
        .wr_en(rd_resp_en),
        .wr_data(rd_resp_word_in),
        .wr_full(rd_resp_full),
        .rd_clk(ACLK),
        .rd_rst_n(ARESETn),
        .rd_en(1'b1), // ACLK side reads when not empty
        .rd_data(rd_resp_word_out),
        .rd_empty(rd_resp_empty)
    );

    // ----------------------------------------------------------------
    // Write Channel FSM (ACLK domain)
    // ----------------------------------------------------------------
    typedef enum logic [1:0] {IDLE, PUSH_WAIT, WAIT_CORE, SEND_BRESP} write_state_t;
    write_state_t write_state, write_state_next;

    // AWVALID and WVALID must both be high to accept transaction (v1)
    assign wr_en = (write_state == PUSH_WAIT) && !wr_full;
    assign wr_data_in = {AWADDR, WDATA, WSTRB};

    // AWREADY and WREADY: both accepted when we can push
    assign AWREADY = (write_state == IDLE) && !wr_full && WVALID;
    assign WREADY  = (write_state == IDLE) && !wr_full && AWVALID;

    // BRESP is always OKAY for now
    assign BRESP = 2'b00;
    assign BVALID = (write_state == SEND_BRESP);
    // We need a write-complete signal from core side (synchronized to ACLK)

    // ----------------------------------------------------------------
    // Write-complete handshake from core side (synchronized)
    // ----------------------------------------------------------------
    logic write_done_core;    // level in CORE_CLK domain when write data available
    logic write_done_aclk;    // synchronized to ACLK domain

    // 2-flop synchronizer for write_done_core -> ACLK
    sync_2ff #(
        .WIDTH(1)
    ) u_write_done_sync (
        .clk(ACLK),
        .rst_n(ARESETn),
        .d_in(write_done_core),
        .q_out(write_done_aclk)
    );

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            write_state <= IDLE;
        end else begin
            write_state <= write_state_next;
        end
    end

    always_comb begin
        write_state_next = write_state;
        case (write_state)
            IDLE: begin
                if (AWVALID && WVALID && !wr_full) begin
                    write_state_next = PUSH_WAIT;
                end
            end
            PUSH_WAIT: begin
                // After pushing, wait for core to receive
                write_state_next = WAIT_CORE;
            end
            WAIT_CORE: begin
                // Wait for core to complete write
                if (write_done_aclk) begin
                    write_state_next = SEND_BRESP;
                end
            end
            SEND_BRESP: begin
                if (BREADY) begin
                    write_state_next = IDLE;
                end
            end
            default: write_state_next = IDLE;
        endcase
    end

    // ----------------------------------------------------------------
    // Read Channel FSM (ACLK domain)
    // ----------------------------------------------------------------
    typedef enum logic [1:0] {RD_IDLE, RD_SEND_ADDR, RD_WAIT_DATA} read_state_t;
    read_state_t read_state, read_state_next;

    assign rd_req_en = (read_state == RD_SEND_ADDR) && !rd_req_full;
    assign rd_req_addr_in = ARADDR;

    assign ARREADY = (read_state == RD_IDLE) && !rd_req_full && ARVALID;

    // Read data path
    assign {RDATA, RRESP} = rd_resp_word_out;
    assign RVALID = (read_state == RD_WAIT_DATA) && !rd_resp_empty;
    // RREADY handled by FIFO read enable (always 1 when not empty)

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            read_state <= RD_IDLE;
        end else begin
            read_state <= read_state_next;
        end
    end

    always_comb begin
        read_state_next = read_state;
        case (read_state)
            RD_IDLE: begin
                if (ARVALID && !rd_req_full) begin
                    read_state_next = RD_SEND_ADDR;
                end
            end
            RD_SEND_ADDR: begin
                // After sending address, wait for data
                read_state_next = RD_WAIT_DATA;
            end
            RD_WAIT_DATA: begin
                if (!rd_resp_empty && RREADY) begin
                    read_state_next = RD_IDLE;
                end
            end
            default: read_state_next = RD_IDLE;
        endcase
    end

    // ----------------------------------------------------------------
    // Core-side logic (CORE_CLK domain)
    // ----------------------------------------------------------------
    // Register bank: simple 32-bit registers, decode lower address bits
    localparam NUM_REGS = 16;
    logic [AXI_DATA_WIDTH-1:0] reg_file [NUM_REGS];
    integer i;

    // Write data path from write FIFO
    logic [AXI_ADDR_WIDTH-1:0] wr_addr_core;
    logic [AXI_DATA_WIDTH-1:0] wr_data_core;
    logic [AXI_STRB_WIDTH-1:0] wr_strb_core;

    assign {wr_addr_core, wr_data_core, wr_strb_core} = wr_data_out;

    // Read request path
    logic [AXI_ADDR_WIDTH-1:0] rd_addr_core;
    assign rd_addr_core = rd_req_addr_out;

    // Read response path
    logic [AXI_DATA_WIDTH-1:0] rd_data_core;
    logic [1:0]               rd_resp_core;

    // Write-complete signal to ACLK side (level when FIFO has data)
    assign write_done_core = !wr_empty; // level: high when FIFO not empty

    always_ff @(posedge CORE_CLK or negedge CORE_RESETn) begin
        if (!CORE_RESETn) begin
            for (i = 0; i < NUM_REGS; i++) begin
                reg_file[i] <= '0;
            end
            rd_resp_en <= 1'b0; // default: don't write to read response FIFO
        end else begin
            // Handle write (when FIFO not empty)
            if (!wr_empty) begin
                // Decode register index (assuming word-aligned, lower 2 bits zero for 32-bit)
                // We'll use the lowest bits that can index NUM_REGS
                localparam REG_IDX_WIDTH = $clog2(NUM_REGS);
                logic [REG_IDX_WIDTH-1:0] reg_idx;
                // Use bits [2+:REG_IDX_WIDTH] of address (assuming byte address, word-aligned)
                reg_idx = wr_addr_core[2 +: REG_IDX_WIDTH];
                // Write with strobe
                for (i = 0; i < AXI_STRB_WIDTH; i++) begin
                    if (wr_strb_core[i]) begin
                        reg_file[reg_idx][i*8 +: 8] <= wr_data_core[i*8 +: 8];
                    end
                end
                rd_resp_en <= 1'b0; // not processing a read request
            end
            // Handle read request
            else if (!rd_req_empty) begin
                logic [$clog2(NUM_REGS)-1:0] reg_idx;
                reg_idx = rd_addr_core[$clog2(NUM_REGS)+1:2];
                rd_data_core <= reg_file[reg_idx];
                rd_resp_core <= 2'b00; // OKAY
                rd_resp_en <= 1'b1; // push read response to FIFO
            end
            else begin
                rd_resp_en <= 1'b0; // default: don't write to read response FIFO
            end
        end
    end

    // Drive the read response FIFO input word
    assign rd_resp_word_in = {rd_data_core, rd_resp_core};

    // ----------------------------------------------------------------
    // SVA Assertions for AXI4-Lite Protocol Compliance
    // ----------------------------------------------------------------
    // NOTE: Assertions are ignored in synthesis (synthesizable when using proper tools)
    // These are for simulation/verification only, conditionally compiled
    // since Icarus Verilog does not yet fully support concurrent assertions or $stable.

`ifndef __ICARUS__
    // Write address channel: AWVALID and AWADDR must be stable until AWREADY
    aw_addr_stable_aw: assert property (@(posedge ACLK) disable iff (!ARESETn)
        (AWVALID && !AWREADY) |=> ($stable(AWADDR) && $stable(AWVALID)))
        else $error("AWADDR changed while AWVALID high and AWREADY low");

    // Write data channel: WVALID and WDATA/WSTRB must be stable until WREADY
    w_data_stable_w: assert property (@(posedge ACLK) disable iff (!ARESETn)
        (WVALID && !WREADY) |=> ($stable(WDATA) && $stable(WSTRB) && $stable(WVALID)))
        else $error("WDATA or WSTRB changed while WVALID high and WREADY low");

    // Write response channel: BRESP must be stable until BREADY when BVALID is high
    b_resp_stable_b: assert property (@(posedge ACLK) disable iff (!ARESETn)
        (BVALID && !BREADY) |=> ($stable(BRESP) && $stable(BVALID)))
        else $error("BRESP changed while BVALID high and BREADY low");

    // Read address channel: ARVALID and ARADDR must be stable until ARREADY
    ar_addr_stable_ar: assert property (@(posedge ACLK) disable iff (!ARESETn)
        (ARVALID && !ARREADY) |=> ($stable(ARADDR) && $stable(ARVALID)))
        else $error("ARADDR changed while ARVALID high and ARREADY low");

    // Read data channel: RDATA and RRESP must be stable until RREADY when RVALID is high
    r_data_stable_r: assert property (@(posedge ACLK) disable iff (!ARESETn)
        (RVALID && !RREADY) |=> ($stable(RDATA) && $stable(RRESP) && $stable(RVALID)))
        else $error("RDATA or RRESP changed while RVALID high and RREADY low");

    // FIFO safety: No push when full
    assert property (@(posedge ACLK) disable iff (!ARESETn)
        wr_en |-> !wr_full)
        else $error("Write FIFO push attempted when full");

    assert property (@(posedge ACLK) disable iff (!ARESETn)
        rd_req_en |-> !rd_req_full)
        else $error("Read request FIFO push attempted when full");

    assert property (@(posedge CORE_CLK) disable iff (!CORE_RESETn)
        rd_resp_en |-> !rd_resp_full)
        else $error("Read response FIFO push attempted when full");
`endif

endmodule