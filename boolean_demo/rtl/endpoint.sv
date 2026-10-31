`timescale 1ns/1ps
module axi_demo_endpoint #(
    parameter AXI_ADDR_WIDTH=32, AXI_DATA_WIDTH=32, AXI_STRB_WIDTH=AXI_DATA_WIDTH/8,
    parameter FIFO_DEPTH=8, parameter [1:0] OOR_RESP=2, parameter STRICT_ALIGN=1
)(
    input wire ACLK, ARESETn, CORE_CLK, CORE_RESETn,
    input wire [AXI_ADDR_WIDTH-1:0] AWADDR, ARADDR,
    input wire AWVALID, WVALID, BREADY, ARVALID, RREADY,
    input wire [AXI_DATA_WIDTH-1:0] WDATA,
    input wire [AXI_STRB_WIDTH-1:0] WSTRB,
    output wire AWREADY,WREADY,BVALID,ARREADY,RVALID,
    output wire [1:0] BRESP,RRESP,
    output wire [AXI_DATA_WIDTH-1:0] RDATA
);
    reg aw_full=0,w_full=0,active=0;
    reg [AXI_ADDR_WIDTH-1:0] aw_saved;
    reg [AXI_DATA_WIDTH-1:0] w_saved;
    reg [AXI_STRB_WIDTH-1:0] strb_saved;
    wire slave_awready,slave_wready;
    wire pair_valid=aw_full && w_full && !active;
    assign AWREADY=ARESETn && !active && !aw_full;
    assign WREADY=ARESETn && !active && !w_full;
    always @(posedge ACLK or negedge ARESETn) begin
        if(!ARESETn) begin aw_full<=0; w_full<=0; active<=0; end
        else begin
            if(AWVALID && AWREADY) begin aw_saved<=AWADDR; aw_full<=1; end
            if(WVALID && WREADY) begin w_saved<=WDATA; strb_saved<=WSTRB; w_full<=1; end
            if(pair_valid && slave_awready && slave_wready) begin
                aw_full<=0; w_full<=0; active<=1;
            end
            if(BVALID && BREADY) active<=0;
        end
    end
    axi4lite_slave_top #(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),.AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_STRB_WIDTH(AXI_STRB_WIDTH),.FIFO_DEPTH(FIFO_DEPTH),.OOR_RESP(OOR_RESP),.STRICT_ALIGN(STRICT_ALIGN)) slave(
        .ACLK(ACLK),.ARESETn(ARESETn),.CORE_CLK(CORE_CLK),.CORE_RESETn(CORE_RESETn),
        .AWADDR(aw_saved),.AWVALID(pair_valid),.AWREADY(slave_awready),
        .WDATA(w_saved),.WSTRB(strb_saved),.WVALID(pair_valid),.WREADY(slave_wready),
        .BRESP(BRESP),.BVALID(BVALID),.BREADY(BREADY),.ARADDR(ARADDR),.ARVALID(ARVALID),
        .ARREADY(ARREADY),.RDATA(RDATA),.RRESP(RRESP),.RVALID(RVALID),.RREADY(RREADY));
endmodule
