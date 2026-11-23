// top.sv - Procesador VLIW Feistel4 + jerarquia de datos (Proyecto II, Harvard).
// Politica de L2 fija: inclusiva.
// MODE: 0 ideal, 1 sin cache, 2 solo L1, 3 L1+L2 (por omision).
module top #(
  parameter int MODE        = 3,
  parameter bit L1_WT       = 1'b0,
  parameter bit BUFFER_FWD  = 1'b1,
  parameter int WB_DEPTH    = 4,
  parameter int EB_DEPTH    = 8,
  parameter int MEM_CLK_DIV = 4,
  parameter int T_FIRST     = 25,
  parameter int L2_HIT      = 8,
  parameter logic [31:0] CRED = 32'hCAFE1234
) (
  input  logic        clk,
  input  logic        rst,
  output logic        halted,
  output logic [31:0] illegal_cnt,
  output logic [31:0] bundles_exec,
  output logic [31:0] cycles
);
  logic [31:0]  imem_addr, dmem_addr, dmem_wdata, dmem_rdata, core_cycles;
  logic [127:0] imem_data;
  logic         imem_en, dmem_re, dmem_we, dmem_stall;
  logic         ev_adv, ev_taken;
  logic [2:0]   ev_instr;
  logic [31:0]  c_stall_l2, c_stall_dram, c_stall_other;
  logic [31:0]  p_cycles, p_bundles, p_instr, p_l1d_stall, p_branch_stall, p_stall_events;

  assign cycles = p_cycles;

  core #(.CRED(CRED)) u_core (
    .clk(clk), .rst(rst),
    .imem_addr(imem_addr), .imem_en(imem_en), .imem_data(imem_data),
    .dmem_addr(dmem_addr), .dmem_re(dmem_re), .dmem_we(dmem_we),
    .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata), .dmem_stall(dmem_stall),
    .halted(halted), .illegal_cnt(illegal_cnt), .bundles_exec(bundles_exec),
    .cycles(core_cycles),
    .ev_adv(ev_adv), .ev_taken(ev_taken), .ev_instr(ev_instr));

  inst_rom u_rom (.clk(clk), .rst(rst), .en(imem_en), .addr(imem_addr), .data(imem_data));

  mem_subsystem #(
    .MODE(MODE), .L1_WT(L1_WT), .BUFFER_FWD(BUFFER_FWD),
    .WB_DEPTH(WB_DEPTH), .EB_DEPTH(EB_DEPTH), .MEM_CLK_DIV(MEM_CLK_DIV),
    .T_FIRST(T_FIRST), .L2_HIT(L2_HIT)
  ) u_mem (
    .clk(clk), .rst(rst),
    .re(dmem_re), .we(dmem_we), .addr(dmem_addr), .wdata(dmem_wdata),
    .rdata(dmem_rdata), .stall(dmem_stall),
    .c_stall_l2(c_stall_l2), .c_stall_dram(c_stall_dram), .c_stall_other(c_stall_other));

  perf_counters u_perf (
    .clk(clk), .rst(rst), .halted(halted),
    .ev_adv(ev_adv), .ev_taken(ev_taken), .ev_instr(ev_instr), .stall(dmem_stall),
    .cycles_total(p_cycles), .bundles_exec(p_bundles), .instr_exec(p_instr),
    .l1d_stall_cycles(p_l1d_stall), .branch_stall_cycles(p_branch_stall),
    .stall_events(p_stall_events));
endmodule
