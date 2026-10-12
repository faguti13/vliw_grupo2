// Etapa IF: Program Counter (reset 0x00000000, avanza 16 bytes por bundle).
// Una redireccion (salto tomado) carga el nuevo PC; `stop` congela el fetch (FIN).
module fetch (
  input  logic        clk,
  input  logic        rst,
  input  logic        redirect,    // 1 si un salto tomado cambia el PC 
  input  logic [31:0] redirect_pc, // dirección destino del salto
  input  logic        stop,        // 1 congela el PC
  output logic [31:0] pc           // PC actual, apunta al bundle a buscar
);
  always @(posedge clk) begin
    if (rst)           pc <= 32'h0000_0000; // arranque en 0 
    else if (redirect) pc <= redirect_pc;   //salto tomado se va al destino
    else if (!stop)    pc <= pc + 32'd16;   // avanza un bundle
  end
endmodule
