// tb_regfile.sv - Banco de registros: r0 fijo, escrituras por puerto y prioridad.

module tb_regfile;
  logic clk = 0, rst = 1; logic [39:0] raddr; logic [255:0] rdata;
  logic [4:0] wen; logic [24:0] waddr; logic [159:0] wdata;
  regfile dut (.*);
  always #5 clk = ~clk;
  integer errs = 0;
  task automatic expect32(input [31:0] got, input [31:0] exp, input string n);
    if (got !== exp) begin errs = errs + 1; $display("FAIL %s: %h (esp %h)", n, got, exp); end
  endtask
  initial begin
    wen = 0; waddr = 0; wdata = 0; raddr = 0;
    repeat (2) @(posedge clk); rst = 0;
    // escribe r0 (ignorado), r5 y r6 en puertos 0,1
    wen = 5'b00011; waddr = {15'd0, 5'd6, 5'd0}; wdata = {96'h0, 32'hAAAA0006, 32'h12345678};
    @(posedge clk); #1; wen = 0;
    raddr = {25'd0, 5'd6, 5'd0, 5'd0, 5'd0}; #1;
    expect32(rdata[31:0], 32'h0, "r0 siempre 0");
    // lee r6 en el puerto 3
    raddr = {20'd0, 5'd6, 15'd0}; #1; expect32(rdata[127:96], 32'hAAAA0006, "r6");
    // prioridad: puertos 0 y 4 escriben r9, gana el 4
    wen = 5'b10001; waddr = {5'd9, 15'd0, 5'd9}; wdata = {32'hBBBB0004, 96'h0, 32'hAAAA0000};
    @(posedge clk); #1; wen = 0;
    raddr = {35'd0, 5'd9}; #1; expect32(rdata[31:0], 32'hBBBB0004, "prioridad");
    if (errs == 0) $display("tb_regfile: PASS"); else begin $display("tb_regfile: FAIL (%0d)", errs); $fatal(1); end
    $finish;
  end
endmodule
