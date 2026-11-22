// Etapa IF: Program Counter (reset 0x00000000, avanza 16 bytes por bundle).
// Una redireccion (salto tomado) carga el nuevo PC; `stop` congela el fetch (FIN).
// `stall` (dmem_stall) tambien congela el PC para el lockstep de la cache de datos.
module fetch (
  input  logic        clk,
  input  logic        rst,
  input  logic        redirect,    // 1 si un salto tomado cambia el PC
  input  logic [31:0] redirect_pc, // direccion destino del salto
  input  logic        stop,        // 1 congela el PC (FIN / halt)
  input  logic        stall,       // 1 congela el PC (miss de datos)
  output logic [31:0] pc           // PC actual, apunta al bundle a buscar
);
  always @(posedge clk) begin
    if (rst)                      pc <= 32'h0000_0000;
    else if (redirect && !stall)  pc <= redirect_pc;
    else if (!stop && !stall)     pc <= pc + 32'd16;
  end
endmodule
