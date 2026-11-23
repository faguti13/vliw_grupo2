// Testbench para el Write Buffer (L1-L2) y el Eviction Buffer (L2-DRAM).
// Pruebas del Write Buffer:
//   * Combinación (merge) de escrituras a la misma línea.
//   * Llenado de la FIFO (si está lleno, push_ready = 0 para forzar el stall de L1).
//   * La cabeza en vuelo no acepta combinaciones.
//   * Forwarding: reconstruye la palabra más nueva buscando en todas las entradas.
//   * Orden FIFO estricto al drenar.
// Pruebas del Eviction Buffer:
//   * Llenado y bandera de "full"
//   * Forwarding de la copia más nueva si hay varias escrituras a la misma línea.
//   * Orden FIFO al drenar hacia memoria


module tb_buffers;
  logic clk = 0, rst = 1;
  always #5 clk = ~clk;
  integer errors = 0;

  task automatic check(input string what, input logic ok);
    if (!ok) begin errors = errors + 1; $display("  FAIL %s", what); end
  endtask

  //Instanciación y estímulos del Write Buffer (4 entradas) 
  logic         w_push, w_ready, w_hvalid, w_busy, w_pop, w_qhit;
  logic [10:0]  w_la, w_hla, w_qla;
  logic [255:0] w_data, w_hdata, w_qdata;
  logic [7:0]   w_mask, w_hmask, w_qmask;
  logic [2:0]   w_count;
  logic [31:0]  w_pushes, w_merges;
  write_buffer #(.DEPTH(4)) u_wb (.clk(clk), .rst(rst), .push(w_push), .push_la(w_la), .push_data(w_data),
      .push_mask(w_mask), .push_ready(w_ready), .head_valid(w_hvalid), .head_la(w_hla), .head_data(w_hdata),
      .head_mask(w_hmask), .head_busy(w_busy), .pop(w_pop), .q_la(w_qla), .q_hit(w_qhit), .q_data(w_qdata),
      .q_mask(w_qmask), .count(w_count), .cnt_pushes(w_pushes), .cnt_merges(w_merges));

  //Tarea para empujar una palabra a una dirección de línea específica
  task automatic wpush(input logic [10:0] la, input int word, input logic [31:0] v);
    @(negedge clk);
    w_push = 1; w_la = la; w_data = {8{v}}; w_mask = 8'b1 << word;
    @(negedge clk);
    w_push = 0;
  endtask

  //Instanciación y estímulos del Eviction Buffer (3 entradas para forzar lleno) 
  logic         e_push, e_full, e_empty, e_hvalid, e_pop, e_qhit;
  logic [10:0]  e_la, e_hla, e_qla;
  logic [255:0] e_line, e_hline, e_qline;
  logic [1:0]   e_count;
  logic [31:0]  e_pushes, e_maxocc;

  eviction_buffer #(.DEPTH(3)) u_eb (.clk(clk), .rst(rst), .push(e_push), .push_la(e_la), .push_line(e_line),
      .full(e_full), .empty(e_empty), .head_valid(e_hvalid), .head_la(e_hla), .head_line(e_hline), .pop(e_pop),
      .q_la(e_qla), .q_hit(e_qhit), .q_line(e_qline), .count(e_count), .cnt_pushes(e_pushes),
      .cnt_max_occupancy(e_maxocc));

  task automatic epush(input logic [10:0] la, input logic [31:0] v);
    @(negedge clk);
    e_push = 1; e_la = la; e_line = {8{v}};
    @(negedge clk);
    e_push = 0;
  endtask

  initial begin
    //Inicialización de señales
    w_push = 0; w_busy = 0; w_pop = 0; w_qla = 0; w_la = 0; w_data = 0; w_mask = 0;
    e_push = 0; e_pop = 0; e_qla = 0; e_la = 0; e_line = 0;
    repeat (3) @(posedge clk);
    #1 rst = 0;

    //Pruebas del Write Buffer

    //Se escriben dos veces en la línea 10 (palabras 0 y 3). Debería combinarse en una sola entrada
    wpush(11'd10, 0, 32'h11111111);
    wpush(11'd10, 3, 32'h33333333);              // misma linea: se combina
    check("combinacion de escrituras a la misma linea", w_count == 1 && w_merges == 1 && w_hmask == 8'b0000_1001);
    
    //Se llena el resto del buffer (3 entradas más, total 4)
    wpush(11'd20, 1, 32'hAAAAAAAA);
    wpush(11'd30, 2, 32'hBBBBBBBB);
    wpush(11'd40, 7, 32'hCCCCCCCC);
    check("4 entradas: lleno", w_count == 4);
    
    //Se intenta meter una línea nueva estando lleno - debe dar stall.
    @(negedge clk); w_la = 11'd50; w_mask = 8'h01; #1;
    check("lleno y linea nueva -> push_ready = 0 (stall)", !w_ready);
    
    //Se intenta meter una línea que ya está -- debe permitirlo (merge)
    w_la = 11'd20; #1;
    check("lleno pero linea pendiente -> se puede combinar", w_ready);
    
    
    //Forwarding.Se pide la línea 10, debe devolver el dato combinado de las palabras 0 y 3
    w_qla = 11'd10; #1;
    check("forwarding: hit", w_qhit && w_qmask == 8'b0000_1001);
    check("forwarding: datos", w_qdata[31:0] == 32'h11111111 && w_qdata[127:96] == 32'h33333333);
    
    //Drenado. se saca la primera entrada (línea 10).
    @(negedge clk); w_busy = 1; w_pop = 0;
    @(negedge clk); w_pop = 1;               //L2 termino de drenar la cabeza
    @(negedge clk); w_pop = 0; w_busy = 0;
    check("drenado FIFO: sale la linea 10 primero", w_hla == 11'd20 && w_count == 3);
    
    //Se prueba que la cabeza en vuelo no se combine
    w_busy = 1;                               //la cabeza actual (linea 20) esta en vuelo
    wpush(11'd20, 5, 32'h55555555);
    check("la cabeza en vuelo no se combina", w_count == 4 && w_merges == 1);
    
    //Forwarding especial. mezcla la cabeza en vuelo con la entrada nueva (la nueva gana).
    w_qla = 11'd20; #1;
    check("forwarding combina cabeza en vuelo + entrada nueva (mas nueva gana)",
          w_qhit && w_qmask == 8'b0010_0010 && w_qdata[63:32] == 32'hAAAAAAAA && w_qdata[191:160] == 32'h55555555);
    //Forwarding miss(se busca una linea que no esta)
    w_qla = 11'd99; #1;
    check("forwarding: miss", !w_qhit);
    w_busy = 0;

    //Pruebas del Eviction Buffer

    //Se llena el buffer de 3 entradas
    //La línea 7 se escribe dos veces (la segunda debe ganar en forwarding)
    epush(11'd7, 32'h70000000);
    epush(11'd8, 32'h80000000);
    epush(11'd7, 32'h71111111);               // segunda copia de la linea 7 (mas nueva)
    check("eviction buffer lleno", e_full && e_count == 3);
    
    // Forwarding.la línea 7 es pedida, debe devolver la copia más nueva (0x71111111)
    e_qla = 11'd7; #1;
    check("forwarding de la copia mas nueva", e_qhit && e_qline == {8{32'h71111111}});
    
    //Se verifica el orden FIFO: la cabeza es la línea 7 vieja (0x70000000)
    check("orden de drenado: cabeza = linea 7 vieja", e_hla == 11'd7 && e_hline == {8{32'h70000000}});
    
    //Se drena la primera entrada.
    @(negedge clk); e_pop = 1; @(negedge clk); e_pop = 0;
    check("drenado: sigue la linea 8", e_hla == 11'd8 && !e_full);
    
    //Forwarding de la línea 8
    e_qla = 11'd8; #1;
    check("forwarding linea 8", e_qhit && e_qline == {8{32'h80000000}});
    
    //Se drena el resto y se verifica que quede vacío
    @(negedge clk); e_pop = 1; @(negedge clk); @(negedge clk); e_pop = 0;
    check("vacio tras drenar todo", e_empty && e_pushes == 3 && e_maxocc == 3);

    //Resultado final
    if (errors == 0) $display("tb_buffers: PASS");
    else             $display("tb_buffers: FAIL (%0d errores)", errors);
    $finish;
  end
endmodule
