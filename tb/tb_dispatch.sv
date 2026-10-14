// Separa los 4  slots, revisa puertos de lectura y detecta opcodes que no corresponden al slot.
/*
Se prueba:
  - Que los slots se separen correctamente del bundle.
  - Que las direcciones de lectura correspondan a cada slot.
  - Que los write enebles y direcciones de escritura sean correctos.
  - Que un opcode invalido en algun slot active illegal_op.
*/

// comando de prueba
// iverilog -g2012 -o tb_dispatch.vvp rtl/dispatch.sv tb/tb_dispatch.sv && vvp tb_dispatch.vvp
module tb_dispatch;
  // Señales conectadas
  logic [127:0] bundle; 
  logic [31:0] s0, s1, s2, s3; 
  logic [39:0] raddr; 
  logic [7:0] ruse;
  logic [24:0] waddr; 
  logic [4:0] wuse; 
  logic illegal_op;

  dispatch dut (.slot0(s0), .slot1(s1), .slot2(s2), .slot3(s3), .*);
  
  integer errs = 0;

  initial begin
    // Bundle de prueba
    //   slot0: SUM r1, r2, r3    -  ALU, escribe r3
    //   slot1: CP 8(r28), r4     -  LSU, lee r28 como base
    //   slot2: NOP               -  BRU, sin efecto
    //   slot3: NOP               - cripto, sin efecto
    bundle = {32'h00022180, 32'h70008202, 32'h0000007B, 32'h0000007C}; #1;
    
    // Los slots 0 y 3 deben coincidir con lo que se cargó
    if (s0 !== 32'h00022180 || s3 !== 32'h0000007C) begin errs++; $display("FAIL slots"); end

    // Direcciones de lectura:
    //   puerto 0 (ALU rs1) - r1
    //   puerto 1 (ALU rs2) - r2
    //   puerto 2 (LSU base) - r28
    if (raddr[4:0] !== 5'd1 || raddr[9:5] !== 5'd2 || raddr[14:10] !== 5'd28) begin errs++; $display("FAIL raddr"); end
    
    // Este bundle es valido no debe marcar ilegal
    if (illegal_op) begin errs++; $display("FAIL ilegal falso"); end
    
    // Escrituras:
    //   puerto 0 (ALU) - r3, activo
    //   puerto 1 (LSU load) - r4, activo
    if (wuse[0] !== 1 || wuse[1] !== 1 || waddr[4:0] !== 5'd3 || waddr[9:5] !== 5'd4) begin errs++; $display("FAIL wuse"); end
    
    // opcode 011 en slot ALU. Se debe reportar como ilegal
    bundle = {32'h0000001B, 32'h0000007A, 32'h0000007B, 32'h0000007C}; #1;
    if (!illegal_op) begin errs++; $display("FAIL ilegal"); end
    
    // Resultado final 
    if (errs == 0) $display("tb_dispatch: PASS"); else begin $display("tb_dispatch: FAIL"); $fatal(1); end
    $finish;
  end
endmodule
