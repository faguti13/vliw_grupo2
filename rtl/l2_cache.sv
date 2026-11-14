// l2_cache.sv - Cache L2 unificada: 16 KB, 4 vias, lineas de 32 B, 128 conjuntos, write-back.
//   offset = addr[4:0], indice = addr[11:5], tag = addr[15:12].
//   Reemplazo Tree-PLRU de 3 bits por conjunto: b0 raiz, b1 vias 0/1, b2 vias 2/3
//   (cada bit apunta lejos de la ultima via usada; la victima se sigue por los bits).
// Atiende una solicitud a la vez del arbitro (fill de L1 o drenado del write buffer):
//   op_wr = 0: lectura de linea (fill de L1).  op_wr = 1: escritura con mascara (write buffer).
// Tiempo: el pipeline ve exactamente HIT_LAT = 8 ciclos de stall en (miss L1, hit L2). L1 gasta
// 3 de esos ciclos (deteccion, solicitud, llenado), por eso la busqueda dura LK = HIT_LAT - 3.
// Politica fija: inclusiva. Un miss elige victima y, si es valida, invalida hacia atras en L1
// (snoop) y toma sus datos si alli estaba sucia. No hay modo NINE ni exclusiva.
// La victima sucia entra al eviction buffer en el mismo ciclo y la lectura a la DRAM arranca
// de inmediato (8 + Tmem ciclos sin contencion).
// Si la linea pedida esta en el eviction buffer: BUFFER_FWD = 1 la toma de ahi (forwarding),
// BUFFER_FWD = 0 espera a que se drene antes de leer la DRAM.
// L2_EN = 0 (configuracion "solo L1"): cada solicitud va directo a la DRAM.
module l2_cache #(
  parameter bit BUFFER_FWD = 1'b1,
  parameter bit L2_EN      = 1'b1,
  parameter int HIT_LAT    = 8
) (
  input  logic         clk,
  input  logic         rst,
  // solicitud desde el arbitro
  input  logic         req,
  input  logic         op_wr,
  input  logic [10:0]  la,
  input  logic [255:0] wdata,
  input  logic [7:0]   wmask,
  output logic         idle,
  output logic         done,
  output logic [255:0] rdata,
  // invalidacion hacia atras en L1
  output logic         snoop_req,
  output logic [10:0]  snoop_la,
  input  logic         snoop_hit,
  input  logic         snoop_dirty,
  input  logic [255:0] snoop_line,
  // eviction buffer
  output logic         eb_push,
  output logic [10:0]  eb_push_la,
  output logic [255:0] eb_push_line,
  input  logic         eb_full,
  output logic [10:0]  eb_q_la,
  input  logic         eb_q_hit,
  input  logic [255:0] eb_q_line,
  // DRAM
  output logic         mem_req,
  output logic         mem_we,
  output logic [10:0]  mem_la,
  output logic [255:0] mem_wdata,
  output logic [7:0]   mem_wmask,
  input  logic         mem_gnt,     // la DRAM acepta la solicitud en este ciclo
  input  logic         mem_done,
  input  logic [255:0] mem_rdata,
  // contadores (Cuadro 2)
  output logic [31:0]  c_acc, c_rd_acc, c_wr_acc, c_hit, c_miss, c_eb_fwd, c_dirty_evict,
  output logic [31:0]  c_snoops, c_eb_full_wait, c_mem_wait
);
  localparam int LK = (HIT_LAT > 3) ? HIT_LAT - 3 : 0;
  localparam logic [2:0] S_IDLE = 3'd0, S_LOOKUP = 3'd1, S_EVICT = 3'd2, S_FETCH = 3'd3,
                         S_MEMWAIT = 3'd4, S_DIRECT = 3'd5;

  logic [255:0] dat [0:3][0:127];
  logic [3:0]   tag [0:3][0:127];
  logic [127:0] val [0:3];
  logic [127:0] dty [0:3];
  logic [2:0]   plru [0:127];

  logic [2:0]   state;
  logic [7:0]   cnt;
  logic         c_op;
  logic [10:0]  c_la;
  logic [255:0] c_wdata;
  logic [7:0]   c_wmask;
  logic [1:0]   way_r;
  logic [10:0]  vic_la_r;
  logic [255:0] vic_line_r;

  logic [6:0] idx;
  logic [3:0] tg;
  assign idx = c_la[6:0];
  assign tg  = c_la[10:7];

  function automatic logic [255:0] merge(input logic [255:0] old, input logic [255:0] nw, input logic [7:0] m);
    logic [255:0] r;
    r = old;
    for (int w = 0; w < 8; w++) if (m[w]) r[32*w +: 32] = nw[32*w +: 32];
    return r;
  endfunction

  function automatic logic [1:0] plru_victim(input logic [2:0] b);
    if (!b[0]) return b[1] ? 2'd1 : 2'd0;
    else       return b[2] ? 2'd3 : 2'd2;
  endfunction

  function automatic logic [2:0] plru_touch(input logic [2:0] b, input logic [1:0] w);
    logic [2:0] r;
    r = b;
    if (w < 2) begin r[0] = 1'b1; r[1] = (w == 2'd0); end
    else       begin r[0] = 1'b0; r[2] = (w == 2'd2); end
    return r;
  endfunction

  // Busqueda
  logic [3:0] hv;
  logic       hit;
  logic [1:0] hway;
  always @* begin
    hit = 1'b0; hway = 2'd0;
    for (int w = 0; w < 4; w++) begin
      hv[w] = val[w][idx] && tag[w][idx] == tg;
      if (hv[w]) begin hit = 1'b1; hway = 2'(w); end
    end
  end

  // Victima
  logic [1:0] vway;
  always @* begin
    if      (!val[0][idx]) vway = 2'd0;
    else if (!val[1][idx]) vway = 2'd1;
    else if (!val[2][idx]) vway = 2'd2;
    else if (!val[3][idx]) vway = 2'd3;
    else                   vway = plru_victim(plru[idx]);
  end

  logic         lk_end, lk_miss;
  logic         vic_valid, vic_dirty;
  logic [10:0]  vic_la;
  logic [255:0] vic_line;
  assign lk_end    = L2_EN && state == S_LOOKUP && cnt == 8'(LK);
  assign lk_miss   = lk_end && !hit;
  assign vic_valid = val[vway][idx];
  assign vic_la    = {tag[vway][idx], idx};
  assign snoop_req = lk_miss && vic_valid;
  assign snoop_la  = vic_la;
  assign vic_dirty = vic_valid && (dty[vway][idx] || (snoop_req && snoop_hit && snoop_dirty));
  assign vic_line  = (snoop_req && snoop_hit && snoop_dirty) ? snoop_line : dat[vway][idx];

  // Victima sucia al eviction buffer (en el ciclo del miss o despues, si estaba lleno)
  assign eb_push      = (lk_miss && vic_dirty && !eb_full) || (state == S_EVICT && !eb_full);
  assign eb_push_la   = (state == S_EVICT) ? vic_la_r : vic_la;
  assign eb_push_line = (state == S_EVICT) ? vic_line_r : vic_line;

  // Traer la linea: forwarding desde el eviction buffer o lectura a la DRAM
  logic try_fetch, fetch_fwd;
  assign try_fetch = (lk_miss && !(vic_dirty && eb_full)) || (state == S_EVICT && !eb_full) || state == S_FETCH;
  assign eb_q_la   = c_la;
  assign fetch_fwd = try_fetch && BUFFER_FWD && eb_q_hit;

  always @* begin
    mem_req   = 1'b0;
    mem_we    = 1'b0;
    mem_la    = c_la;
    mem_wdata = c_wdata;
    mem_wmask = c_wmask;
    if (!L2_EN) begin
      // solo L1: la solicitud va directo a la DRAM (en el mismo ciclo en que llega)
      if (state == S_IDLE && req) begin mem_req = 1'b1; mem_we = op_wr; mem_la = la; mem_wdata = wdata; mem_wmask = wmask; end
      else if (state == S_DIRECT) begin mem_req = 1'b1; mem_we = c_op; end
    end else if (try_fetch && !eb_q_hit) mem_req = 1'b1;
  end

  // Respuesta
  logic [255:0] src_line, res_line;
  always @* begin
    if (!L2_EN)                     src_line = mem_rdata;
    else if (lk_end && hit)         src_line = dat[hway][idx];
    else if (fetch_fwd)             src_line = eb_q_line;
    else                            src_line = mem_rdata;
    res_line = c_op ? merge(src_line, c_wdata, c_wmask) : src_line;
  end
  assign rdata = src_line;
  assign done  = L2_EN ? ((lk_end && hit) || fetch_fwd || (state == S_MEMWAIT && mem_done))
                       : (state == S_MEMWAIT && mem_done);
  assign idle  = state == S_IDLE;

  logic         fill_now;      // instala la linea traida (miss)
  assign fill_now = L2_EN && (fetch_fwd || (state == S_MEMWAIT && mem_done));

  integer s, w2;
  initial begin
    for (s = 0; s < 128; s = s + 1) begin
      plru[s] = 3'b0;
      for (w2 = 0; w2 < 4; w2 = w2 + 1) begin dat[w2][s] = '0; tag[w2][s] = '0; end
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      state <= S_IDLE; cnt <= '0;
      for (int w = 0; w < 4; w++) begin val[w] <= '0; dty[w] <= '0; end
      for (int i = 0; i < 128; i++) plru[i] <= 3'b0;
      c_acc <= '0; c_rd_acc <= '0; c_wr_acc <= '0; c_hit <= '0; c_miss <= '0; c_eb_fwd <= '0;
      c_dirty_evict <= '0; c_snoops <= '0; c_eb_full_wait <= '0; c_mem_wait <= '0;
    end else begin
      case (state)
        S_IDLE: if (req) begin
          c_op <= op_wr; c_la <= la; c_wdata <= wdata; c_wmask <= wmask; cnt <= '0;
          c_acc <= c_acc + 1;
          if (op_wr) c_wr_acc <= c_wr_acc + 1; else c_rd_acc <= c_rd_acc + 1;
          if (!L2_EN) state <= mem_gnt ? S_MEMWAIT : S_DIRECT;
          else        state <= S_LOOKUP;
        end
        S_DIRECT: if (mem_gnt) state <= S_MEMWAIT;
        S_LOOKUP: begin
          if (!lk_end) cnt <= cnt + 1;
          else if (hit) begin
            c_hit <= c_hit + 1;
            plru[idx] <= plru_touch(plru[idx], hway);
            if (c_op) begin dat[hway][idx] <= res_line; dty[hway][idx] <= 1'b1; end
            state <= S_IDLE;
          end else begin
            c_miss <= c_miss + 1;
            way_r      <= vway;
            vic_la_r   <= vic_la;
            vic_line_r <= vic_line;
            val[vway][idx] <= 1'b0;
            dty[vway][idx] <= 1'b0;
            if (snoop_req) c_snoops <= c_snoops + 1;
            if (vic_dirty) c_dirty_evict <= c_dirty_evict + 1;
            if (vic_dirty && eb_full)           state <= S_EVICT;
            else if (fetch_fwd)                 state <= S_IDLE;
            else if (!eb_q_hit && mem_gnt)      state <= S_MEMWAIT;
            else                                state <= S_FETCH;
          end
        end
        S_EVICT: begin
          if (eb_full) c_eb_full_wait <= c_eb_full_wait + 1;
          else if (fetch_fwd)            state <= S_IDLE;
          else if (!eb_q_hit && mem_gnt) state <= S_MEMWAIT;
          else                           state <= S_FETCH;
        end
        S_FETCH: begin
          if (fetch_fwd)                 state <= S_IDLE;
          else if (!eb_q_hit && mem_gnt) state <= S_MEMWAIT;
        end
        S_MEMWAIT: begin
          c_mem_wait <= c_mem_wait + 1;
          if (mem_done) state <= S_IDLE;
        end
        default: state <= S_IDLE;
      endcase
      if (fill_now) begin
        // la via elegida es la del miss (en el ciclo del lookup todavia no esta en way_r)
        dat[lk_end ? vway : way_r][idx] <= res_line;
        tag[lk_end ? vway : way_r][idx] <= tg;
        val[lk_end ? vway : way_r][idx] <= 1'b1;
        dty[lk_end ? vway : way_r][idx] <= c_op;
        plru[idx] <= plru_touch(plru[idx], lk_end ? vway : way_r);
        if (fetch_fwd) c_eb_fwd <= c_eb_fwd + 1;
      end
    end
  end
endmodule
