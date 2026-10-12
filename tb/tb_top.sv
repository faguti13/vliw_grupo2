// Testbench de sistema completo
// Carga un programa en memoria, lo ejecuta hasta que el procesador se detiene y al fianl 
// muestra/guarda lo que se quedó en registros y memoria.
// Se controla con plusargs: +PROG=f.mem +DATA=f.mem +REGS=f +DUMP=f +DUMPLO=n +DUMPHI=n +TIMEOUT=ciclos +TRACE +VCD=f

module tb_top;
  logic clk = 0, rst = 1;
  logic halted; logic [31:0] illegal_cnt, bundles_exec, cycles;
  
  //Probando el sistema completo
  top dut (.clk(clk), .rst(rst), .halted(halted), .illegal_cnt(illegal_cnt),
           .bundles_exec(bundles_exec), .cycles(cycles));

  always #5 clk = ~clk; //Reloj

  // Monitor de hazards conectado al pipeline interno del core
  integer raw_count, waw_count;
  logic trace;
  hazard_monitor u_haz (.clk(clk), .rst(rst),
      .ifid_bundle(dut.u_core.ifid_bundle), .ifid_valid(dut.u_core.ifid_valid), .ex_flush(dut.u_core.ex_flush),
      .idex_bundle(dut.u_core.idex_bundle), .idex_valid(dut.u_core.idex_valid),
      .exwb_wen(dut.u_core.exwb_wen), .exwb_waddr(dut.u_core.exwb_waddr), .trace(trace),
      .raw_count(raw_count), .waw_count(waw_count));

  // Variables de control de simulacion
  string prog, data, regs_f, dump_f, vcd_f;
  integer timeout, dlo, dhi, i, fd;

  // Traza por ciclo
  // Se muestra en consola lo que pasa en EX y WB cuando +TRACE está activo
  always @(posedge clk) begin
    if (trace && !rst) begin

      // Bundle que está en EX
      if (dut.u_core.idex_valid)
        $display("[%0d] EX pc=%08h  %08h|%08h|%08h|%08h  %s", cycles, dut.u_core.idex_pc,
                 dut.u_core.e0, dut.u_core.e1, dut.u_core.e2, dut.u_core.e3,
                 dut.u_core.ex_taken ? "SALTO TOMADO" : "");

      // Si hubo salto, muestra  el destino y los bundles descartados
      if (dut.u_core.ex_taken) $display("[%0d]    salto -> %08h (se descartan 2 bundles)", cycles, dut.u_core.ex_target);
      
      // Escritura que están en WB
      for (i = 0; i < 5; i = i + 1)
        if (dut.u_core.exwb_wen[i] && dut.u_core.exwb_waddr[5*i +: 5] != 0)
          $display("[%0d]    WB r%0d <= %08h", cycles, dut.u_core.exwb_waddr[5*i +: 5], dut.u_core.exwb_wdata[32*i +: 32]);
      // Escrituras a memoria de datos
      if (dut.u_core.dmem_we)
        $display("[%0d]    MEM[%08h] <= %08h", cycles, dut.u_core.dmem_addr, dut.u_core.dmem_wdata);
    end
  end

  // Detecta cambios en el registro de estado y los imprime
  logic [31:0] sr_prev;
  always @(posedge clk) begin
    if (trace && !rst && dut.u_core.sr !== sr_prev) $display("[%0d]    SR = %08h", cycles, dut.u_core.sr);
    sr_prev <= dut.u_core.sr;
  end

  initial begin
    // Lee los plusargs 
    trace = $test$plusargs("TRACE");
    if (!$value$plusargs("TIMEOUT=%d", timeout)) timeout = 2000000;
    if ($value$plusargs("VCD=%s", vcd_f)) begin $dumpfile(vcd_f); $dumpvars(0, tb_top); end

    // Carga programa y datos en memoria 
    if ($value$plusargs("PROG=%s", prog)) $readmemh(prog, dut.u_mem.mem);
    if ($value$plusargs("DATA=%s", data)) $readmemh(data, dut.u_mem.mem);
    
    // Reset (4 ciclos en alto, luego se libera)
    repeat (4) @(posedge clk);
    #1 rst = 0;
    while (!halted && cycles < timeout) @(posedge clk);
    repeat (2) @(posedge clk);
    if (!halted) $display("TIMEOUT tras %0d ciclos", cycles);

    // Reporte final en consola
    $display("HALT cycles=%0d bundles=%0d illegal=%0d hazards_raw=%0d hazards_waw=%0d SR=%08h",
             cycles, bundles_exec, illegal_cnt, raw_count, waw_count, dut.u_core.sr);
    
    // Si se pidió +REGS, guarda los registros en un archivo
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

    // Si se pidió +DUMP, guarda un rango de memoria en un archivo
    if ($value$plusargs("DUMP=%s", dump_f)) begin
      if (!$value$plusargs("DUMPLO=%d", dlo)) dlo = 65536;
      if (!$value$plusargs("DUMPHI=%d", dhi)) dhi = 69631;
      fd = $fopen(dump_f, "w");
      $fdisplay(fd, "@%08h", dlo);
      for (i = dlo; i <= dhi; i = i + 1) $fdisplay(fd, "%02h", dut.u_mem.mem[i]);
      $fclose(fd);
    end
    $finish;
  end
endmodule
