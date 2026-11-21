// tb_stall_lockstep.sv - Verifica el congelamiento en lockstep del pipeline (Iteracion 1).
// Core + ROM sincrona + memoria de datos de comportamiento que inyecta stalls aleatorios:
//   - en cada CP/AP con probabilidad +STALLPCT (por omision 50 %) y largo aleatorio 1..+STALLMAX ciclos,
//   - y tambien en ciclos sin acceso (+FREEPCT), para probar que el congelamiento es total.
// Un programa correcto debe dejar los mismos registros y memoria que sin stalls (check_dump.py)
// y el monitor de riesgos debe reportar 0. Se corre con los 8 programas de P1 (make stall-test).
// Plusargs: +PROG= +REGS= +DUMP= +DUMPLO= +DUMPHI= +SEED= +STALLPCT= +STALLMAX= +FREEPCT= +TIMEOUT=
module tb_stall_lockstep;
  logic clk = 0, rst = 1;
  always #5 clk = ~clk;

  logic [31:0]  imem_addr, dmem_addr, dmem_wdata, dmem_rdata;
  logic [127:0] imem_data;
  logic         imem_en, dmem_re, dmem_we, dmem_stall;
  logic         halted;
  logic [31:0]  illegal_cnt, bundles_exec, cycles;

  core u_core (.clk(clk), .rst(rst), .imem_addr(imem_addr), .imem_en(imem_en), .imem_data(imem_data),
      .dmem_addr(dmem_addr), .dmem_re(dmem_re), .dmem_we(dmem_we), .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
      .dmem_stall(dmem_stall), .halted(halted), .illegal_cnt(illegal_cnt), .bundles_exec(bundles_exec),
      .cycles(cycles));
  inst_rom u_rom (.clk(clk), .rst(rst), .en(imem_en), .addr(imem_addr), .data(imem_data));

  integer raw_count, waw_count;
  hazard_monitor u_haz (.clk(clk), .rst(rst),
      .ifid_bundle(u_core.ifid_bundle), .ifid_valid(u_core.ifid_valid && !dmem_stall),
      .ex_flush(u_core.ex_flush),
      .idex_bundle(u_core.idex_bundle), .idex_valid(u_core.idex_valid),
      .exwb_wen(u_core.exwb_wen), .exwb_waddr(u_core.exwb_waddr),
      .trace(1'b0), .raw_count(raw_count), .waw_count(waw_count));

  // Memoria de datos de comportamiento (64 KB, alias de 16 bits) con stalls inyectados
  logic [7:0] dmem [0:65535];
  logic [7:0] rom_b [0:65535];
  logic [15:0] da;
  assign da = {dmem_addr[15:2], 2'b00};
  assign dmem_rdata = {dmem[da], dmem[da + 1], dmem[da + 2], dmem[da + 3]};

  integer seed, stall_pct, stall_max, free_pct, left, injected, stalled_cycles;
  integer next_acc, next_free;   // largo sorteado para el proximo acceso / ciclo libre (0 = sin stall)
  logic   in_stall, access, start;
  // Un stall puede empezar en el mismo ciclo en que aparece el acceso (como un miss real);
  // `left` cuenta los ciclos que faltan despues del actual.
  assign access = dmem_re || dmem_we;
  assign start  = !rst && !in_stall && (access ? next_acc > 0 : next_free > 0);
  assign dmem_stall = !rst && (left > 0 || start);
  always @(posedge clk) begin
    next_acc  <= (($urandom(seed) % 100) < stall_pct) ? 1 + ($urandom % stall_max) : 0;
    next_free <= (($urandom % 100) < free_pct) ? 1 + ($urandom % stall_max) : 0;
    if (rst) begin left <= 0; in_stall <= 1'b0; end
    else if (start) begin
      left     <= (access ? next_acc : next_free) - 1;
      in_stall <= 1'b1;
      if (access) injected <= injected + 1;
    end else if (left > 0) left <= left - 1;
    else in_stall <= 1'b0;
    if (!rst && dmem_stall) stalled_cycles <= stalled_cycles + 1;
  end

  integer stores = 0;
  always @(posedge clk) begin
    if (dmem_we && !dmem_stall) begin
      stores <= stores + 1;
      dmem[da]     <= dmem_wdata[31:24];
      dmem[da + 1] <= dmem_wdata[23:16];
      dmem[da + 2] <= dmem_wdata[15:8];
      dmem[da + 3] <= dmem_wdata[7:0];
    end
  end

  // En cada ciclo de espera se conservan IF/ID e ID/EX y se vacía EX/WB.
  always @(posedge clk) begin
    if (!rst && dmem_stall) begin
      logic [31:0] pc, pc_id, pc_ex, sr;
      logic valid_id, valid_ex;
      logic [127:0] bundle_id, bundle_ex;
      logic [255:0] operands;
      {pc, pc_id, pc_ex, sr} = {imem_addr, u_core.ifid_pc, u_core.idex_pc, u_core.sr};
      {valid_id, valid_ex} = {u_core.ifid_valid, u_core.idex_valid};
      {bundle_id, bundle_ex, operands} = {imem_data, u_core.idex_bundle, u_core.idex_rdata};
      #1;
      if ({imem_addr, u_core.ifid_pc, u_core.idex_pc, u_core.sr} !== {pc, pc_id, pc_ex, sr} ||
          {u_core.ifid_valid, u_core.idex_valid} !== {valid_id, valid_ex} ||
          {imem_data, u_core.idex_bundle, u_core.idex_rdata} !== {bundle_id, bundle_ex, operands})
        $fatal(1, "El pipeline avanzó durante un stall en PC=%h", pc_ex);
      if ({u_core.exwb_valid, u_core.exwb_wen, u_core.exwb_fin} !== 7'b0)
        $fatal(1, "WB recibió un bundle durante un stall en PC=%h", pc_ex);
    end
  end

  string prog, regs_f, dump_f;
  integer timeout, dlo, dhi, i, j, fd, h, r, addr, b, expected_stores;

  initial begin
    if (!$value$plusargs("SEED=%d", seed)) seed = 1;
    if (!$value$plusargs("STALLPCT=%d", stall_pct)) stall_pct = 50;
    if (!$value$plusargs("STALLMAX=%d", stall_max)) stall_max = 6;
    if (!$value$plusargs("FREEPCT=%d", free_pct)) free_pct = 10;
    if (!$value$plusargs("TIMEOUT=%d", timeout)) timeout = 200000;
    injected = 0; stalled_cycles = 0;
    for (i = 0; i < 65536; i = i + 1) begin dmem[i] = 8'h00; rom_b[i] = 8'h00; end
    #1;
    if (!$value$plusargs("PROG=%s", prog)) $fatal(1, "Falta +PROG");
    h = $fopen(prog, "r");
    if (!h) $fatal(1, "No se pudo abrir %s", prog);
    addr = 0;
    while (!$feof(h)) begin
      r = $fscanf(h, " @%h", addr);
      if (r != 1) begin
        r = $fscanf(h, " %h", b);
        if (r == 1) begin
          if (addr < 32'h10000) rom_b[addr] = b[7:0]; else dmem[addr & 32'hFFFF] = b[7:0];
          addr = addr + 1;
        end else r = $fgetc(h);
      end
    end
    $fclose(h);
    for (i = 0; i < 4096; i = i + 1)
      for (j = 0; j < 16; j = j + 1) u_rom.rom[i][127 - 8*j -: 8] = rom_b[16*i + j];

    repeat (4) @(posedge clk);
    #1 rst = 0;
    while (!halted && cycles < timeout) @(posedge clk);
    repeat (2) @(posedge clk);
    if ($value$plusargs("STORES=%d", expected_stores) && stores !== expected_stores)
      $fatal(1, "Escrituras aceptadas: %0d, esperadas: %0d", stores, expected_stores);
    if (!halted) $display("TIMEOUT tras %0d ciclos", cycles);
    $display("HALT cycles=%0d bundles=%0d illegal=%0d hazards_raw=%0d hazards_waw=%0d SR=%08h stalls_inyectados=%0d ciclos_stall=%0d",
             cycles, bundles_exec, illegal_cnt, raw_count, waw_count, u_core.sr, injected, stalled_cycles);
    if ($value$plusargs("REGS=%s", regs_f)) begin
      fd = $fopen(regs_f, "w");
      for (i = 0; i < 32; i = i + 1) $fdisplay(fd, "r%0d %08h", i, u_core.u_regfile.regs[i]);
      $fdisplay(fd, "sr %08h", u_core.sr);
      $fdisplay(fd, "cycles %0d", cycles);
      $fdisplay(fd, "bundles %0d", bundles_exec);
      $fdisplay(fd, "illegal %0d", illegal_cnt);
      $fdisplay(fd, "hazards %0d", raw_count + waw_count);
      $fclose(fd);
    end
    if ($value$plusargs("DUMP=%s", dump_f)) begin
      if (!$value$plusargs("DUMPLO=%d", dlo)) dlo = 65536;
      if (!$value$plusargs("DUMPHI=%d", dhi)) dhi = 69631;
      fd = $fopen(dump_f, "w");
      $fdisplay(fd, "@%08h", dlo);
      for (i = dlo; i <= dhi; i = i + 1) $fdisplay(fd, "%02h", dmem[i & 32'hFFFF]);
      $fclose(fd);
    end
    $finish;
  end
endmodule
