// tb_alu.sv - Prueba autoverificable de la ALU.
module tb_alu;
  logic [31:0] instr, a, b, y; logic wen, illegal; logic [4:0] rd;
  alu dut (.instr(instr), .a(a), .b(b), .wen(wen), .rd(rd), .y(y), .illegal(illegal));
  integer errs = 0;

  //Armar las instr de acuerdo al al formato del ISA
  function automatic [31:0] enc_r(input [3:0] f, input [4:0] rs1, rs2, rdx);
    enc_r = {10'b0, rs1, rs2, rdx, f, 3'b000};
  endfunction
  function automatic [31:0] enc_i(input [3:0] f, input [4:0] rs1, input [14:0] imm, input [4:0] rdx);
    enc_i = {imm[14], rs1, imm[13:0], rdx, f, 3'b001};
  endfunction

  task automatic chk(input string name, input [31:0] exp, input expwen);
    #1;
    if (y !== exp || wen !== expwen) begin
      errs = errs + 1; $display("FAIL %s: y=%h (esp %h) wen=%b", name, y, exp, wen);
    end
  endtask

  initial begin
    a = 32'd10; b = 32'd3; //a=10 y b=3
    instr = enc_r(4'd0, 1, 2, 3);  chk("SUM", 13, 1);
    instr = enc_r(4'd1, 1, 2, 3);  chk("REST", 7, 1);
    instr = enc_r(4'd2, 1, 2, 3);  chk("MUL", 30, 1);
    instr = enc_r(4'd3, 1, 2, 3);  chk("DIV", 3, 1);
    instr = enc_r(4'd4, 1, 2, 3);  chk("OLY", 2, 1);
    instr = enc_r(4'd5, 1, 2, 3);  chk("OLO", 11, 1);
    instr = enc_r(4'd6, 1, 2, 3);  chk("LOE", 9, 1);
    instr = enc_r(4'd7, 1, 2, 3);  chk("DLI", 80, 1);
    instr = enc_r(4'd8, 1, 2, 3);  chk("DLD", 1, 1);
    instr = enc_r(4'd9, 1, 2, 3);  chk("COMP a<b", 0, 1);
    a = 32'hFFFFFFFE; b = 32'd1;   // -2 < 1 con signo
    instr = enc_r(4'd9, 1, 2, 3);  chk("COMP signo", 1, 1);
    a = 32'd7; b = 32'd0;
    instr = enc_r(4'd3, 1, 2, 3);  chk("DIV/0", 32'hFFFFFFFF, 1);
    a = 32'hFFFFFFF9; b = 32'd2;   // -7/2 = -3 (trunca a cero)
    instr = enc_r(4'd3, 1, 2, 3);  chk("DIV signo", 32'hFFFFFFFD, 1);
    instr = enc_r(4'b1111, 1, 2, 3); chk("NOP", 0, 0);
    a = 32'd100;
    instr = enc_i(4'd0, 1, 15'd5, 3);        chk("SUMI", 105, 1);
    instr = enc_i(4'd0, 1, 15'h7FFF, 3);     chk("SUMI -1", 99, 1);
    instr = enc_i(4'd1, 1, 15'd1, 3);        chk("RESTI", 99, 1);
    instr = enc_i(4'd2, 1, 15'd3, 3);        chk("MULI", 300, 1);
    instr = enc_i(4'd3, 1, 15'd7, 3);        chk("DIVI", 14, 1);
    instr = enc_i(4'd4, 1, 15'd2, 3);        chk("DLII", 400, 1);
    instr = enc_i(4'd5, 1, 15'd2, 3);        chk("DLDI", 25, 1);
    instr = enc_i(4'd0, 1, 15'h4000, 3);     chk("SUMI -16384", 100 - 16384, 1);
    instr = enc_i(4'd9, 1, 15'd1, 3);        #1; if (!illegal) begin errs = errs + 1; $display("FAIL: funct invalido no marcado"); end
    if (errs == 0) $display("tb_alu: PASS"); else begin $display("tb_alu: FAIL (%0d)", errs); $fatal(1); end
    $finish;
  end
endmodule
