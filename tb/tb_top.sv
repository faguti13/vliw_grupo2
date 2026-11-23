// tb_top.sv - Sistema Harvard (Proyecto II).
// +PROG= imagen unificada: bytes < 0x10000 a ROM, resto a DRAM (addr[15:0]).
// +ROM= / +DRAM= / +DATA= cargan imagenes separadas. +DUMP usa peek_byte (vista coherente).
module tb_top #(
  parameter int MODE        = 3,
  parameter bit L1_WT       = 1'b0,
  parameter bit BUFFER_FWD  = 1'b1,
  parameter int WB_DEPTH    = 4,
  parameter int EB_DEPTH    = 8,
  parameter int MEM_CLK_DIV = 4
);
  logic clk = 0, rst = 1;
  logic halted; logic [31:0] illegal_cnt, bundles_exec, cycles;

  top #(.MODE(MODE), .L1_WT(L1_WT), .BUFFER_FWD(BUFFER_FWD),
        .WB_DEPTH(WB_DEPTH), .EB_DEPTH(EB_DEPTH), .MEM_CLK_DIV(MEM_CLK_DIV))
    dut (.clk(clk), .rst(rst), .halted(halted), .illegal_cnt(illegal_cnt),
         .bundles_exec(bundles_exec), .cycles(cycles));

  always #5 clk = ~clk;

  integer raw_count, waw_count;
  logic trace;
  hazard_monitor u_haz (.clk(clk), .rst(rst),
      .ifid_bundle(dut.u_core.ifid_bundle), .ifid_valid(dut.u_core.ifid_valid),
      .ex_flush(dut.u_core.ex_flush),
      .idex_bundle(dut.u_core.idex_bundle), .idex_valid(dut.u_core.idex_valid),
      .exwb_wen(dut.u_core.exwb_wen), .exwb_waddr(dut.u_core.exwb_waddr),
      .stall(dut.dmem_stall), .trace(trace),
      .raw_count(raw_count), .waw_count(waw_count));

  string prog, data, rom_f, dram_f, regs_f, dump_f, vcd_f;
  integer timeout, dlo, dhi, i, fd, h, r, addr, b;
  logic [7:0] tmp [0:1048575];

  task automatic load_unified(input string f);
    integer a;
    for (a = 0; a < 1048576; a = a + 1) tmp[a] = 8'h00;
    $readmemh(f, tmp);
    for (a = 0; a < 65536; a = a + 1) begin
      // ROM: 16 bytes por bundle
      if ((a % 16) == 0)
        for (int j = 0; j < 16; j = j + 1)
          dut.u_rom.rom[a/16][127 - 8*j -: 8] = tmp[a + j];
      dut.u_mem.u_dram.mem[a] = tmp[65536 + a];
      // alias: bytes en [0x10000, 0x1FFFF] ya van arriba; tambien aceptar datos en bajo
      if (tmp[a] != 8'h00 && tmp[65536 + a] == 8'h00)
        ; // codigo en bajo no pisa DRAM
    end
    // Si el .mem solo tiene datos en el alias alto, ya estan; si trae datos en bajo
    // (programas P2 con gp=0), copiar bajos a DRAM cuando no son solo codigo:
    // la convencion del Makefile es imagen unificada codigo|datos con datos en >=0x10000.
  endtask

  task automatic load_rom(input string f);
    integer a, j;
    for (a = 0; a < 65536; a = a + 1) tmp[a] = 8'h00;
    $readmemh(f, tmp);
    for (a = 0; a < 4096; a = a + 1)
      for (j = 0; j < 16; j = j + 1)
        dut.u_rom.rom[a][127 - 8*j -: 8] = tmp[16*a + j];
  endtask

  task automatic load_dram(input string f);
    integer a;
    for (a = 0; a < 65536; a = a + 1) tmp[a] = 8'h00;
    $readmemh(f, tmp);
    for (a = 0; a < 65536; a = a + 1) dut.u_mem.u_dram.mem[a] = tmp[a];
  endtask

  always @(posedge clk) begin
    if (trace && !rst) begin
      if (dut.u_core.idex_valid && !dut.dmem_stall)
        $display("[%0d] EX pc=%08h  %08h|%08h|%08h|%08h  %s", cycles, dut.u_core.idex_pc,
                 dut.u_core.e0, dut.u_core.e1, dut.u_core.e2, dut.u_core.e3,
                 dut.u_core.ex_taken ? "SALTO TOMADO" : "");
      if (dut.u_core.ex_taken) $display("[%0d]    salto -> %08h", cycles, dut.u_core.ex_target);
      for (i = 0; i < 5; i = i + 1)
        if (dut.u_core.exwb_wen[i] && dut.u_core.exwb_waddr[5*i +: 5] != 0)
          $display("[%0d]    WB r%0d <= %08h", cycles, dut.u_core.exwb_waddr[5*i +: 5],
                   dut.u_core.exwb_wdata[32*i +: 32]);
      if (dut.u_core.dmem_we && !dut.dmem_stall)
        $display("[%0d]    MEM[%08h] <= %08h", cycles, dut.u_core.dmem_addr, dut.u_core.dmem_wdata);
    end
  end

  initial begin
    trace = $test$plusargs("TRACE");
    if (!$value$plusargs("TIMEOUT=%d", timeout)) timeout = 2000000;
    if ($value$plusargs("VCD=%s", vcd_f)) begin $dumpfile(vcd_f); $dumpvars(0, tb_top); end

    if ($value$plusargs("ROM=%s", rom_f)) load_rom(rom_f);
    if ($value$plusargs("DRAM=%s", dram_f)) load_dram(dram_f);
    if ($value$plusargs("DATA=%s", data)) load_dram(data);
    if ($value$plusargs("PROG=%s", prog)) begin
      // imagen unificada: todo el archivo a un buffer grande
      for (i = 0; i < 1048576; i = i + 1) tmp[i] = 8'h00;
      $readmemh(prog, tmp);
      for (i = 0; i < 4096; i = i + 1)
        for (int j = 0; j < 16; j = j + 1)
          dut.u_rom.rom[i][127 - 8*j -: 8] = tmp[16*i + j];
      for (i = 0; i < 65536; i = i + 1) begin
        // datos en alias 0x10000+ (P1) o en bajo si el byte alto esta vacio y hay dato en 0x10000+i
        dut.u_mem.u_dram.mem[i] = tmp[32'h10000 + i];
      end
    end

    repeat (4) @(posedge clk);
    #1 rst = 0;
    while (!halted && cycles < timeout) @(posedge clk);
    repeat (2) @(posedge clk);
    if (!halted) $display("TIMEOUT tras %0d ciclos", cycles);

    $display("HALT cycles=%0d bundles=%0d illegal=%0d hazards_raw=%0d hazards_waw=%0d SR=%08h",
             cycles, bundles_exec, illegal_cnt, raw_count, waw_count, dut.u_core.sr);

    if ($value$plusargs("REGS=%s", regs_f)) begin
      fd = $fopen(regs_f, "w");
      for (i = 0; i < 32; i = i + 1) $fdisplay(fd, "r%0d %08h", i, dut.u_core.u_regfile.regs[i]);
      $fdisplay(fd, "sr %08h", dut.u_core.sr);
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
      for (i = dlo; i <= dhi; i = i + 1)
        $fdisplay(fd, "%02h", dut.u_mem.peek_byte(16'(i)));
      $fclose(fd);
    end
    $finish;
  end
endmodule
