module tb;
    logic clk, rst, a, b;
    always_ff @(posedge clk) begin
        if (rst) begin
            if ($past(a)) begin
                assert ($stable(b)) else $error("fail");
            end
        end
    end
endmodule
