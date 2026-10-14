// regfile.sv - 32 registros de 32 bits. 8 puertos de lectura combinacional,
// 5 de escritura sincrona (prioridad fija: puerto mayor gana; el puerto
// 0 es ALU, 1 LSU, 2 BRU, 3-4 cripto). r0 vale siempre 0. Sin bypass.

/*Si el puerto 0 y el puerto 4 intentan escribir en el registro R5 al mismo tiempo, el puerto 
0 escribe primero, pero el puerto 4 pasa despues, lo sobreescribe y su valor es el que  se 
queda guardado en R5. (prioridad fija: puerto mayor gana)
*/


module regfile (
  input  logic         clk,
  input  logic         rst,
  input  logic [39:0]  raddr, // Contiene ocho direcciones de registros que se quieren leer (2 por inst del bundle), 5 bits
  output logic [255:0] rdata, // Devuelve los ocho valores leidos, de 32 bits cada uno.
  input  logic [4:0]   wen, //Cinco senales de habilitacion, una por puerto de escritura.
  input  logic [24:0]  waddr, //Contiene las direcciones de los cinco registros que se quieren escribir (una para alu, lsu, bru y dos para cripto)
  input  logic [159:0] wdata // Contiene los cinco valores que podrian escribirse 32 bits
);
  logic [31:0] regs [0:31]; //arreglo de 32 registros de 32 bits

  integer k;
  initial begin
    for (k = 0; k < 32; k = k + 1) regs[k] = 32'h0;
  end

  /*lectura de registros, en a se guarda el num de registro a acceder (0 al 31) y en rdata se guarda el valor
  leido (regs[a], en un bus 256 bits (32*8))
  */
  genvar g;
  generate
    for (g = 0; g < 8; g = g + 1) begin : g_rd
      wire [4:0] a = raddr[5*g +: 5]; // extrae un bloque de 5 bits del bus raddr (ej. para g=0 toma raddr[4:0])
      assign rdata[32*g +: 32] = (a == 5'd0) ? 32'h0 : regs[a];
    end
  endgenerate


  /*Escritura de registros*/
  integer p;
  always @(posedge clk) begin
    if (rst) begin
      for (p = 0; p < 32; p = p + 1) regs[p] <= 32'h0; //limpia todos los registos con 32'h0
    end else begin
      for (p = 0; p < 5; p = p + 1) begin
        if (wen[p] && waddr[5*p +: 5] != 5'd0) //que en no sea cero y el registro en el que se escribira no sea r0
          regs[waddr[5*p +: 5]] <= wdata[32*p +: 32]; // se escribe en el regs[n] el valor de wdata[n]
      end
    end
  end
endmodule
