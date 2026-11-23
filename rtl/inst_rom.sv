// inst_rom.sv - ROM de instrucciones (Proyecto II, arquitectura Harvard).
// 64 KB = 4096 bundles de 128 bits. Lectura sincrona de 1 ciclo: la salida registrada
// hace de registro IF/ID del bundle, asi que el flujo secuencial no tiene burbujas.
// `en` = 0 (stall de la cache de datos) retiene la salida para congelar IF/ID en lockstep.
// El contenido lo carga el testbench (tb_top) antes de soltar el reset.
module inst_rom #(parameter int BUNDLES = 4096) (
  input  logic         clk,
  input  logic         rst,
  input  logic         en,
  input  logic [31:0]  addr,      // direccion de byte del bundle (PC)
  output logic [127:0] data
);
  logic [127:0] rom [0:BUNDLES-1];

  integer i;
  initial begin
    for (i = 0; i < BUNDLES; i = i + 1) rom[i] = 128'h0;
  end

  logic [$clog2(BUNDLES)-1:0] idx;
  assign idx = addr[$clog2(BUNDLES)+3:4];

  always @(posedge clk) begin
    if (rst)     data <= 128'h0;
    else if (en) data <= rom[idx];
  end
endmodule
