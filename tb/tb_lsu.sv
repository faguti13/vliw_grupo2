// tb_lsu.sv - LSU: direccion efectiva base+offset con signo, CP/AP.

module tb_lsu;
  logic [31:0] instr, base, store_v, mem_rdata, addr, mem_wdata, y; logic mem_we, wen, illegal; logic [4:0] rd;
  lsu dut (.*);
  integer errs = 0;
  function automatic [31:0] enc(input [3:0] f, input [4:0] rb, input [14:0] imm, input [4:0] rdx);
    enc = {imm[14], rb, imm[13:0], rdx, f, 3'b010};
  endfunction
  initial begin
    base = 32'h1000; store_v = 32'hDEADBEEF; mem_rdata = 32'h11223344;
    instr = enc(4'b0000, 1, 15'd8, 4); #1;
    if (addr !== 32'h1008 || !wen || mem_we || y !== 32'h11223344 || rd !== 4) begin errs++; $display("FAIL CP"); end
    instr = enc(4'b0001, 1, 15'h7FFC, 5); #1;   // offset -4
    if (addr !== 32'h0FFC || wen || !mem_we || mem_wdata !== 32'hDEADBEEF) begin errs++; $display("FAIL AP"); end
    instr = enc(4'b1111, 1, 15'd0, 0); #1;
    if (wen || mem_we) begin errs++; $display("FAIL NOP"); end
    if (errs == 0) $display("tb_lsu: PASS"); else begin $display("tb_lsu: FAIL"); $fatal(1); end
    $finish;
  end
endmodule
