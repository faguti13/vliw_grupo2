// Procesador VLIW segmentado de 4 etapas: IF, ID, EX, WB (Proyecto II).
//  IF: fetch del bundle completo (128 bits) desde inst_rom.
//  ID: dispatch de los 4 slots y lectura del banco.
//  EX: ALU, LSU, BRU y unidad cripto en paralelo. Los saltos se resuelven aca.
//  WB: escritura de resultados en el banco.
// dmem_stall congela PC, IF/ID e ID/EX en lockstep e inyecta burbuja hacia EX/WB.
// No hay forwarding: las distancias RAW las resuelve el planificador.
module core #(parameter logic [31:0] CRED = 32'hCAFE1234) (
  input  logic         clk,
  input  logic         rst,
  output logic [31:0]  imem_addr,
  output logic         imem_en,
  input  logic [127:0] imem_data,
  output logic [31:0]  dmem_addr,
  output logic         dmem_re,
  output logic         dmem_we,
  output logic [31:0]  dmem_wdata,
  input  logic [31:0]  dmem_rdata,
  input  logic         dmem_stall,
  output logic         halted,
  output logic [31:0]  illegal_cnt,
  output logic [31:0]  bundles_exec,
  output logic [31:0]  cycles,
  // eventos para perf_counters
  output logic         ev_adv,
  output logic         ev_taken,
  output logic [2:0]   ev_instr
);
  logic [31:0] pc;
  logic        ex_flush, ex_taken, ex_fin, ex_go;
  logic [31:0] ex_target;
  logic        fin_seen;

  fetch u_fetch (.clk(clk), .rst(rst), .redirect(ex_flush && ex_taken), .redirect_pc(ex_target),
                 .stop(fin_seen || ex_fin || halted), .stall(dmem_stall), .pc(pc));
  assign imem_addr = pc;
  assign imem_en   = !dmem_stall && !fin_seen && !halted;

  // IF/ID: el bundle vive en la salida registrada de inst_rom; aca solo PC y valid.
  logic [127:0] ifid_bundle;
  logic [31:0]  ifid_pc;
  logic         ifid_valid;
  assign ifid_bundle = imem_data;
  always @(posedge clk) begin
    if (rst) begin ifid_valid <= 1'b0; ifid_pc <= 32'h0; end
    else if (!dmem_stall) begin
      ifid_pc    <= pc;
      ifid_valid <= !ex_flush && !fin_seen && !halted && imem_en;
    end
  end

  // ID
  logic [31:0] id_s0, id_s1, id_s2, id_s3;
  logic [39:0] id_raddr;
  logic [7:0]  id_ruse;
  logic [24:0] id_waddr;
  logic [4:0]  id_wuse;
  logic        id_illegal_op;

  dispatch u_dispatch (.bundle(ifid_bundle), .slot0(id_s0), .slot1(id_s1), .slot2(id_s2), .slot3(id_s3),
                       .raddr(id_raddr), .ruse(id_ruse), .waddr(id_waddr), .wuse(id_wuse),
                       .illegal_op(id_illegal_op));

  logic [255:0] id_rdata;
  logic [4:0]   wb_wen;
  logic [24:0]  wb_waddr;
  logic [159:0] wb_wdata;

  regfile u_regfile (.clk(clk), .rst(rst), .raddr(id_raddr), .rdata(id_rdata),
                     .wen(wb_wen), .waddr(wb_waddr), .wdata(wb_wdata));

  logic [127:0] idex_bundle;
  logic [31:0]  idex_pc;
  logic [255:0] idex_rdata;
  logic         idex_valid;
  always @(posedge clk) begin
    if (rst) begin idex_valid <= 1'b0; idex_bundle <= 128'h0; idex_pc <= 32'h0; idex_rdata <= 256'h0; end
    else if (!dmem_stall) begin
      idex_bundle <= ifid_bundle;
      idex_pc     <= ifid_pc;
      idex_rdata  <= id_rdata;
      idex_valid  <= ifid_valid && !ex_flush;
    end
  end

  // EX
  logic [31:0] e0, e1, e2, e3;
  assign e0 = idex_bundle[127:96];
  assign e1 = idex_bundle[95:64];
  assign e2 = idex_bundle[63:32];
  assign e3 = idex_bundle[31:0];

  logic [31:0] rv [0:7];
  genvar g;
  generate
    for (g = 0; g < 8; g = g + 1) begin : g_rv
      assign rv[g] = idex_rdata[32*g +: 32];
    end
  endgenerate

  assign ex_go = idex_valid && !dmem_stall;

  logic a_wen, a_ill; logic [4:0] a_rd; logic [31:0] a_y;
  alu u_alu (.instr(e0), .a(rv[0]), .b(rv[1]), .wen(a_wen), .rd(a_rd), .y(a_y), .illegal(a_ill));

  logic l_wen, l_we, l_ill; logic [4:0] l_rd; logic [31:0] l_y, l_addr, l_wdata;
  lsu u_lsu (.instr(e1), .base(rv[2]), .store_v(rv[3]), .mem_rdata(dmem_rdata), .addr(l_addr),
             .mem_we(l_we), .mem_wdata(l_wdata), .wen(l_wen), .rd(l_rd), .y(l_y), .illegal(l_ill));
  assign dmem_addr  = l_addr;
  assign dmem_wdata = l_wdata;
  assign dmem_we    = idex_valid && l_we;
  assign dmem_re    = idex_valid && l_wen;

  logic b_link, b_fin, b_ill, b_taken; logic [31:0] b_target, b_linkv;
  bru u_bru (.instr(e2), .pc(idex_pc), .a(rv[4]), .b(rv[5]), .taken(b_taken), .target(b_target),
             .link_wen(b_link), .link_val(b_linkv), .fin(b_fin), .illegal(b_ill));
  assign ex_taken  = ex_go && b_taken;
  assign ex_fin    = ex_go && b_fin;
  assign ex_flush  = ex_taken || ex_fin;
  assign ex_target = b_target;

  logic c_wl, c_wr, c_ill; logic [4:0] c_rdl, c_rdr; logic [31:0] c_yl, c_yr, sr;
  crypto_unit #(.CRED(CRED)) u_crypto (.clk(clk), .rst(rst), .valid(ex_go), .instr(e3),
      .a(rv[6]), .b(rv[7]), .wen_l(c_wl), .rd_l(c_rdl), .y_l(c_yl), .wen_r(c_wr), .rd_r(c_rdr),
      .y_r(c_yr), .illegal(c_ill), .sr_o(sr));

  logic ex_illegal;
  assign ex_illegal = ex_go && (a_ill || l_ill || b_ill || c_ill);

  // Contar instrucciones no-NOP del bundle que termina EX
  function automatic logic [2:0] count_instr(input logic [127:0] b);
    logic [2:0] n;
    n = 3'd0;
    if (b[127:96] != 32'h0) n = n + 3'd1;
    if (b[95:64]  != 32'h0) n = n + 3'd1;
    if (b[63:32]  != 32'h0) n = n + 3'd1;
    if (b[31:0]   != 32'h0) n = n + 3'd1;
    return n;
  endfunction
  assign ev_adv   = ex_go;
  assign ev_taken = ex_taken;
  assign ev_instr = ex_go ? count_instr(idex_bundle) : 3'd0;

  logic         exwb_valid;
  logic [4:0]   exwb_wen;
  logic [24:0]  exwb_waddr;
  logic [159:0] exwb_wdata;
  logic         exwb_fin;
  always @(posedge clk) begin
    if (rst) begin
      exwb_valid <= 1'b0; exwb_wen <= 5'b0; exwb_waddr <= 25'h0; exwb_wdata <= 160'h0; exwb_fin <= 1'b0;
    end else if (dmem_stall) begin
      // burbuja hacia WB: no duplicar escrituras mientras EX espera la cache
      exwb_valid <= 1'b0;
      exwb_wen   <= 5'b0;
      exwb_fin   <= 1'b0;
    end else begin
      exwb_valid <= idex_valid;
      exwb_wen   <= idex_valid ? {c_wr, c_wl, b_link, l_wen, a_wen} : 5'b0;
      exwb_waddr <= {c_rdr, c_rdl, 5'd31, l_rd, a_rd};
      exwb_wdata <= {c_yr, c_yl, b_linkv, l_y, a_y};
      exwb_fin   <= ex_fin;
    end
  end
  assign wb_wen   = exwb_wen;
  assign wb_waddr = exwb_waddr;
  assign wb_wdata = exwb_wdata;

  always @(posedge clk) begin
    if (rst) begin
      fin_seen <= 1'b0; halted <= 1'b0; illegal_cnt <= 32'h0; bundles_exec <= 32'h0; cycles <= 32'h0;
    end else begin
      cycles <= cycles + 32'd1;
      if (ex_fin) fin_seen <= 1'b1;
      if (exwb_fin) halted <= 1'b1;
      if (ex_illegal) illegal_cnt <= illegal_cnt + 32'd1;
      if (ex_go) bundles_exec <= bundles_exec + 32'd1;
    end
  end
endmodule
