// Buffer de escritura (FIFO) entre la caché L1-D y la caché L2.
// Cada entrada representa una línea de 32 B con una máscara que indica qué palabras fueron modificadas.
// Funcionamiento:
// - En L1 Write-Through: cada AP (store) encola solo la palabra modificada (máscara de 1 bit).
//     Si se hacen varias escrituras a la misma línea, se combinan en la misma entrada pendiente (write merging).
// - En L1 Write-Back: cuando se desaloja una línea sucia, se encola la línea completa (máscara 0xFF).
// El buffer drena hacia L2 en segundo plano. La entrada que está siendo drenada (`head_busy`) no 
// acepta combinaciones para evitar corromper el dato en vuelo.

// Forwarding: Para resolver el riesgo RAW (Read After Write) en memoria, la interfaz q_hit/q_data/q_mask 
// busca la dirección de lectura (q_la) en todas las entradas pendientes. Si hay coincidencia, 
// reconstruye el dato más reciente combinando las máscaras desde la entrada más vieja a la más nueva.

module write_buffer #(parameter int DEPTH = 4) (
  input  logic         clk,
  input  logic         rst,

  //Interfaz de entrada (desde L1)
  input  logic         push,
  input  logic [10:0]  push_la,
  input  logic [255:0] push_data,
  input  logic [7:0]   push_mask,
  output logic         push_ready,   //Indica si hay espacio o si se puede combinar

  //Interfaz de drenado (hacia L2)
  output logic         head_valid,
  output logic [10:0]  head_la,
  output logic [255:0] head_data,
  output logic [7:0]   head_mask,  
  input  logic         head_busy,  //L2 está ocupado drenando esta entrada
  input  logic         pop,       //L2 confirma que terminó de drenar

  //Interfaz de forwarding (búsqueda para loads)
  input  logic [10:0]  q_la,
  output logic         q_hit,
  output logic [255:0] q_data,
  output logic [7:0]   q_mask,

  //Contadores y estado
  output logic [$clog2(DEPTH+1)-1:0] count,
  output logic [31:0]  cnt_pushes,
  output logic [31:0]  cnt_merges
);
  //Cálculo de anchos de bits para los punteros circulares
  localparam int PW = (DEPTH > 1) ? $clog2(DEPTH) : 1;
  localparam int CW = $clog2(DEPTH+1);

  //Almacenamiento de la FIFO
  logic [10:0]  la_q   [0:DEPTH-1];
  logic [255:0] data_q [0:DEPTH-1];
  logic [7:0]   mask_q [0:DEPTH-1];
  logic [PW-1:0] head, tail;

  //Incremento circular del puntero
  function automatic logic [PW-1:0] inc(input logic [PW-1:0] p);
    return (p == PW'(DEPTH - 1)) ? '0 : p + 1'b1;
  endfunction

  //Función para combinar los datos nuevos con los viejos según la máscara
  function automatic logic [255:0] merge(input logic [255:0] old, input logic [255:0] nw, input logic [7:0] m);
    logic [255:0] r;
    r = old;
    for (int w = 0; w < 8; w++) if (m[w]) r[32*w +: 32] = nw[32*w +: 32];
    return r;
  endfunction

  //Banderas de estado de la FIFO
  logic full, empty;
  assign full       = (count == DEPTH[$clog2(DEPTH+1)-1:0]);
  assign empty      = (count == '0);
  //Señales de la cabeza (para drenado)
  assign head_valid = !empty;
  assign head_la    = la_q[head];
  assign head_data  = data_q[head];
  assign head_mask  = mask_q[head];

  //Lógica Combinacional: Combinación de escrituras y Forwarding
  integer i;
  logic [PW-1:0] p, mpos;
  logic mfound;
  always @* begin
    mfound = 1'b0; mpos = '0;
    q_hit = 1'b0; q_data = '0; q_mask = '0;
    p = head;
    //Se recorren todas las entradas válidas
    for (i = 0; i < DEPTH; i = i + 1) begin
      if (i < count) begin
        //1.Se busca si la escritura entrante (push) se puede combinar(No se combina si la entrada ya está en vuelo hacia L2)
        if (la_q[p] == push_la && !(head_busy && p == head)) begin 
          mfound = 1'b1; 
          mpos = p;
        end
        //2.Forwarding: Si un load busca esta dirección, combinamos todas las máscaras
        //para reconstruir el estado más actualizado de la línea.
        if (la_q[p] == q_la) begin
          q_hit  = 1'b1;
          q_data = merge(q_data, data_q[p], mask_q[p]);
          q_mask = q_mask | mask_q[p];
        end
      end
      p = inc(p);
    end
  end

  //La L1 puede meter datos si hay espacio libre o si se puede combinar
  assign push_ready = mfound || !full;

  //Lógica Síncrona: Control de Punteros y Contadores
  logic do_push, do_merge, do_pop;
  assign do_merge = push && mfound;
  assign do_push  = push && !mfound && !full;
  assign do_pop   = pop && !empty;

  always @(posedge clk) begin
    if (rst) begin
      head <= '0; tail <= '0; count <= '0; cnt_pushes <= '0; cnt_merges <= '0;
    end else begin
      //Escritura combinada en una entrada existente
      if (do_merge) begin
        data_q[mpos] <= merge(data_q[mpos], push_data, push_mask);
        mask_q[mpos] <= mask_q[mpos] | push_mask;
        cnt_merges   <= cnt_merges + 1;
      end
      //Nueva entrada en la cola
      if (do_push) begin
        la_q[tail]   <= push_la;
        data_q[tail] <= push_data;
        mask_q[tail] <= push_mask;
        tail         <= inc(tail);
        cnt_pushes   <= cnt_pushes + 1;
      end
      //Avance de la cabeza cuando L2 termina de drenar
      if (do_pop) head <= inc(head);
      //Actualización del contador de ocupación
      count <= count + CW'(do_push) - CW'(do_pop);
    end
  end
endmodule
