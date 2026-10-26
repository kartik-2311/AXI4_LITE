`timescale 1ns/1ps
// Verification-only environment contract; joint assertion flushes both FIFO owners.
module axi4lite_reset_checker(
    input wire ACLK, CORE_CLK, ARESETn, CORE_RESETn
);
    realtime a_release_edge=0, core_release_edge=0;
    always @(negedge ACLK) a_release_edge=$realtime;
    always @(negedge CORE_CLK) core_release_edge=$realtime;
    always @(negedge ARESETn or negedge CORE_RESETn) begin
        #0;
        if(ARESETn!==1'b0 || CORE_RESETn!==1'b0)
            $fatal(1,"RESET_CONTRACT seed=41584934 joint assertion required");
    end
    // Falling-edge release is synchronous to each local clock and leaves a half cycle of recovery.
    always @(posedge ARESETn) begin
        #0;
        if(ACLK!==1'b0 || $realtime!=a_release_edge)
            $fatal(1,"RESET_CONTRACT seed=41584934 ACLK synchronous release required");
    end
    always @(posedge CORE_RESETn) begin
        #0;
        if(CORE_CLK!==1'b0 || $realtime!=core_release_edge)
            $fatal(1,"RESET_CONTRACT seed=41584934 CORE_CLK synchronous release required");
    end
endmodule
