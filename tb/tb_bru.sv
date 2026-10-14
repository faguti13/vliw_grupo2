// Testbench del BRU: condiciones, destino relativo al sig bundle
// SYE/SRG/FIN.

/* Comandos necesarios para su prueba
# compilar
iverilog -g2012 -o tb_bru.vvp rtl/bru.sv tb/tb_bru.sv

# simular
vvp tb_bru.vvp
*/
module tb_bru;
  // Señales conectadas al modulo por nombre
  logic [31:0] instr, pc, a, b, target, link_val; 
  logic taken, link_wen, fin, illegal;

  bru dut (.*);
  integer errs = 0;

  // Arma una instr condicional 
  // {offset(15), rs1(5), rs2(5), funct(4), opcode=011}
  function automatic [31:0] cond(input [3:0] f, input [14:0] off, input [4:0] rs1, rs2);
    cond = {off, rs1, rs2, f, 3'b011};
  endfunction

  // Arma una instrucción incondicional:
  // {offset(25), funct(4), opcode=011}
  function automatic [31:0] jmp(input [3:0] f, input [24:0] off);
    jmp = {off, f, 3'b011};
  endfunction

  // Se revisa taken y si se toma, se revisa tambien destino.
  task automatic chk(input string n, input exp_taken, input [31:0] exp_t);
    #1; if (taken !== exp_taken || (exp_taken && target !== exp_t)) begin errs++; $display("FAIL %s taken=%b t=%h", n, taken, target); end
  endtask

  initial begin
    pc = 32'h100; a = 5; b = 5;
    // SIG: a == b, se toma
    instr = cond(4'd0, 15'd2, 1, 2);  chk("SIG", 1, 32'h100 + 16 + 32);
    
    // SNIG: a == b, no se toma
    instr = cond(4'd1, 15'd2, 1, 2);  chk("SNIG no", 0, 0);
    
    a = 3; b = 9;

    // SNIG: a != b, se toma
    instr = cond(4'd1, 15'h7FFF, 1, 2); chk("SNIG -1", 1, 32'h100);       // destino = PC+16-16
    
    // SMI: a < b, no se toma
    instr = cond(4'd2, 15'd1, 1, 2);  chk("SMI no", 0, 0);

    // SMQ: a < b, se toma
    instr = cond(4'd3, 15'd1, 1, 2);  chk("SMQ", 1, 32'h120);
    a = 32'hFFFFFFFF; b = 1;

    // SMQ con signo: 0xFFFFFFFF (-1) < 1, se toma
    instr = cond(4'd3, 15'd1, 1, 2);  chk("SMQ signo", 1, 32'h120);
    
    // S: salto incondicional
    instr = jmp(4'd4, 25'd3);         chk("S", 1, 32'h100 + 16 + 48);
    
    // SYE: salto incondicional con enlace. Mismo destino que S.
    instr = jmp(4'd5, 25'd3);         chk("SYE", 1, 32'h100 + 16 + 48);

    // SYE también debe activar link_wen y dejar link_val = 0x110
    if (!link_wen || link_val !== 32'h110) begin errs++; $display("FAIL SYE enlace"); end
    
    // SRG: retorno. Salta a la dirección en rs1 (a = 0x2000), alineada a bundle.
    a = 32'h2000; instr = {15'd0, 5'd1, 5'd0, 4'd6, 3'b011}; chk("SRG", 1, 32'h2000);
    
    // FIN: halt. No debe tomar salto.
    instr = 32'h0000003B; #1; if (!fin || taken) begin errs++; $display("FAIL FIN"); end
    
    // NOP del BRU (no toma, no termina, no es ilegal)
    instr = 32'h0000007B; #1; if (taken || fin || illegal) begin errs++; $display("FAIL NOP"); end
    
    // Resultado final
    if (errs == 0) $display("tb_bru: PASS"); else begin $display("tb_bru: FAIL"); $fatal(1); end
    $finish;
  end
endmodule
