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

endpackage
