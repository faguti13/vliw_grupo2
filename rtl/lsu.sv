// lsu.sv - Unidad de carga/almacenamiento (slot 1). CP (load word), AP (store word).
// Direccion efectiva = GPR[rbase] + SignExtend(imm15)

module lsu (
  input  logic [31:0] instr, //Instruccion codificada CP, AP o NOP
  input  logic [31:0] base, // GPR[rbase]
  input  logic [31:0] store_v, // valor que se desea almacenar en memoria (fuente del AP)
  input  logic [31:0] mem_rdata, /// Palabra devuelta por la memoria
  output logic [31:0] addr, //Direccion efectiva calculada por la LSU
  output logic        mem_we, //habilita escritura en memoria.
  output logic [31:0] mem_wdata, //Dato enviado para almacenarse en memoria
  output logic        wen, //solicita escrita en registros
  output logic [4:0]  rd,
  output logic [31:0] y, //resultado para el banco de regustros
  output logic        illegal //instruccion invalida
);

  logic [14:0] imm15;
  logic [31:0] simm;
  assign imm15 = {instr[31], instr[25:12]};
  assign simm  = {{17{imm15[14]}}, imm15}; //extension del bit de signo del inmeddiato a 32 bits (manejar dezplazamientos negativos)
  assign addr  = base + simm; // dir de memoria efectivo offset(base)
  assign rd    = instr[11:7]; 
  assign mem_wdata = store_v; 
  assign y     = mem_rdata;

  always @* begin
    wen = 1'b0; mem_we = 1'b0; illegal = 1'b0;
    if (instr[2:0] != 3'b010) illegal = 1'b1;
    else begin
      case (instr[6:3])
        4'b0000: wen = 1'b1; // Operacion de Carga (Load) -> Habilita escritura en registros
        4'b0001: mem_we = 1'b1; // Operacion de Almacenamiento (Store) -> Habilita escritura en memoria
        4'b1111: ; // NOP (No Operation) -> No hace nada, deja todo en 0
        default: illegal = 1'b1;
      endcase
    end
  end
endmodule
