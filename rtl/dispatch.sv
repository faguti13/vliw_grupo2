// Decodifica/despacha un bundle: separa los 4 slots, elige las
// direcciones de lectura de los 8 puertos del banco segun el tipo de cada slot
// y reporta los registros que cada slot escribe (para el monitor de riesgos).
module dispatch (
  input  logic [127:0] bundle,    // bundle completo (4 slots de 32 bits)
  output logic [31:0]  slot0, slot1, slot2, slot3,
  output logic [39:0]  raddr,     // 8 direcciones de lectura x 5 bits
  output logic [7:0]   ruse,      // que puerto de lectura se usa realmente
  output logic [24:0]  waddr,     // 5 instr de escritura x 5 bits: orden - ALU, LSU, BRU(r31), cripto L, cripto R
  output logic [4:0]   wuse,      // que puerto de escritura se activa
  output logic         illegal_op // opcode que no corresponde al slot
);
  // Separa el bundle en sus 4 slots (cada uno de 32 bits)
  assign slot0 = bundle[127:96];
  assign slot1 = bundle[95:64];
  assign slot2 = bundle[63:32];
  assign slot3 = bundle[31:0];

  logic [4:0] r [0:7]; // direcciones de los 8 puertos de lectura
  always @* begin
    ruse = 8'h0;

    // Slot 0 - ALU
    // Opcode 001 = instr con immediato: solo lee rs1 y usa 0 en el puerto 1
    // Cualquier otro caso lee rs1 (bits 21:17) y rs2 (bits 16:12)
    if (slot0[2:0] == 3'b001) begin r[0] = slot0[30:26]; r[1] = 5'd0; ruse[0] = 1'b1; end
    else begin r[0] = slot0[21:17]; r[1] = slot0[16:12]; ruse[1:0] = 2'b11; end
    
    // Slot 1 - LSU
    // base siempre en rs (30:26). El store lee además el valor a guardar  en rd(11:7)
    r[2] = slot1[30:26]; r[3] = slot1[11:7]; ruse[2] = 1'b1; ruse[3] = (slot1[6:3] == 4'b0001);
    
    // Slot 2 - BRU
    // condicionales y SRG leen rs1, solo condicionales leen rs2
    r[4] = slot2[16:12]; r[5] = slot2[11:7];
    ruse[4] = (slot2[6:3] <= 4'b0011) || (slot2[6:3] == 4'b0110);
    ruse[5] = (slot2[6:3] <= 4'b0011);

    // Slot 3 - Cripto/Seguridad
    // Opcode 100: rs_L(16:12) y rs_R (11:7)
    // Opcode 101: rs_L(16:12) y credencial (11:7)
    r[6] = slot3[16:12]; r[7] = slot3[11:7];
    ruse[6] = (slot3[2:0] == 3'b100 && slot3[6:3] == 4'b0001);
    ruse[7] = (slot3[2:0] == 3'b100 && slot3[6:3] <= 4'b0001) ||
              (slot3[2:0] == 3'b101 && slot3[6:3] == 4'b0000);
    
    // Registros escritos
    wuse = 5'b0;  //Nadie escribe por defecto
    waddr[4:0]   = slot0[11:7]; // ALU: rd
    waddr[9:5]   = slot1[11:7]; // LSU: rd
    waddr[14:10] = 5'd31;       // BRU: siempre r31
    waddr[19:15] = (slot3[2:0] == 3'b101) ? slot3[11:7] : slot3[30:26]; // cripto L
    waddr[24:20] = slot3[25:21]; // cripto R
    // Momento de escritura de cada FU
    // ALU con imm || ALU registro salvo NOP
    wuse[0] = (slot0[2:0] == 3'b001) || (slot0[2:0] == 3'b000 && slot0[6:3] != 4'b1111);
    wuse[1] = (slot1[2:0] == 3'b010 && slot1[6:3] == 4'b0000);   // LSU load
    wuse[2] = (slot2[2:0] == 3'b011 && slot2[6:3] == 4'b0101);   // BRU SYE (link)
    wuse[3] = (slot3[2:0] == 3'b100 && slot3[6:3] == 4'b0001) || // cripto L
              (slot3[2:0] == 3'b101 && slot3[6:3] == 4'b0010);   // cripto L:otra op
    wuse[4] = (slot3[2:0] == 3'b100 && slot3[6:3] == 4'b0001);   // cripto R
    // Instr ilegal
    // Cada slot tiene un opcode fijo, sino coincide se reporta
    illegal_op = !(slot0[2:0] == 3'b000 || slot0[2:0] == 3'b001) ||
                 (slot1[2:0] != 3'b010) || (slot2[2:0] != 3'b011) ||
                 !(slot3[2:0] == 3'b100 || slot3[2:0] == 3'b101);
  end
 // Se empaquetan las 8 direcciones de lectura en un solo bus de 40 bits
  genvar g;
  generate
    for (g = 0; g < 8; g = g + 1) begin : g_ra
      assign raddr[5*g +: 5] = r[g];
    end
  endgenerate
endmodule
