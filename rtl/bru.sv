// Unidad de control de flujo(BRU) del procesador
// Vive en el slot 2 y su opcode es 011
// Su función es decidir si un salto se toma y calcula la dirección de destino
// SIG SNIG SMI SMQ (condicionales), S, SYE (call), SRG (ret), FIN (halt)
module bru (
  input  logic [31:0] instr,    // instr de 32 bits
  input  logic [31:0] pc,       // PC actual (apunta al bundle que se esta ejecutando)
  input  logic [31:0] a,        // GPR[rs1]
  input  logic [31:0] b,        // GPR[rs2]
  output logic        taken,    // 1 si el salto se toma
  output logic [31:0] target,   // dirección de destino de salto
  output logic        link_wen, // SYE escribe r31
  output logic [31:0] link_val, // valor de retorno para SYE
  output logic        fin,      // halt( fin del procesador-lo detiene)
  output logic        illegal   // instr invalida
);
  logic [3:0]  funct;           // selecciona la operacion dentro del opcode 011
  logic [31:0] off15, off25;    // offsets con signo para condicionales e incondicionales
  assign funct = instr[6:3];
  assign off15 = {{17{instr[31]}}, instr[31:17]}; //Offset de 15 bits con signo (para condicionales)
  assign off25 = {{7{instr[31]}}, instr[31:7]}; //Offset de 25 bits con signo(para incondicionales)
  assign link_val = pc + 32'd16; //Dirección de retorno para SYE- el bundle siguiente al actual

  always @* begin
    // Valores por defecto (no salta y el PC avanza al siguiente bundle)
    taken = 1'b0; target = pc + 32'd16; link_wen = 1'b0; fin = 1'b0; illegal = 1'b0;
    // Si el opcode no es 011, no es una inst del BRU
    if (instr[2:0] != 3'b011) illegal = 1'b1;
    else begin
      case (funct)
        // Saltos condicionales(comparan a y b, offset de 15 bits)
        4'b0000: begin taken = (a == b);                    target = pc + 32'd16 + (off15 << 4); end
        4'b0001: begin taken = (a != b);                    target = pc + 32'd16 + (off15 << 4); end
        4'b0010: begin taken = ($signed(a) >= $signed(b));  target = pc + 32'd16 + (off15 << 4); end
        4'b0011: begin taken = ($signed(a) <  $signed(b));  target = pc + 32'd16 + (off15 << 4); end
        // Salto incondicional (offset de 25 bits)
        4'b0100: begin taken = 1'b1;                        target = pc + 32'd16 + (off25 << 4); end
        // SYE (salta y guarda la dirección de retorno de r31)
        4'b0101: begin taken = 1'b1; link_wen = 1'b1;       target = pc + 32'd16 + (off25 << 4); end
        // SRG ( retorno, salta a la dirección guardada en rs1(alineada a bundle))
        4'b0110: begin taken = 1'b1; target = {a[31:4], 4'b0000}; end
        // FIN (detiene la ejecución)
        4'b0111: fin = 1'b1;
        // NOP del BRU
        4'b1111: ;
        // Cualquier otro funct es invalido
        default: illegal = 1'b1;
      endcase
    end
  end
endmodule
