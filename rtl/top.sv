// ROM de instrucciones y memoria de datos del procesador VLIW.
module top #(parameter int MEM_BYTES = 1 << 20,            // 1 MB de memoria
             parameter logic [31:0] CRED = 32'hCAFE1234) ( // credencial por defecto
  input  logic        clk,
  input  logic        rst,
  output logic        halted,       // procesador detenido
  output logic [31:0] illegal_cnt,  // contador de instr ilegales
  output logic [31:0] bundles_exec, // bundles ejecutados
  output logic [31:0] cycles        // ciclos transcurridos
);
  logic [31:0]  imem_addr, dmem_addr, dmem_wdata, dmem_rdata;
  logic [127:0] imem_data;         // bundle de 4 slots
  logic         imem_en;
  logic         ev_adv, ev_taken, dmem_stall;
  logic [2:0]   ev_instr;
  logic [31:0]  p_cycles, p_bundles, p_instr, p_l1d_stall, p_branch_stall, p_stall_events;
  logic         dmem_we;           // write enable de datos

  // Procesador - lee instr, lee/escribe datos
  core #(.CRED(CRED)) u_core (.clk(clk), .rst(rst), .imem_addr(imem_addr), .imem_en(imem_en), .imem_data(imem_data),
      .dmem_addr(dmem_addr), .dmem_stall(dmem_stall), .dmem_re(), .dmem_we(dmem_we), .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
      .halted(halted), .illegal_cnt(illegal_cnt), .bundles_exec(bundles_exec), .cycles(cycles),
      .ev_adv(ev_adv), .ev_taken(ev_taken), .ev_instr(ev_instr));

  perf_counters u_perf (.clk(clk), .rst(rst), .halted(halted), .stall(dmem_stall),
      .ev_adv(ev_adv), .ev_taken(ev_taken), .ev_instr(ev_instr),
      .cycles_total(p_cycles), .bundles_exec(p_bundles), .instr_exec(p_instr),
      .l1d_stall_cycles(p_l1d_stall), .branch_stall_cycles(p_branch_stall), .stall_events(p_stall_events));

  inst_rom u_rom (.clk(clk), .rst(rst), .en(imem_en), .addr(imem_addr), .data(imem_data));

  // La memoria de datos del proyecto I responde sin espera.
  assign dmem_stall = 1'b0;
  memory #(.MEM_BYTES(MEM_BYTES)) u_mem (.clk(clk), .fetch_addr(32'b0), .fetch_data(),
      .d_addr(dmem_addr), .d_rdata(dmem_rdata), .d_we(dmem_we), .d_wdata(dmem_wdata));
endmodule
