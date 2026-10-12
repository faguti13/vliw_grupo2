// alu.sv - Unidad aritmetico-logica (slot 0). Para instrucciones tipo Registro (000) e Inmediato (001).


module alu (
  input  logic [31:0] instr,
  input  logic [31:0] a, // GPR[rs1]
  input  logic [31:0] b, // GPR[rs2] (solo tipo Registro)
  output logic        wen, //indica si un resultado se debe escribir o no
  output logic [4:0]  rd,
  output logic [31:0] y, // resultado de la operacion 
  output logic        illegal //indicar conficacion de la intruccion invalida, para ver errores en la simulacion
);
  logic [2:0]  opc;
  logic [3:0]  funct;
  logic [31:0] op2;
  logic [4:0]  sh;
  logic signed [31:0] sa, sb, sq;   // division con signo (trunca hacia cero)
  assign sa = a;
  assign sb = op2;
  assign sq = (sb == 32'sd0) ? 32'sd0 : (sa / sb); //0 si el div es 0, sino es el cociente entero
  assign opc   = instr[2:0];
  assign funct = instr[6:3];
  assign rd    = instr[11:7];
  logic [14:0] imm15;
  logic [31:0] simm15;
  assign imm15  = {instr[31], instr[25:12]};
  assign simm15 = {{17{imm15[14]}}, imm15};
  assign op2    = (opc == 3'b001) ? simm15 : b;
  assign sh     = (opc == 3'b001) ? imm15[4:0] : b[4:0];

  always @* begin
    wen = 1'b0; y = 32'h0; illegal = 1'b0;
    if (opc == 3'b000) begin
      if (instr[31:22] != 10'b0) illegal = 1'b1;
      else begin
        wen = 1'b1;
        case (funct)
          4'b0000: y = a + op2; //sum
          4'b0001: y = a - op2; //rest
          4'b0010: y = a * op2; //mul 
          4'b0011: y = (op2 == 32'h0) ? 32'hFFFFFFFF : sq; //div
          4'b0100: y = a & op2; //oly (and)
          4'b0101: y = a | op2; //olo (or)
          4'b0110: y = a ^ op2; //loe (xor)
          4'b0111: y = a << sh; // dli (shift izq)
          4'b1000: y = a >> sh; // dld (shift der)
          4'b1001: y = ($signed(a) < $signed(op2)) ? 32'h1 : 32'h0; // comp
          4'b1111: wen = 1'b0; // NOP
          default: begin wen = 1'b0; illegal = 1'b1; end
        endcase
      end
    end else if (opc == 3'b001) begin
      wen = 1'b1;
      case (funct)
        4'b0000: y = a + op2; //sumi
        4'b0001: y = a - op2; //resti
        4'b0010: y = a * op2; //muli
        4'b0011: y = (op2 == 32'h0) ? 32'hFFFFFFFF : sq; //divi
        4'b0100: y = a << sh; //dlii (shift izq inm)
        4'b0101: y = a >> sh; // dldi (shift der inm)
        default: begin wen = 1'b0; illegal = 1'b1; end 
      endcase
    end else begin
      illegal = 1'b1;
    end
  end
endmodule
