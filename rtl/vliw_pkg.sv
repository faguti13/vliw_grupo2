// vliw_pkg.sv 
//Contiene las constantes generales de la arquitectura (constantes que no cambian)

package vliw_pkg;
  localparam int NUM_SLOTS  = 4;  // slots por bundle
  localparam int BUNDLE_W   = 128;  // ancho del bundle en bits
  localparam int XLEN       = 32;  // ancho de registro
  localparam int NREGS      = 32;  // registros de proposito general
  localparam int MEM_BYTES  = 1 << 20;  // 1 MiB (1x20^20)
  localparam logic [31:0] CRED_BOVEDA = 32'hCAFE1234;  // credencial de AUTH = CAFE1234 (para acceder a las llaves)

  // Opcodes (3 bits [2:0] de cada instrccion)
  localparam logic [2:0] OP_REG = 3'b000;
  localparam logic [2:0] OP_IMM = 3'b001;
  localparam logic [2:0] OP_MEM = 3'b010;
  localparam logic [2:0] OP_CTL = 3'b011;
  localparam logic [2:0] OP_CRY = 3'b100;
  localparam logic [2:0] OP_SEC = 3'b101;

  localparam logic [3:0] F_NOP = 4'b1111; //para representar un NOP

  /* Rotacion a la izquierda de 32 bits
  Usa automatic para almacenamiento propio temporal. 
  Recibe: x (valor a rotar) y y (cantidad de posiciones a rotar)
  Salida: result de 32 bits
  Funcion: (x << r) desplaza x, r posiciones a la izq y completa de ceros, (x >> (32 - r)) desplaza a la derecha dejando solo los bits que salieron,
  despues un or
  */
  function automatic logic [31:0] rol32(input logic [31:0] x, input int r);
    return (x << r) | (x >> (32 - r));
  endfunction

  /* Funcion de ronda F de Feistel4
  Recibe: x=32 bits a aplicarle Feistel4, k= subllave de 32 bits 
  Funcion: hace la logica F(x,k) = [rol32(x,5) + K] XOR rol32(x,13)
  */
  function automatic logic [31:0] feistel_f(input logic [31:0] x, input logic [31:0] k);
    logic [31:0] t;
    t = rol32(x, 5) + k;
    return t ^ rol32(x, 13);
  endfunction
  
endpackage
