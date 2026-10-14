// key_vault.sv - Boveda de llaves: 4 llaves x 4 subllaves de 32 bits (4 x 128 bits).
// Raiz de confianza: la unica escritura es LOADKEY (con we ya condicionado por SR.AUTH)
// y la unica lectura es el puerto rdata, que solo se conecta a la funcion F de la
// unidad criptografica. No existe ningun puerto hacia los GPR ni hacia la memoria.
module key_vault (
  input  logic        clk,
  input  logic        we,
  input  logic [1:0]  wkey,
  input  logic [1:0]  wsub,
  input  logic [31:0] wdata,
  input  logic [1:0]  rkey,
  input  logic [1:0]  rsub,
  output logic [31:0] rdata
);
  logic [31:0] vault [0:3][0:3];
  integer i, j;
  initial begin
    for (i = 0; i < 4; i = i + 1)
      for (j = 0; j < 4; j = j + 1) vault[i][j] = 32'h0;
  end
  assign rdata = vault[rkey][rsub];
  always @(posedge clk) begin
    if (we) vault[wkey][wsub] <= wdata;
  end
endmodule
