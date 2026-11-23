// tb_l2_coherence.sv — L2 inclusiva sola. No instancia L1, DRAM ni el eviction buffer:
// este banco hace de los tres.
//   L1: responde snoop_hit / snoop_dirty / snoop_line.
//   Eviction buffer: guarda lo que L2 empuja y contesta eb_q_*.
//   DRAM: devuelve la linea DRAM_LAT ciclos despues de aceptar mem_req.
// El pipeline ve HIT_LAT = 8 ciclos de stall en un hit de L2 porque L1 gasta 3 fuera
// de este modulo (la busqueda interna dura LK = 5). Un miss limpio son esos 8 mas Tmem.
// No hay modo NINE: la politica del modulo es inclusiva fija.
module tb_l2_coherence;
  localparam int HIT_LAT  = 8;
  localparam int L1_OVH   = 3;
  localparam int TMEM     = 53;
  localparam int DRAM_LAT = 52; // el stub cuenta de forma que el miss visible queda en 8 + Tmem

  logic clk = 0, rst = 1;
  always #5 clk = ~clk;

  logic         req, op_wr, idle, done, snoop_req, snoop_hit, snoop_dirty;
  logic         eb_push, eb_full, eb_q_hit, mem_req, mem_we, mem_gnt, mem_done;
  logic [10:0]  la, snoop_la, eb_push_la, eb_q_la, mem_la;
  logic [255:0] wdata, rdata, snoop_line, eb_push_line, eb_q_line, mem_wdata, mem_rdata;
  logic [7:0]   wmask, mem_wmask;
  logic [31:0]  c_acc, c_rd_acc, c_wr_acc, c_hit, c_miss, c_eb_fwd, c_dirty_evict;
  logic [31:0]  c_snoops, c_eb_full_wait, c_mem_wait;

  l2_cache #(.BUFFER_FWD(1'b1), .L2_EN(1'b1), .HIT_LAT(HIT_LAT)) dut (
    .clk(clk), .rst(rst), .req(req), .op_wr(op_wr), .la(la), .wdata(wdata), .wmask(wmask),
    .idle(idle), .done(done), .rdata(rdata),
    .snoop_req(snoop_req), .snoop_la(snoop_la), .snoop_hit(snoop_hit), .snoop_dirty(snoop_dirty),
    .snoop_line(snoop_line),
    .eb_push(eb_push), .eb_push_la(eb_push_la), .eb_push_line(eb_push_line), .eb_full(eb_full),
    .eb_q_la(eb_q_la), .eb_q_hit(eb_q_hit), .eb_q_line(eb_q_line),
    .mem_req(mem_req), .mem_we(mem_we), .mem_la(mem_la), .mem_wdata(mem_wdata), .mem_wmask(mem_wmask),
    .mem_gnt(mem_gnt), .mem_done(mem_done), .mem_rdata(mem_rdata),
    .c_acc(c_acc), .c_rd_acc(c_rd_acc), .c_wr_acc(c_wr_acc), .c_hit(c_hit), .c_miss(c_miss),
    .c_eb_fwd(c_eb_fwd), .c_dirty_evict(c_dirty_evict), .c_snoops(c_snoops),
    .c_eb_full_wait(c_eb_full_wait), .c_mem_wait(c_mem_wait));

  // ---- stub de L1: una linea, la que el caso de prueba deja sucia ----
  logic         l1_v, l1_d;
  logic [10:0]  l1_a;
  logic [255:0] l1_line;
  assign snoop_hit   = snoop_req && l1_v && snoop_la == l1_a;
  assign snoop_dirty = snoop_hit && l1_d;
  assign snoop_line  = l1_line;

  // ---- stub del eviction buffer ----
  logic [10:0]  eb_la [0:7];
  logic [255:0] eb_line [0:7];
  logic [3:0]   eb_n;
  logic [10:0]  eb_last_la;
  logic [255:0] eb_last_line;
  integer       eb_pushes;
  logic         eb_seed_we, eb_clear;
  logic [10:0]  eb_seed_la;
  logic [255:0] eb_seed_line;
  assign eb_full = eb_n == 4'd8;

  always @* begin
    eb_q_hit  = 1'b0;
    eb_q_line = '0;
    for (int i = 0; i < 8; i++) begin
      if (i < eb_n && eb_la[i] == eb_q_la) begin
        eb_q_hit  = 1'b1;
        eb_q_line = eb_line[i];
      end
    end
  end

  always @(posedge clk) begin
    if (rst || eb_clear) begin
      eb_n <= '0; eb_pushes <= 0; eb_last_la <= '0; eb_last_line <= '0;
    end else if (eb_seed_we) begin
      eb_la[0] <= eb_seed_la; eb_line[0] <= eb_seed_line; eb_n <= 4'd1;
    end else if (eb_push && !eb_full) begin
      eb_la[eb_n]   <= eb_push_la;
      eb_line[eb_n] <= eb_push_line;
      eb_n          <= eb_n + 1;
      eb_pushes     <= eb_pushes + 1;
      eb_last_la    <= eb_push_la;
      eb_last_line  <= eb_push_line;
    end
  end

  // ---- stub de DRAM: lectura de linea, latencia fija, contenido por direccion ----
  function automatic logic [255:0] dram_pat(input logic [10:0] a);
    logic [255:0] r;
    for (int w = 0; w < 8; w++) r[32*w +: 32] = {8'hD0, a, w[4:0], 8'hA5};
    return r;
  endfunction

  integer       dram_cnt, dram_reads;
  logic         dram_busy;
  logic [10:0]  dram_la_r;
  assign mem_gnt = mem_req && !dram_busy && !mem_we;

  always @(posedge clk) begin
    if (rst) begin
      mem_done <= 1'b0; mem_rdata <= '0; dram_busy <= 1'b0; dram_cnt <= 0; dram_reads <= 0;
    end else begin
      mem_done <= 1'b0;
      if (mem_gnt) begin
        dram_busy <= 1'b1; dram_la_r <= mem_la; dram_cnt <= DRAM_LAT; dram_reads <= dram_reads + 1;
      end else if (dram_busy) begin
        if (dram_cnt == 1) begin
          mem_done <= 1'b1; mem_rdata <= dram_pat(dram_la_r); dram_busy <= 1'b0;
        end else dram_cnt <= dram_cnt - 1;
      end
    end
  end

  integer errors, nchecks;
  task automatic check(input string what, input logic ok);
    nchecks = nchecks + 1;
    if (!ok) begin errors = errors + 1; $display("  FAIL %s", what); end
  endtask

  task automatic acc(input logic wr, input logic [10:0] a, input logic [255:0] d, input logic [7:0] m,
                     output logic [255:0] r, output integer c);
    @(negedge clk);
    while (!idle) @(negedge clk);
    req = 1; op_wr = wr; la = a; wdata = d; wmask = m;
    @(posedge clk);
    @(negedge clk);
    req = 0; op_wr = 0;
    c = 0;
    while (!done) begin
      @(negedge clk);
      c = c + 1;
      if (c > 400) begin
        $display("FAIL timeout en %03h", a);
        $fatal(1);
      end
    end
    r = rdata;
    // El flanco siguiente cuenta el hit o el forwarding y vuelve a idle.
    @(posedge clk);
    @(negedge clk);
  endtask

  // ciclos que veria el pipeline: los de L2 mas los 3 que L1 gasta fuera del modulo
  function automatic integer cara(input integer c);
    return c + L1_OVH;
  endfunction

  integer c, hit0, miss0, sn0, ev0, fwd0, dr0, eb0;
  logic [255:0] r, sucia, l1sucia, fwd_line;
  localparam logic [10:0] P0 = 11'h000;
  localparam logic [10:0] X0 = 11'h002, X1 = 11'h082, X2 = 11'h102, X3 = 11'h182, X4 = 11'h202;
  localparam logic [10:0] A4 = 11'h004, B4 = 11'h084, C4 = 11'h104, D4 = 11'h184, E4 = 11'h204;
  localparam logic [10:0] A6 = 11'h006, B6 = 11'h086, C6 = 11'h106, D6 = 11'h186, E6 = 11'h206;
  localparam logic [10:0] F8 = 11'h008;

  initial begin
    errors = 0; nchecks = 0;
    req = 0; op_wr = 0; la = '0; wdata = '0; wmask = '0;
    l1_v = 0; l1_d = 0; l1_a = '0; l1_line = '0;
    eb_seed_we = 0; eb_clear = 0; eb_seed_la = '0; eb_seed_line = '0;
    repeat (3) @(posedge clk);
    @(negedge clk); rst = 0;
    @(negedge clk);

    // 1. miss limpio y luego hit. El hit son 8 ciclos de cara al pipeline.
    dr0 = dram_reads; hit0 = int'(c_hit); miss0 = int'(c_miss); sn0 = int'(c_snoops); eb0 = eb_pushes;
    acc(1'b0, P0, '0, 8'h00, r, c);
    check($sformatf("miss limpio: %0d ciclos de cara al pipeline (esperado %0d)", cara(c), HIT_LAT + TMEM),
          cara(c) == HIT_LAT + TMEM);
    check("miss limpio: dato de la DRAM", r == dram_pat(P0));
    check("miss limpio: una lectura a DRAM, sin snoop ni desalojo",
          dram_reads == dr0 + 1 && int'(c_miss) == miss0 + 1 && int'(c_snoops) == sn0 && eb_pushes == eb0);
    dr0 = dram_reads;
    acc(1'b0, P0, '0, 8'h00, r, c);
    check($sformatf("hit L2: %0d ciclos de cara al pipeline (esperado %0d)", cara(c), HIT_LAT),
          cara(c) == HIT_LAT);
    check("hit L2: mismo dato, sin DRAM", r == dram_pat(P0) && dram_reads == dr0 && int'(c_hit) == hit0 + 1);

    // 2. Tree-PLRU en el conjunto 2: X0..X3 llenan, se tocan X0 y X1, X4 saca a X2.
    acc(1'b0, X0, '0, 8'h00, r, c);
    acc(1'b0, X1, '0, 8'h00, r, c);
    acc(1'b0, X2, '0, 8'h00, r, c);
    acc(1'b0, X3, '0, 8'h00, r, c);
    acc(1'b0, X0, '0, 8'h00, r, c);
    check("PLRU X0 sigue (hit)", c + L1_OVH == HIT_LAT && r == dram_pat(X0));
    acc(1'b0, X1, '0, 8'h00, r, c);
    check("PLRU X1 sigue (hit)", c + L1_OVH == HIT_LAT && r == dram_pat(X1));
    sn0 = int'(c_snoops); eb0 = eb_pushes; dr0 = dram_reads;
    acc(1'b0, X4, '0, 8'h00, r, c);
    check("PLRU X4 es miss y la victima limpia X2 solo se snoopea",
          c + L1_OVH == HIT_LAT + TMEM && r == dram_pat(X4) &&
          int'(c_snoops) == sn0 + 1 && eb_pushes == eb0 && dram_reads == dr0 + 1);
    acc(1'b0, X3, '0, 8'h00, r, c);
    check("PLRU X3 sigue en L2", c + L1_OVH == HIT_LAT && r == dram_pat(X3));
    acc(1'b0, X2, '0, 8'h00, r, c);
    check("PLRU X2 fue la victima", c + L1_OVH == HIT_LAT + TMEM && r == dram_pat(X2));

    // 3. miss con victima sucia en L2. L1 no la tiene: se desaloja la linea de L2.
    sucia = {8{32'hA11CE5ED}};
    acc(1'b1, A4, sucia, 8'hFF, r, c);
    check("escritura con miss (write-allocate)", c + L1_OVH == HIT_LAT + TMEM);
    acc(1'b0, B4, '0, 8'h00, r, c);
    acc(1'b0, C4, '0, 8'h00, r, c);
    acc(1'b0, D4, '0, 8'h00, r, c);
    ev0 = int'(c_dirty_evict); eb0 = eb_pushes; fwd0 = int'(c_eb_fwd);
    acc(1'b0, E4, '0, 8'h00, r, c);
    check("victima sucia: la linea de L2 entra al eviction buffer",
          eb_pushes == eb0 + 1 && eb_last_la == A4 && eb_last_line == sucia &&
          int'(c_dirty_evict) == ev0 + 1);
    acc(1'b0, A4, '0, 8'h00, r, c);
    check("victima sucia: al releerla vuelve por forwarding, no por la DRAM",
          c + L1_OVH == HIT_LAT && r == sucia && int'(c_eb_fwd) == fwd0 + 1);

    // 4. snoop: L1 tiene la linea sucia y esa, no la de L2, es la que se desaloja.
    l1sucia = {8{32'hD1A7_0006}};
    acc(1'b0, A6, '0, 8'h00, r, c);
    acc(1'b0, B6, '0, 8'h00, r, c);
    acc(1'b0, C6, '0, 8'h00, r, c);
    acc(1'b0, D6, '0, 8'h00, r, c);
    l1_v = 1; l1_d = 1; l1_a = A6; l1_line = l1sucia;
    ev0 = int'(c_dirty_evict); sn0 = int'(c_snoops); eb0 = eb_pushes; fwd0 = int'(c_eb_fwd);
    acc(1'b0, E6, '0, 8'h00, r, c);
    check("snoop: la linea sucia de L1 es la desalojada",
          eb_pushes == eb0 + 1 && eb_last_la == A6 && eb_last_line == l1sucia &&
          eb_last_line != dram_pat(A6) && int'(c_snoops) == sn0 + 1 &&
          int'(c_dirty_evict) == ev0 + 1);
    l1_v = 0;
    acc(1'b0, A6, '0, 8'h00, r, c);
    check("snoop: A vuelve por forwarding con el dato de L1",
          c + L1_OVH == HIT_LAT && r == l1sucia && int'(c_eb_fwd) == fwd0 + 1);

    // 5. forwarding de una linea que esta solo en el eviction buffer.
    fwd_line = {8{32'hF0DA_0008}};
    eb_seed_la = F8; eb_seed_line = fwd_line; eb_seed_we = 1;
    @(posedge clk); @(negedge clk); eb_seed_we = 0;
    dr0 = dram_reads; fwd0 = int'(c_eb_fwd);
    acc(1'b0, F8, '0, 8'h00, r, c);
    check("forwarding del stub: latencia de hit y sin DRAM",
          c + L1_OVH == HIT_LAT && r == fwd_line && dram_reads == dr0 && int'(c_eb_fwd) == fwd0 + 1);
    // ya quedo instalada: un segundo hit no depende del buffer
    eb_clear = 1;
    @(posedge clk); @(negedge clk); eb_clear = 0;
    acc(1'b0, F8, '0, 8'h00, r, c);
    check("forwarding: la linea quedo en L2", c + L1_OVH == HIT_LAT && r == fwd_line);

    if (errors == 0) $display("tb_l2_coherence: PASS (%0d chequeos)", nchecks);
    else begin $display("tb_l2_coherence: FAIL (%0d errores)", errors); $fatal(1); end
    $finish;
  end
endmodule
