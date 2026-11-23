// mem_subsystem.sv - Jerarquia de memoria de datos del Proyecto II.
//
//   core (EX) <-> L1-D <-> [arbitro L2] <-> L2 <-> [arbitro DRAM] <-> dram_ctrl (clk_mem)
//                  |            ^             |          ^
//                  +-> write buffer ----------+          |
//                                             +-> eviction buffer
//
// MODE: 0 = memoria ideal de 1 ciclo (sin stalls, referencia funcional)
//       1 = sin cache: cada CP/AP va a la DRAM y paga Tmem (linea base de la Iteracion 2)
//       2 = solo L1-D (con write buffer) sobre la DRAM
//       3 = L1-D + L2 + write buffer + eviction buffer (configuracion completa, por omision)
// Arbitro de L2: el fill de L1 (demanda) tiene prioridad sobre el drenado del write buffer.
// Arbitro de DRAM: la lectura de L2 (o del modo sin cache) tiene prioridad sobre el drenado
// del eviction buffer.
// peek_byte(): vista coherente de un byte (L1 > write buffer > L2 > eviction buffer > DRAM)
// para el volcado del testbench; no es un puerto de hardware.
// Politica de L2 fija: inclusiva.
module mem_subsystem #(
  parameter int MODE        = 3,
  parameter bit L1_WT       = 1'b0,
  parameter bit BUFFER_FWD  = 1'b1,
  parameter int WB_DEPTH    = 4,
  parameter int EB_DEPTH    = 8,
  parameter int MEM_CLK_DIV = 4,
  parameter int T_FIRST     = 25,
  parameter int L2_HIT      = 8
) (
  input  logic        clk,
  input  logic        rst,
  input  logic        re,
  input  logic        we,
  input  logic [31:0] addr,
  input  logic [31:0] wdata,
  output logic [31:0] rdata,
  output logic        stall,
  // ciclos de stall por causa (para el analisis de desempeño)
  output logic [31:0] c_stall_l2,       // misses de L1 cuya linea vino de L2 o del eviction buffer
  output logic [31:0] c_stall_dram,     // misses que necesitaron la DRAM (y todo el modo sin cache)
  output logic [31:0] c_stall_other     // write buffer lleno o snoop
);
  localparam bit USE_L1 = (MODE >= 2);
  localparam bit USE_L2 = (MODE == 3);

  logic [15:0] a;
  assign a = addr[15:0];

  // ---------------- Reloj de memoria y DRAM ----------------
  logic clk_mem;
  clk_div #(.DIV(MEM_CLK_DIV)) u_clkdiv (.clk(clk), .clk_out(clk_mem));

  logic         d_req, d_we, d_idle, d_done;
  logic [10:0]  d_la;
  logic [255:0] d_wdata, d_rdata;
  logic [7:0]   d_wmask;
  logic [31:0]  i_rdata;
  logic [31:0]  dram_reads, dram_writes, dram_busy;
  logic         dram_err;
  dram_ctrl #(.DIV(MEM_CLK_DIV), .T_FIRST(T_FIRST), .IDEAL(MODE == 0)) u_dram (
    .clk(clk), .rst(rst), .clk_mem(clk_mem),
    .req(d_req), .we(d_we), .la(d_la), .wdata(d_wdata), .wmask(d_wmask),
    .idle(d_idle), .done(d_done), .rdata(d_rdata),
    .i_addr(a), .i_we(MODE == 0 && we), .i_wdata(wdata), .i_rdata(i_rdata),
    .cnt_reads(dram_reads), .cnt_writes(dram_writes), .cnt_busy(dram_busy), .err_timeout(dram_err));

  // ---------------- L1-D, write buffer, L2, eviction buffer ----------------
  logic         l2_req, l2_op, l2_idle, l2_done;
  logic [10:0]  l2_la;
  logic [255:0] l2_wdata, l2_rdata;
  logic [7:0]   l2_wmask;
  logic         grant_l1;
  logic         l1_stall;
  logic [31:0]  l1_rdata;
  logic         wb_push, wb_push_ready, wb_q_hit;
  logic [10:0]  wb_push_la, wb_q_la;
  logic [255:0] wb_push_data, wb_q_data;
  logic [7:0]   wb_push_mask, wb_q_mask;
  logic         fill_req, fill_done;
  logic [10:0]  fill_la;
  logic         snoop_req, snoop_hit, snoop_dirty;
  logic [10:0]  snoop_la;
  logic [255:0] snoop_line;
  logic [31:0]  l1_rd_acc, l1_wr_acc, l1_rd_hit, l1_rd_miss, l1_wr_hit, l1_wr_miss;
  logic [31:0]  l1_back_inv, l1_wb_full_stall, l1_fwd_fill, l1_dirty_evict, l1_drain_wait;

  l1d_cache #(.L1_WT(L1_WT), .BUFFER_FWD(BUFFER_FWD)) u_l1 (
    .clk(clk), .rst(rst),
    .rd(USE_L1 && re), .wr(USE_L1 && we), .addr(a), .wdata(wdata), .rdata(l1_rdata), .stall(l1_stall),
    .wb_push(wb_push), .wb_push_la(wb_push_la), .wb_push_data(wb_push_data), .wb_push_mask(wb_push_mask),
    .wb_push_ready(wb_push_ready), .wb_q_la(wb_q_la), .wb_q_hit(wb_q_hit), .wb_q_data(wb_q_data), .wb_q_mask(wb_q_mask),
    .fill_req(fill_req), .fill_la(fill_la), .fill_done(fill_done), .fill_line(l2_rdata),
    .snoop_req(snoop_req), .snoop_la(snoop_la), .snoop_hit(snoop_hit), .snoop_dirty(snoop_dirty), .snoop_line(snoop_line),
    .c_rd_acc(l1_rd_acc), .c_wr_acc(l1_wr_acc), .c_rd_hit(l1_rd_hit), .c_rd_miss(l1_rd_miss),
    .c_wr_hit(l1_wr_hit), .c_wr_miss(l1_wr_miss), .c_back_inv(l1_back_inv), .c_wb_full_stall(l1_wb_full_stall),
    .c_fwd_fill(l1_fwd_fill), .c_dirty_evict(l1_dirty_evict), .c_drain_wait(l1_drain_wait));

  logic         wbh_valid, wb_pop;
  logic [10:0]  wbh_la;
  logic [255:0] wbh_data;
  logic [7:0]   wbh_mask;
  logic [$clog2(WB_DEPTH+1)-1:0] wb_count;
  logic [31:0]  wb_pushes, wb_merges;
  logic [1:0]   l2_owner;          // 0 libre, 1 fill de L1, 2 write buffer
  localparam logic [1:0] OWN_NONE = 2'd0, OWN_L1 = 2'd1, OWN_WB = 2'd2;

  write_buffer #(.DEPTH(WB_DEPTH)) u_wb (
    .clk(clk), .rst(rst),
    .push(wb_push), .push_la(wb_push_la), .push_data(wb_push_data), .push_mask(wb_push_mask), .push_ready(wb_push_ready),
    .head_valid(wbh_valid), .head_la(wbh_la), .head_data(wbh_data), .head_mask(wbh_mask),
    .head_busy(l2_owner == OWN_WB || (l2_req && !grant_l1)), .pop(wb_pop),
    .q_la(wb_q_la), .q_hit(wb_q_hit), .q_data(wb_q_data), .q_mask(wb_q_mask),
    .count(wb_count), .cnt_pushes(wb_pushes), .cnt_merges(wb_merges));

  // Arbitro de L2
  assign grant_l1 = fill_req;
  assign l2_req   = l2_idle && (fill_req || wbh_valid);
  assign l2_op    = !grant_l1;
  assign l2_la    = grant_l1 ? fill_la : wbh_la;
  assign l2_wdata = wbh_data;
  assign l2_wmask = wbh_mask;
  assign fill_done = l2_done && l2_owner == OWN_L1;
  assign wb_pop    = l2_done && l2_owner == OWN_WB;

  always @(posedge clk) begin
    if (rst) l2_owner <= OWN_NONE;
    else if (l2_req) l2_owner <= grant_l1 ? OWN_L1 : OWN_WB;
    else if (l2_done) l2_owner <= OWN_NONE;
  end

  logic         eb_push, eb_full, eb_empty, ebh_valid, eb_pop, eb_q_hit;
  logic [10:0]  eb_push_la, ebh_la, eb_q_la;
  logic [255:0] eb_push_line, ebh_line, eb_q_line;
  logic [$clog2(EB_DEPTH+1)-1:0] eb_count;
  logic [31:0]  eb_pushes, eb_max_occ;
  logic         l2m_req, l2m_we, l2m_gnt, l2m_done;
  logic [10:0]  l2m_la;
  logic [255:0] l2m_wdata;
  logic [7:0]   l2m_wmask;
  logic [31:0]  l2_acc, l2_rd_acc, l2_wr_acc, l2_hit, l2_miss, l2_eb_fwd, l2_dirty_evict;
  logic [31:0]  l2_snoops, l2_eb_full_wait, l2_mem_wait;

  l2_cache #(.BUFFER_FWD(BUFFER_FWD), .L2_EN(USE_L2), .HIT_LAT(L2_HIT)) u_l2 (
    .clk(clk), .rst(rst),
    .req(l2_req), .op_wr(l2_op), .la(l2_la), .wdata(l2_wdata), .wmask(l2_wmask),
    .idle(l2_idle), .done(l2_done), .rdata(l2_rdata),
    .snoop_req(snoop_req), .snoop_la(snoop_la), .snoop_hit(snoop_hit), .snoop_dirty(snoop_dirty), .snoop_line(snoop_line),
    .eb_push(eb_push), .eb_push_la(eb_push_la), .eb_push_line(eb_push_line), .eb_full(eb_full),
    .eb_q_la(eb_q_la), .eb_q_hit(eb_q_hit), .eb_q_line(eb_q_line),
    .mem_req(l2m_req), .mem_we(l2m_we), .mem_la(l2m_la), .mem_wdata(l2m_wdata), .mem_wmask(l2m_wmask),
    .mem_gnt(l2m_gnt), .mem_done(l2m_done), .mem_rdata(d_rdata),
    .c_acc(l2_acc), .c_rd_acc(l2_rd_acc), .c_wr_acc(l2_wr_acc), .c_hit(l2_hit), .c_miss(l2_miss),
    .c_eb_fwd(l2_eb_fwd), .c_dirty_evict(l2_dirty_evict), .c_snoops(l2_snoops),
    .c_eb_full_wait(l2_eb_full_wait), .c_mem_wait(l2_mem_wait));

  eviction_buffer #(.DEPTH(EB_DEPTH)) u_eb (
    .clk(clk), .rst(rst),
    .push(eb_push), .push_la(eb_push_la), .push_line(eb_push_line), .full(eb_full), .empty(eb_empty),
    .head_valid(ebh_valid), .head_la(ebh_la), .head_line(ebh_line), .pop(eb_pop),
    .q_la(eb_q_la), .q_hit(eb_q_hit), .q_line(eb_q_line), .count(eb_count),
    .cnt_pushes(eb_pushes), .cnt_max_occupancy(eb_max_occ));

  // ---------------- Modo sin cache (MODE 1) ----------------
  logic        byp_busy;
  logic        byp_access;
  assign byp_access = (MODE == 1) && (re || we);

  // ---------------- Arbitro de DRAM ----------------
  // dueño de la operacion en curso: 0 = L2 / sin cache, 1 = eviction buffer
  logic d_owner_eb;
  logic eb_go;
  assign l2m_gnt = d_idle && l2m_req;
  assign eb_go   = d_idle && !l2m_req && !(byp_access && !byp_busy) && ebh_valid;
  always @* begin
    d_req = 1'b0; d_we = 1'b0; d_la = l2m_la; d_wdata = l2m_wdata; d_wmask = l2m_wmask;
    if (MODE == 1) begin
      d_req   = byp_access && !byp_busy;
      d_we    = we;
      d_la    = a[15:5];
      d_wdata = {8{wdata}};
      d_wmask = we ? (8'b1 << a[4:2]) : 8'h00;
    end else if (l2m_req) begin
      d_req = 1'b1; d_we = l2m_we;
    end else if (eb_go) begin
      d_req = 1'b1; d_we = 1'b1; d_la = ebh_la; d_wdata = ebh_line; d_wmask = 8'hFF;
    end
  end
  assign l2m_done = d_done && !d_owner_eb;
  assign eb_pop   = d_done && d_owner_eb;

  always @(posedge clk) begin
    if (rst) begin d_owner_eb <= 1'b0; byp_busy <= 1'b0; end
    else begin
      if (d_idle && d_req) d_owner_eb <= (MODE != 1) && !l2m_req;
      if (MODE == 1) begin
        if (byp_access && !byp_busy && d_idle) byp_busy <= 1'b1;
        else if (byp_busy && d_done)           byp_busy <= 1'b0;
      end
    end
  end

  // ---------------- Salida hacia el core ----------------
  always @* begin
    case (MODE)
      0:       begin rdata = i_rdata; stall = 1'b0; end
      1:       begin rdata = d_rdata[32*a[4:2] +: 32]; stall = byp_access && !(byp_busy && d_done); end
      default: begin rdata = l1_rdata; stall = l1_stall; end
    endcase
  end

  // Ciclos de stall por causa. Un episodio de miss de L1 se acumula en `ep` y al terminar se
  // suma a c_stall_dram si la linea tuvo que venir de la DRAM, o a c_stall_l2 si vino de L2 / EB.
  logic [31:0] ep;
  logic        ep_dram, miss_cause;
  assign miss_cause = MODE >= 2 && (u_l1.need_fill || u_l1.state != 2'd0);
  always @(posedge clk) begin
    if (rst) begin
      c_stall_l2 <= '0; c_stall_dram <= '0; c_stall_other <= '0; ep <= '0; ep_dram <= 1'b0;
    end else begin
      if (stall && miss_cause) begin
        ep <= ep + 1;
        if (l2_owner == OWN_L1 && (l2m_req || u_l2.state == 3'd4)) ep_dram <= 1'b1;
      end else if (stall) begin
        if (MODE == 1) c_stall_dram <= c_stall_dram + 1;
        else           c_stall_other <= c_stall_other + 1;
      end
      if (!stall && ep != 0) begin
        if (ep_dram) c_stall_dram <= c_stall_dram + ep;
        else         c_stall_l2   <= c_stall_l2 + ep;
        ep <= '0; ep_dram <= 1'b0;
      end
    end
  end

  // ---------------- Vista coherente para el testbench ----------------
  function automatic logic [7:0] peek_byte(input logic [15:0] pa);
    logic [255:0] line;
    logic         found;
    logic [10:0]  pla;
    logic [5:0]   i1;
    logic [6:0]   i2;
    int           p, n;
    pla = pa[15:5];
    i1  = pa[10:5];
    i2  = pa[11:5];
    if (MODE == 0 || MODE == 1) return u_dram.peek(pa);
    found = 1'b0;
    line  = '0;
    // base: L2, si no la victima que espera lugar en el eviction buffer, si no el eviction buffer
    // (la copia mas nueva), si no la DRAM
    for (int w = 0; w < 4; w++)
      if (u_l2.val[w][i2] && u_l2.tag[w][i2] == pa[15:12]) begin line = u_l2.dat[w][i2]; found = 1'b1; end
    if (!found && u_l2.state == 3'd2 && u_l2.vic_la_r == pla) begin line = u_l2.vic_line_r; found = 1'b1; end
    if (!found) begin
      p = int'(u_eb.head);
      n = int'(u_eb.count);
      for (int i = 0; i < EB_DEPTH; i++) begin
        if (i < n && u_eb.la_q[p] == pla) begin line = u_eb.line_q[p]; found = 1'b1; end
        p = (p == EB_DEPTH - 1) ? 0 : p + 1;
      end
    end
    if (!found)
      for (int wd = 0; wd < 8; wd++)
        line[32*wd +: 32] = {u_dram.peek({pla, 5'b0} + 16'(4*wd)), u_dram.peek({pla, 5'b0} + 16'(4*wd + 1)),
                             u_dram.peek({pla, 5'b0} + 16'(4*wd + 2)), u_dram.peek({pla, 5'b0} + 16'(4*wd + 3))};
    // escrituras pendientes del write buffer, de la mas vieja a la mas nueva
    p = int'(u_wb.head);
    n = int'(u_wb.count);
    for (int i = 0; i < WB_DEPTH; i++) begin
      if (i < n && u_wb.la_q[p] == pla)
        for (int wd = 0; wd < 8; wd++)
          if (u_wb.mask_q[p][wd]) line[32*wd +: 32] = u_wb.data_q[p][32*wd +: 32];
      p = (p == WB_DEPTH - 1) ? 0 : p + 1;
    end
    // la copia de L1, si existe, es la mas reciente
    for (int w = 0; w < 2; w++)
      if (u_l1.val[w][i1] && u_l1.tag[w][i1] == pa[15:11]) line = u_l1.dat[w][i1];
    return line[32*int'(pa[4:2]) + 8*(3 - int'(pa[1:0])) +: 8];
  endfunction
endmodule
