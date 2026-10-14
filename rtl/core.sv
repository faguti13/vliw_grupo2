// Procesador VLIW segmentado de 4 etapas: IF, ID, EX, WB.
//  IF: fetch del bundle completo (128 bits).
//  ID: dispatch de los 4 slots y lectura del banco.
//  EX: ALU, LSU, BRU y unidad cripto/seguridad en paralelo. Los saltos se resuelven acá.
//  WB: escritura de resultados en el banco.
// No hay forwarding, scoreboarding ni stalls ya que eso lo resuelve el planificador(software).
module core #(parameter logic [31:0] CRED = 32'hCAFE1234) (
  input  logic         clk,
  input  logic         rst,
  output logic [31:0]  imem_addr, // dirección a mem de las instr
  input  logic [127:0] imem_data, // bundle leído (128 bits 4 slots)
  output logic [31:0]  dmem_addr, // dirección a memoria de datos
  output logic         dmem_we,   // write enable de datos
  output logic [31:0]  dmem_wdata, // dato a escribir en mem
  input  logic [31:0]  dmem_rdata, // dato leído de mem
  output logic         halted,     // procesador detenido
  output logic [31:0]  illegal_cnt, // contador de instr ilegales
  output logic [31:0]  bundles_exec, // contador de bundles ejecutados
  output logic [31:0]  cycles       // contador de ciclos
);
  // Etapa 1: IF
  logic [31:0] pc;
  logic        ex_flush, ex_taken, ex_fin;
  logic [31:0] ex_target;
  logic        fin_seen;
  // Fetch: pide el bundle al PC, redirige si hay salto tomado, se detiene con fin o halt 
  fetch u_fetch (.clk(clk), .rst(rst), .redirect(ex_flush && ex_taken), .redirect_pc(ex_target),
                 .stop(fin_seen || ex_fin || halted), .pc(pc));
  assign imem_addr = pc;
  // Registro IF/ID: guarda el bundle y su PC para la etapa de decode.
  logic [127:0] ifid_bundle;
  logic [31:0]  ifid_pc;
  logic         ifid_valid;
  always @(posedge clk) begin
    if (rst) begin ifid_valid <= 1'b0; ifid_bundle <= 128'h0; ifid_pc <= 32'h0; end
    else begin
      ifid_bundle <= imem_data;
      ifid_pc     <= pc;
      // El bundle se invalida si hay flush
      ifid_valid  <= !ex_flush && !fin_seen && !halted;
    end
  end

  // Etapa 2: ID
  logic [31:0] id_s0, id_s1, id_s2, id_s3; //los 4 slots del bundle
  logic [39:0] id_raddr;                   // 8 direcciones de lectura (5 bits cada uno)
  logic [7:0]  id_ruse;
  logic [24:0] id_waddr;                   // 5 direcciones de escritura (5 bits cada uno)
  logic [4:0]  id_wuse;
  logic        id_illegal_op;

  // Dispatch: separa el bundle en slots y arma direcciones del banco
  dispatch u_dispatch (.bundle(ifid_bundle), .slot0(id_s0), .slot1(id_s1), .slot2(id_s2), .slot3(id_s3),
                       .raddr(id_raddr), .ruse(id_ruse), .waddr(id_waddr), .wuse(id_wuse),
                       .illegal_op(id_illegal_op));

  logic [255:0] id_rdata; // 8 registros leídos
  logic [4:0]   wb_wen;   // 5 write enables de WB
  logic [24:0]  wb_waddr; // 5 direcciones de escritura de WB
  logic [159:0] wb_wdata; // 5 datos de escritura de WB

  // Banco de registros ( 8 puestos de lectura y 5 de escritura)
  regfile u_regfile (.clk(clk), .rst(rst), .raddr(id_raddr), .rdata(id_rdata),
                     .wen(wb_wen), .waddr(wb_waddr), .wdata(wb_wdata));

  // Registro  ID/EX: lleva bundle , PC y valores ya leidos a la etapa EX.
  logic [127:0] idex_bundle;
  logic [31:0]  idex_pc;
  logic [255:0] idex_rdata;
  logic         idex_valid;
  always @(posedge clk) begin
    if (rst) begin idex_valid <= 1'b0; idex_bundle <= 128'h0; idex_pc <= 32'h0; idex_rdata <= 256'h0; end
    else begin
      idex_bundle <= ifid_bundle;
      idex_pc     <= ifid_pc;
      idex_rdata  <= id_rdata;
      // Si hubo flush en EX, el bundle en ID ya no se debe ejecutar
      idex_valid  <= ifid_valid && !ex_flush;
    end
  end

  // Etapa 3: EX
  // Cada slot del bundle va a su unidad funcional
  logic [31:0] e0, e1, e2, e3;
  assign e0 = idex_bundle[127:96]; // slot 0 - ALU
  assign e1 = idex_bundle[95:64];  // slot 1 - LSU
  assign e2 = idex_bundle[63:32];  // slot 2 - BRU
  assign e3 = idex_bundle[31:0];   // slot 3 - cripto

  // Reparte los 8 valores leídos del banco entre las unidades
  logic [31:0] rv [0:7];
  genvar g;
  generate
    for (g = 0; g < 8; g = g + 1) begin : g_rv
      assign rv[g] = idex_rdata[32*g +: 32];
    end
  endgenerate

  // ALU
  logic a_wen, a_ill; logic [4:0] a_rd; logic [31:0] a_y;
  alu u_alu (.instr(e0), .a(rv[0]), .b(rv[1]), .wen(a_wen), .rd(a_rd), .y(a_y), .illegal(a_ill));
  // LSU
  logic l_wen, l_we, l_ill; logic [4:0] l_rd; logic [31:0] l_y, l_addr, l_wdata;
  lsu u_lsu (.instr(e1), .base(rv[2]), .store_v(rv[3]), .mem_rdata(dmem_rdata), .addr(l_addr),
             .mem_we(l_we), .mem_wdata(l_wdata), .wen(l_wen), .rd(l_rd), .y(l_y), .illegal(l_ill));
  assign dmem_addr  = l_addr;
  assign dmem_wdata = l_wdata;
  assign dmem_we    = idex_valid && l_we; // solo escribe si el bundle es válido
  // BRU
  logic b_link, b_fin, b_ill, b_taken; logic [31:0] b_target, b_linkv;
  bru u_bru (.instr(e2), .pc(idex_pc), .a(rv[4]), .b(rv[5]), .taken(b_taken), .target(b_target),
             .link_wen(b_link), .link_val(b_linkv), .fin(b_fin), .illegal(b_ill));
  // Un salto tomado o un FIN descartan los dos bundles que estan en IF e ID
  assign ex_taken  = idex_valid && b_taken;
  assign ex_fin    = idex_valid && b_fin;
  assign ex_flush  = ex_taken || ex_fin;
  assign ex_target = b_target;
  // Cripto / seguridad
  logic c_wl, c_wr, c_ill; logic [4:0] c_rdl, c_rdr; logic [31:0] c_yl, c_yr, sr;
  crypto_unit #(.CRED(CRED)) u_crypto (.clk(clk), .rst(rst), .valid(idex_valid), .instr(e3),
      .a(rv[6]), .b(rv[7]), .wen_l(c_wl), .rd_l(c_rdl), .y_l(c_yl), .wen_r(c_wr), .rd_r(c_rdr),
      .y_r(c_yr), .illegal(c_ill), .sr_o(sr));
  // Si alguna unidad resporta instr invalida, se cuenta como ilegal
  logic ex_illegal;
  assign ex_illegal = idex_valid && (a_ill || l_ill || b_ill || c_ill);

  // Registro EX/WB: empaqueta los 5 posibles destinos de escritura 
  logic         exwb_valid;
  logic [4:0]   exwb_wen;
  logic [24:0]  exwb_waddr;
  logic [159:0] exwb_wdata;
  logic         exwb_fin;
  always @(posedge clk) begin
    if (rst) begin
      exwb_valid <= 1'b0; exwb_wen <= 5'b0; exwb_waddr <= 25'h0; exwb_wdata <= 160'h0; exwb_fin <= 1'b0;
    end else begin
      exwb_valid <= idex_valid;
      // Ordena los 5 puertos (cripto_r, cripto_l, link, LSU, ALU)
      exwb_wen   <= idex_valid ? {c_wr, c_wl, b_link, l_wen, a_wen} : 5'b0;
      exwb_waddr <= {c_rdr, c_rdl, 5'd31, l_rd, a_rd};
      exwb_wdata <= {c_yr, c_yl, b_linkv, l_y, a_y};
      exwb_fin   <= ex_fin;
    end
  end
  // WB: los resultados del registro EX/WB van directo al banco
  assign wb_wen   = exwb_wen;
  assign wb_waddr = exwb_waddr;
  assign wb_wdata = exwb_wdata;

  // Contrato global
  always @(posedge clk) begin
    if (rst) begin
      fin_seen <= 1'b0; halted <= 1'b0; illegal_cnt <= 32'h0; bundles_exec <= 32'h0; cycles <= 32'h0;
    end else begin
      cycles <= cycles + 32'd1;
      
      // Si EX ve un FIN, se recuerda para detener el fetch
      if (ex_fin) fin_seen <= 1'b1;

      // Halt efectivo cuando FIN llega a WB
      if (exwb_fin) halted <= 1'b1;

      //Contadores
      if (ex_illegal) illegal_cnt <= illegal_cnt + 32'd1;
      if (idex_valid) bundles_exec <= bundles_exec + 32'd1;
    end
  end
endmodule
