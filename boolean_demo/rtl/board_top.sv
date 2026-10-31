`timescale 1ns/1ps
module axi_boolean_top(input wire clk,reset_button,output wire [2:0] led);
    wire feedback,feedback_buf,axi_raw,core_raw,aclk,core_clk,locked;
    MMCME2_BASE #(.CLKIN1_PERIOD(10.0),.CLKFBOUT_MULT_F(6.0),.CLKOUT0_DIVIDE_F(6.0),.CLKOUT1_DIVIDE(8)) clocks(
        .CLKIN1(clk),.CLKFBIN(feedback_buf),.CLKFBOUT(feedback),.CLKOUT0(axi_raw),.CLKOUT1(core_raw),
        .LOCKED(locked),.RST(1'b0),.PWRDWN(1'b0));
    BUFG feedback_clock(.I(feedback),.O(feedback_buf));
    BUFG axi_clock(.I(axi_raw),.O(aclk));
    BUFG core_clock(.I(core_raw),.O(core_clk));
    wire reset_async=reset_button || !locked;
    (* ASYNC_REG="TRUE" *) reg [2:0] axi_release=0,core_release=0;
    always @(posedge aclk or posedge reset_async)
        if(reset_async) axi_release<=0;else axi_release<={axi_release[1:0],1'b1};
    always @(posedge core_clk or posedge reset_async)
        if(reset_async) core_release<=0;else core_release<={core_release[1:0],1'b1};
    reg [26:0] heartbeat=0;
    always @(posedge aclk) heartbeat<=heartbeat+1'b1;
    assign led[2]=heartbeat[26];
    axi_board_demo demo(.aclk(aclk),.core_clk(core_clk),.aresetn(axi_release[2]),.core_resetn(core_release[2]),
        .passed(led[0]),.failed(led[1]));
endmodule
