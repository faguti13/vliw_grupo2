// memory.sv - Memoria byte-addressable big-endian.
// Puerto de fetch: 128 bits (16 bytes alineados). Puerto de datos: palabra de 32 bits.
// Lectura combinacional; escritura sincrona.


module memory #(parameter int MEM_BYTES = 1 << 20) (
  input  logic         clk,
  input  logic [31:0]  fetch_addr, //dir a buscar
  output logic [127:0] fetch_data, //bundle que esta en la dir de fetch_addr
  input  logic [31:0]  d_addr, //dir donde quiere leer o escribir
  output logic [31:0]  d_rdata, //dato leido
  input  logic         d_we, //senal de habilitacion de escritura
  input  logic [31:0]  d_wdata //dato que se quiere escribir
);
  logic [7:0] mem [0:MEM_BYTES-1]; //arreglo de 8 bits (bytes) que abarca desde la posicion 0 hasta MEM_BYTES - 1
  // Como es memoria byte-addressable, cada direccion apunta exactamente a un byte

  integer i;
  initial begin //toda la memoria con 8'h00 para iniciar
    for (i = 0; i < MEM_BYTES; i = i + 1) mem[i] = 8'h00;
  end

  /* fetch_data debe venir alineados con palabras de 32 bits (multiplos de 4= 0,4,8,..),
  fetch_addr  debe venir alineado con 16 bits (por el bundle), el hexa menos significativo debe ser cero
  Este codigo alinea al mas bajo 
   */
  logic [31:0] fa, da;
  assign fa = {fetch_addr[31:4], 4'b0000} % MEM_BYTES; //fuerza los 2 bits mas bajos a ser 0 (asi es multiplo de 4)
  assign da = {d_addr[31:2], 2'b00} % MEM_BYTES; //fuerza los 4 bits mas bajos a ser 0 (asi es multiplo de 16)

  //devuelde en fetch_data la siguente instruccion (buldle)
  genvar g;
  generate
    for (g = 0; g < 16; g = g + 1) begin : g_fetch
      assign fetch_data[127 - 8*g -: 8] = mem[fa + g];
    end
  endgenerate

  assign d_rdata = {mem[da], mem[da + 1], mem[da + 2], mem[da + 3]}; //dato que se quiere escribir o leer

  always @(posedge clk) begin
    if (d_we) begin //si hay  senal de escritura, escribe em me 
      mem[da]     <= d_wdata[31:24];
      mem[da + 1] <= d_wdata[23:16];
      mem[da + 2] <= d_wdata[15:8];
      mem[da + 3] <= d_wdata[7:0];
    end
  end
endmodule
