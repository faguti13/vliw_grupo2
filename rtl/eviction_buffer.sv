// eviction_buffer.sv - Buffer de desalojo L2 -> DRAM (FIFO de lineas sucias de 32 B).
// L2 empuja la victima sucia en 1 ciclo y sigue con el fill; el buffer drena a la DRAM en
// segundo plano cuando la DRAM esta libre. La consulta por direccion de linea (q_la) permite
// el dirty-line forwarding: si un miss de L2 pide una linea que sigue aqui, se toma la copia
// mas reciente sin ir a la DRAM (o, con BUFFER_FWD = 0, L2 espera a que se drene).
module eviction_buffer #(parameter int DEPTH = 8) (
  input  logic         clk,
  input  logic         rst,
  // entrada desde L2
  input  logic         push,
  input  logic [10:0]  push_la,
  input  logic [255:0] push_line,
  output logic         full,
  output logic         empty,
  // drenado hacia la DRAM
  output logic         head_valid,
  output logic [10:0]  head_la,
  output logic [255:0] head_line,
  input  logic         pop,
  // consulta para forwarding
  input  logic [10:0]  q_la,
  output logic         q_hit,
  output logic [255:0] q_line,
  output logic [$clog2(DEPTH+1)-1:0] count,
  output logic [31:0]  cnt_pushes,
  output logic [31:0]  cnt_max_occupancy
);
  localparam int PW = (DEPTH > 1) ? $clog2(DEPTH) : 1;
  localparam int CW = $clog2(DEPTH+1);
  logic [10:0]  la_q   [0:DEPTH-1];
  logic [255:0] line_q [0:DEPTH-1];
  logic [PW-1:0] head, tail;

  function automatic logic [PW-1:0] inc(input logic [PW-1:0] p);
    return (p == PW'(DEPTH - 1)) ? '0 : p + 1'b1;
  endfunction

  assign full       = (count == DEPTH[$clog2(DEPTH+1)-1:0]);
  assign empty      = (count == '0);
  assign head_valid = !empty;
  assign head_la    = la_q[head];
  assign head_line  = line_q[head];

  // La entrada mas nueva que coincide gana (se recorre de la mas vieja a la mas nueva)
  integer i;
  logic [PW-1:0] p;
  always @* begin
    q_hit = 1'b0; q_line = '0; p = head;
    for (i = 0; i < DEPTH; i = i + 1) begin
      if (i < count && la_q[p] == q_la) begin q_hit = 1'b1; q_line = line_q[p]; end
      p = inc(p);
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      head <= '0; tail <= '0; count <= '0; cnt_pushes <= '0; cnt_max_occupancy <= '0;
    end else begin
      if (push && !full) begin
        la_q[tail]   <= push_la;
        line_q[tail] <= push_line;
        tail         <= inc(tail);
        cnt_pushes   <= cnt_pushes + 1;
        if (!(pop && !empty) && 32'(count) == cnt_max_occupancy)
          cnt_max_occupancy <= 32'(count) + 1;
      end
      if (pop && !empty) head <= inc(head);
      count <= count + CW'(push && !full) - CW'(pop && !empty);
    end
  end
endmodule
