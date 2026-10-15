// tb_key_vault.sv - Boveda: escribir/leer 4x4 subllaves.
module tb_key_vault;
  logic clk = 0, we = 0; logic [1:0] wkey, wsub, rkey, rsub; logic [31:0] wdata, rdata;
  key_vault dut (.*);
  always #5 clk = ~clk;
  integer errs = 0, i, j;
  initial begin
    for (i = 0; i < 4; i++) for (j = 0; j < 4; j++) begin
      wkey = i; wsub = j; wdata = 32'h1000 * i + j + 1; we = 1; @(posedge clk); #1;
    end
    we = 0;
    for (i = 0; i < 4; i++) for (j = 0; j < 4; j++) begin
      rkey = i; rsub = j; #1;
      if (rdata !== 32'h1000 * i + j + 1) begin errs++; $display("FAIL vault[%0d][%0d]=%h", i, j, rdata); end
    end
    // sin we no se escribe
    wkey = 0; wsub = 0; wdata = 32'hFFFFFFFF; @(posedge clk); #1; rkey = 0; rsub = 0; #1;
    if (rdata !== 32'h1) begin errs++; $display("FAIL we=0 escribio"); end
    if (errs == 0) $display("tb_key_vault: PASS"); else begin $display("tb_key_vault: FAIL"); $fatal(1); end
    $finish;
  end
endmodule
