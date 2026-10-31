`timescale 1ns/1ps
module axi_board_demo #(parameter WATCHDOG_BITS=24)(
    input wire aclk,core_clk,aresetn,core_resetn,
    output reg passed=0,failed=0
);
    localparam WRITE=0,WAIT_B=1,READ=2,WAIT_R=3,CHECK=4,STOP=5;
    reg [2:0] state=WRITE,operation=0;
    reg [3:0] index=0;
    reg [31:0] sweep=0;
    reg [31:0] model[0:15];
    reg [31:0] received;
    reg [1:0] received_resp;
    reg aw_done=0,w_done=0;
    reg [5:0] delay_count=0;
    reg [WATCHDOG_BITS-1:0] watchdog=0;
    wire [31:0] address={26'b0,index,2'b0};
    wire [31:0] write_address=operation==3 ? 32'h40 : (operation==4 ? address|1 : address);
    wire [31:0] write_data=(32'ha5c35a00 ^ sweep ^ {28'b0,index}) ^ (operation==1 ? 32'hffffffff : 0);
    wire [3:0] strobes=operation==2 ? 0 : (operation==1 ? 5 : 15);
    wire awvalid=state==WRITE && !aw_done && (index%3!=1 || delay_count>=12);
    wire wvalid=state==WRITE && !w_done && (index%3!=2 || delay_count>=12);
    wire awready,wready,bvalid,arready,rvalid;
    wire [1:0] bresp,rresp;
    wire [31:0] rdata;
    wire bready=state==WAIT_B && delay_count==63;
    wire rready=state==WAIT_R && delay_count==63;
    axi_demo_endpoint endpoint(.ACLK(aclk),.ARESETn(aresetn),.CORE_CLK(core_clk),.CORE_RESETn(core_resetn),
        .AWADDR(write_address),.AWVALID(awvalid),.AWREADY(awready),.WDATA(write_data),.WSTRB(strobes),
        .WVALID(wvalid),.WREADY(wready),.BRESP(bresp),.BVALID(bvalid),.BREADY(bready),
        .ARADDR(operation==3 ? 32'h40 : (operation==4 ? address|1 : address)),
        .ARVALID(state==READ),.ARREADY(arready),.RDATA(rdata),.RRESP(rresp),.RVALID(rvalid),.RREADY(rready));
    integer lane,slot;
    always @(posedge aclk or negedge aresetn) begin
        if(!aresetn) begin
            passed<=0;failed<=0;state<=WRITE;operation<=0;index<=0;sweep<=0;
            aw_done<=0;w_done<=0;delay_count<=0;watchdog<=0;received<=0;received_resp<=0;
            for(slot=0;slot<16;slot=slot+1) model[slot]<=0;
        end else begin
            watchdog<=watchdog+1'b1;
            if(&watchdog) begin failed<=1;state<=STOP;end
            else case(state)
                WRITE: begin
                    if(delay_count!=63) delay_count<=delay_count+1'b1;
                    if(awvalid && awready) aw_done<=1;
                    if(wvalid && wready) w_done<=1;
                    if((aw_done || (awvalid && awready)) && (w_done || (wvalid && wready))) begin
                        state<=WAIT_B;delay_count<=0;watchdog<=0;
                    end
                end
                WAIT_B: begin
                    if(delay_count!=63) delay_count<=delay_count+1'b1;
                    if(bvalid && bready) begin
                        watchdog<=0;
                        if(bresp!==(operation>=3 ? 2'b10 : 2'b00)) begin failed<=1;state<=STOP;end
                        else begin
                            if(operation<3) for(lane=0;lane<4;lane=lane+1)
                                if(strobes[lane]) model[index][lane*8+:8]<=write_data[lane*8+:8];
                            state<=READ;
                        end
                    end
                end
                READ: if(arready) begin state<=WAIT_R;delay_count<=0;watchdog<=0;end
                WAIT_R: begin
                    if(delay_count!=63) delay_count<=delay_count+1'b1;
                    if(rvalid && rready) begin received<=rdata;received_resp<=rresp;state<=CHECK;watchdog<=0;end
                end
                CHECK: begin
                    if(received_resp!==(operation>=3 ? 2'b10 : 2'b00) || received!==(operation>=3 ? 32'b0 : model[index])) begin
                        failed<=1;state<=STOP;
                    end else begin
                        if(operation==4) begin
                            operation<=0;index<=index+1'b1;
                            if(index==15) begin passed<=1;sweep<=sweep+1'b1;end
                        end else operation<=operation+1'b1;
                        state<=WRITE;aw_done<=0;w_done<=0;delay_count<=0;watchdog<=0;
                    end
                end
                default: state<=STOP;
            endcase
        end
    end
endmodule
