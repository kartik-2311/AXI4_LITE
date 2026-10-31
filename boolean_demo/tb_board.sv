`timescale 1ns/1ps
module tb_board;
    reg clk=0,reset_button=1;
    always #5 clk=~clk;
    wire [2:0] led;
    axi_boolean_top dut(.*);
    always @(posedge dut.axi_release[2]) if(dut.aclk!==1) $fatal(1,"ACLK reset release off-edge");
    always @(posedge dut.core_release[2]) if(dut.core_clk!==1) $fatal(1,"CORE reset release off-edge");
    initial begin
        #203;reset_button=0;
        wait(dut.locked);wait(dut.demo.state==3);
        #2;reset_button=1;#1;
        if(dut.axi_release!==0 || dut.core_release!==0 || led[0] || led[1]) $fatal(1,"Joint asynchronous reset failed");
        #103;reset_button=0;
        wait(led[0] || led[1]);if(led[1]) $fatal(1,"Board sweep failed");
        #2;force dut.locked=0;#1;
        if(dut.axi_release!==0 || dut.core_release!==0) $fatal(1,"Lost-lock reset failed");
        #100;release dut.locked;
        wait(led[0] || led[1]);if(led[1]) $fatal(1,"Lost-lock restart failed");
        $display("PASS UNISIM MMCM/BUFG, reset button, lost lock, synchronized releases, board sweeps");$finish;
    end
    initial begin #1000000;$fatal(1,"Board simulation timeout");end
endmodule
