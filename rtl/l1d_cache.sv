// Cache L1 de datos: Caché de datos L1 (4 KB, 2 vías, 32 B/línea)

//Organización
//- 64 conjuntos (sets). Dirección de 16 bits: offset addr[4:0],índice addr[10:5], tag addr[15:11].
//- LRU real de 1 bit por conjunto: 0 = vía 0 es la menos usada, 1 = vía 1 es la menos usada.

// Comportamiento:
//- Lectura/Escritura en 1 ciclo si hay hit. Los datos y tags se leen combinacionalmente.
//- En un miss, se levanta `stall` (congela el pipeline). La línea se pide a L2 (fill_req).
//- Políticas: Write-back + Write-allocate (L1_WT=0) o Write-through + No-write-allocate (L1_WT=1).
//- Mantiene coherencia con L2 por invalidación (snoop). Si L2 expulsa una línea, L1 la invalida.
//- Implementa Forwarding (BUFFER_FWD) para reenviar datos pendientes del write buffer.

module l1d_cache #(
  parameter bit L1_WT      = 1'b0, // 0: WB+WA, 1: WT+NWA
  parameter bit BUFFER_FWD = 1'b1  // 1: Forwarding desde write buffer, 0: esperar drenado
) (
  input  logic         clk,
  input  logic         rst,

  //Interfaz con la CPU (etapa EX)
  input  logic         rd,
  input  logic         wr,
  input  logic [15:0]  addr,
  input  logic [31:0]  wdata,
  output logic [31:0]  rdata,
  output logic         stall,

  //Interfaz con el Write Buffer
  output logic         wb_push,
  output logic [10:0]  wb_push_la,
  output logic [255:0] wb_push_data,
  output logic [7:0]   wb_push_mask,
  input  logic         wb_push_ready,
  output logic [10:0]  wb_q_la,
  input  logic         wb_q_hit,
  input  logic [255:0] wb_q_data,
  input  logic [7:0]   wb_q_mask,

  //Interfaz de Fill con L2
  output logic         fill_req,
  output logic [10:0]  fill_la,
  input  logic         fill_done,
  input  logic [255:0] fill_line,

  // Interfaz de invalidación(Backward invalidation desde L2)
  input  logic         snoop_req,
  input  logic [10:0]  snoop_la,
  output logic         snoop_hit,
  output logic         snoop_dirty,
  output logic [255:0] snoop_line,

  //Contadores de rendimiento
  output logic [31:0]  c_rd_acc, c_wr_acc, c_rd_hit, c_rd_miss, c_wr_hit, c_wr_miss,
  output logic [31:0]  c_back_inv, c_wb_full_stall, c_fwd_fill, c_dirty_evict, c_drain_wait
);
  //Estados de la máquina de control de misses
  localparam logic [1:0] S_IDLE = 2'd0, S_DRAIN = 2'd1, S_FILL = 2'd2;

  //Arreglos de almacenamiento (2 vias x 64 conjuntos)
  logic [255:0] dat [0:1][0:63]; //Linea de 32 bytes-256 bits
  logic [4:0]   tag [0:1][0:63]; //5 bits de tag por linea
  logic [63:0]  val [0:1];       //Bit de válido por conjunto
  logic [63:0]  dty [0:1];       //Bit de dirty(Solo para WB)
  logic [63:0]  lru;             //Bits de LRU por conjunto

  logic [1:0]  state;
  logic [10:0] miss_la;  //Line Address de la linea que causo el miss
  logic        miss_way; //Via que se va a reemplazar
  logic        counted;  //Bandera para no contar el mismo acceso dos veces

  // Decodificacion de dirección
  logic [10:0] la;
  logic [5:0]  idx;
  logic [4:0]  tg;
  logic [2:0]  ws;
  assign la  = addr[15:5];
  assign idx = addr[10:5];
  assign tg  = addr[15:11];
  assign ws  = addr[4:2];

  //Lógica de Hit
  logic hit0, hit1, hit, hway, access;
  assign hit0   = val[0][idx] && tag[0][idx] == tg;
  assign hit1   = val[1][idx] && tag[1][idx] == tg;
  assign hit    = hit0 || hit1;
  assign hway   = hit1; //Si hay hit en la via 1, hway es 1
  assign access = rd || wr;

  logic [255:0] hline;
  assign hline = dat[hway][idx];
  assign rdata = hline[32*ws +: 32]; //Extrae la palabra según el offset

  // Selección de victima 
  // Prioriza vías inválidas: si ambas son válidas, usa el bit LRU
  logic vway;
  assign vway = !val[0][idx] ? 1'b0 : (!val[1][idx] ? 1'b1 : lru[idx]);
  
  //Una victima es dirty solo si estamos en Write-Back y la línea fue modificada
  logic vdirty;
  assign vdirty = !L1_WT && val[vway][idx] && dty[vway][idx];

  //Funciones auxiliares para actualizar palabras de la línea
  function automatic logic [255:0] put_word(input logic [255:0] l, input logic [2:0] w, input logic [31:0] v);
    logic [255:0] r;
    r = l;
    r[32*w +: 32] = v;
    return r;
  endfunction

  // Mezcla los datos de una línea vieja con los datos pendientes del write buffer(forwarding)
  function automatic logic [255:0] merge(input logic [255:0] old, input logic [255:0] nw, input logic [7:0] m);
    logic [255:0] r;
    r = old;
    for (int w = 0; w < 8; w++) if (m[w]) r[32*w +: 32] = nw[32*w +: 32];
    return r;
  endfunction

  //Condiciones de control del ciclo actual
  logic eval;            // Hay un acceso válido en este ciclo
  logic wt_store;        // Es un store en modo Write-through
  logic need_fill;       // Es un miss que requiere traer la linea L2
  assign eval      = state == S_IDLE && access && !snoop_req;
  assign wt_store  = L1_WT && wr;
  assign need_fill = eval && !hit && !wt_store;

  // Lógica combinacional de respuesta y stalls
  always @* begin
    stall        = 1'b0;
    wb_push      = 1'b0;
    wb_push_la   = la;
    wb_push_data = {8{wdata}}; //Replicamos el dato para facilitar el manejo de máscaras
    wb_push_mask = 8'b1 << ws; //Mascara de 1 byte activo(el que se escribe)

    if (state != S_IDLE) stall = 1'b1; //Si se esta llenando o drenando, el pipeline se detiene
    else if (access) begin
      if (snoop_req) stall = 1'b1; //Prioridad al snoop de invalidacion
      else if (wt_store) begin
        wb_push = wb_push_ready;
        stall   = !wb_push_ready; //Stall si el buffer está lleno
      end else if (!hit) begin
        stall = 1'b1; //Miss (siempre stalls)
        //Si la victima esta dirty, se intenta empujar al buffer antes de pedir el fill

        if (vdirty) begin
          wb_push      = wb_push_ready;
          wb_push_la   = {tag[vway][idx], idx};
          wb_push_data = dat[vway][idx];
          wb_push_mask = 8'hFF; //Máscara completa(se escribe toda la linea)
        end
      end
    end
  end

  //La dirección de consulta del buffer se mantiene congelada durante el miss
  assign wb_q_la  = la;            
  assign fill_req = state == S_FILL;
  assign fill_la  = miss_la;

  //Lógica de Snoop (invalidacion hacias atrás desde L2)
  logic [5:0] sidx;
  logic [4:0] stg;
  logic s0, s1;
  assign sidx       = snoop_la[5:0];
  assign stg        = snoop_la[10:6];
  assign s0         = val[0][sidx] && tag[0][sidx] == stg;
  assign s1         = val[1][sidx] && tag[1][sidx] == stg;
  assign snoop_hit  = s0 || s1;
  assign snoop_dirty = (s0 && dty[0][sidx]) || (s1 && dty[1][sidx]);
  assign snoop_line = s1 ? dat[1][sidx] : dat[0][sidx];

  // Si el forwardinf está activo y hay un hit en el write buffer, mezclamos los datos al vuelo.
  logic [255:0] fline;
  assign fline = (BUFFER_FWD && wb_q_hit) ? merge(fill_line, wb_q_data, wb_q_mask) : fill_line;

  //Inicializacion
  integer s;
  initial begin
    for (s = 0; s < 64; s = s + 1) begin
      dat[0][s] = '0; dat[1][s] = '0; tag[0][s] = '0; tag[1][s] = '0;
    end
  end

  //Máquina de estados síncrona y actualización de contadores
  always @(posedge clk) begin
    if (rst) begin
      val[0] <= '0; val[1] <= '0; dty[0] <= '0; dty[1] <= '0; lru <= '0;
      state <= S_IDLE; miss_la <= '0; miss_way <= 1'b0; counted <= 1'b0;
      c_rd_acc <= '0; c_wr_acc <= '0; c_rd_hit <= '0; c_rd_miss <= '0; c_wr_hit <= '0; c_wr_miss <= '0;
      c_back_inv <= '0; c_wb_full_stall <= '0; c_fwd_fill <= '0; c_dirty_evict <= '0; c_drain_wait <= '0;
    end else begin
      case (state)
        S_IDLE: if (eval) begin
          //Contamos accesos y hits/misses solo en el primer ciclo de la instrucción
          if (!counted) begin
            if (rd) begin c_rd_acc <= c_rd_acc + 1; if (hit) c_rd_hit <= c_rd_hit + 1; else c_rd_miss <= c_rd_miss + 1; end
            if (wr) begin c_wr_acc <= c_wr_acc + 1; if (hit) c_wr_hit <= c_wr_hit + 1; else c_wr_miss <= c_wr_miss + 1; end
          end
          counted <= stall;
          if (wt_store) begin
            // Write-Through: si hay hit, actualizamos L1 y mandamos al buffer
            if (wb_push_ready) begin
              if (hit) begin dat[hway][idx] <= put_word(hline, ws, wdata); lru[idx] <= !hway; end
            end else c_wb_full_stall <= c_wb_full_stall + 1;
          end else if (hit) begin
            //Hit normal (Read o Write-Back)
            lru[idx] <= !hway;
            if (wr) begin
              dat[hway][idx] <= put_word(hline, ws, wdata);
              dty[hway][idx] <= 1'b1; // Marcamos la línea como dirty
            end
          end else begin
            //// Miss- se prepara el reemplazo
            if (vdirty && !wb_push_ready) c_wb_full_stall <= c_wb_full_stall + 1;
            else begin
              if (vdirty) c_dirty_evict <= c_dirty_evict + 1;
              val[vway][idx] <= 1'b0;
              dty[vway][idx] <= 1'b0;
              miss_la  <= la;
              miss_way <= vway;
              //Si no hay forwarding y el buffer tiene datos, drenamos primero
              state    <= (!BUFFER_FWD && wb_q_hit) ? S_DRAIN : S_FILL;
            end
          end
        end
        S_DRAIN: begin
          // Se espera que el write buffer drene la línea pendiente
          c_drain_wait <= c_drain_wait + 1;
          if (!wb_q_hit) state <= S_FILL;
        end
        S_FILL: if (fill_done) begin
          dat[miss_way][miss_la[5:0]] <= fline;
          tag[miss_way][miss_la[5:0]] <= miss_la[10:6];
          val[miss_way][miss_la[5:0]] <= 1'b1;
          dty[miss_way][miss_la[5:0]] <= 1'b0;
          lru[miss_la[5:0]]           <= !miss_way;
          if (BUFFER_FWD && wb_q_hit) c_fwd_fill <= c_fwd_fill + 1;
          state <= S_IDLE;
        end
        default: state <= S_IDLE;
      endcase
      //Procesamiento del snoop (independiente del estado de la FSM)
      if (snoop_req && snoop_hit) begin
        c_back_inv <= c_back_inv + 1;
        if (s0) begin val[0][sidx] <= 1'b0; dty[0][sidx] <= 1'b0; end
        if (s1) begin val[1][sidx] <= 1'b0; dty[1][sidx] <= 1'b0; end
      end
    end
  end
endmodule
