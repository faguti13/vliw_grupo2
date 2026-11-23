// Contadores de desempeño del pipeline.
module perf_counters (
  input  logic        clk,
  input  logic        rst,
  input  logic        halted,
  input  logic        ev_adv,      // un bundle valido termina EX
  input  logic        ev_taken,    // salto tomado (descarta 2 bundles)
  input  logic [2:0]  ev_instr,    // instrucciones no-NOP del bundle que termina EX
  input  logic        stall,       // cache_stall
  output logic [31:0] cycles_total,
  output logic [31:0] bundles_exec,
  output logic [31:0] instr_exec,
  output logic [31:0] l1d_stall_cycles,
  output logic [31:0] branch_stall_cycles,
  output logic [31:0] stall_events   // episodios de stall, aunque duren varios ciclos
);
  logic stall_q;
  always @(posedge clk) begin
    if (rst) begin
      cycles_total <= 0; bundles_exec <= 0; instr_exec <= 0;
      l1d_stall_cycles <= 0; branch_stall_cycles <= 0; stall_events <= 0; stall_q <= 1'b0;
    end else if (!halted) begin
      cycles_total <= cycles_total + 1;
      stall_q      <= stall;
      if (ev_adv)   bundles_exec <= bundles_exec + 1;
      instr_exec <= instr_exec + 32'(ev_instr);
      if (stall)    l1d_stall_cycles <= l1d_stall_cycles + 1;
      if (stall && !stall_q) stall_events <= stall_events + 1;
      if (ev_taken) branch_stall_cycles <= branch_stall_cycles + 2;
    end
  end
endmodule
