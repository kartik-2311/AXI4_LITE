module test;
  reg clk = 0;
  reg rst_n = 0;
  reg a = 0;
  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (rst_n) begin
      if (a) assert(a == $past(a));
    end
  end

  initial begin
    $dumpvars(0, test);
    #10 rst_n = 1;
    #10 a = 1;
    #10 a = 1;
    #10 a = 0;
    #10 $finish;
  end
endmodule
