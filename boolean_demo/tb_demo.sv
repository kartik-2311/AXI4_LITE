`timescale 1ns/1ps
module tb_demo;
    reg aclk=0,core_clk=0,aresetn=0,core_resetn=0;
    always #5 aclk=~aclk;
    always #(20.0/3.0) core_clk=~core_clk;
    wire passed,failed;
    axi_board_demo #(.WATCHDOG_BITS(12)) demo(.*);
    task reset;
        begin
            @(negedge aclk);aresetn=0;core_resetn=0;
            repeat(5) @(negedge aclk);
            fork
                begin @(negedge aclk);aresetn=1;end
                begin @(negedge core_clk);core_resetn=1;end
            join
        end
    endtask
    initial begin
        reset();wait(passed || failed);if(failed) $fatal(1,"normal sweep failed");
        wait(demo.state==3);reset();
        if(passed || failed) $fatal(1,"reset did not clear status");
        wait(passed || failed);if(failed) $fatal(1,"restart failed");
        @(negedge aclk);force demo.rdata=32'hdeadbeef;
        wait(failed);release demo.rdata;
        repeat(100) @(negedge aclk);if(!failed) $fatal(1,"FAIL not sticky");
        reset();@(negedge aclk);force demo.awready=0;
        wait(failed);release demo.awready;
        $display("PASS sweeps, partial writes, orderings, stalls, invalid access, reset, corruption, watchdog");$finish;
    end
    initial begin #3000000;$fatal(1,"timeout");end
endmodule
