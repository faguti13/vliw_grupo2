//Testbench para la caché L1-D y el write buffer.

// Se encarga de conectar la L1-D y el write buffer a un modelo de L2 simplificado.
// El modelo de L2 responde a los fills después de `FILL_LAT` ciclos y drena el 
// write buffer solo cuando `drain_en = 1`. Esto permite probar el forwarding 
// de datos pendientes durante un fill.

// El testbench se parametriza para correr en tres variantes:
//   1. L1_WT=0, BUFFER_FWD=1 (Write-Back + Write-Allocate, con forwarding)
//   2. L1_WT=1, BUFFER_FWD=1 (Write-Through + No-Write-Allocate)
//   3. L1_WT=0, BUFFER_FWD=0 (Write-Back sin forwarding, para probar stalls de drenado)

module tb_l1d #(parameter bit L1_WT = 1'b0, parameter bit BUFFER_FWD = 1'b1);
  logic clk = 0, rst = 1;
  always #5 clk = ~clk;
  localparam int FILL_LAT = 5; // Latencia simulada de L2

  //Señales de la interfaz CPU -- L1-D
  logic         rd, wr, stall;
  logic [15:0]  addr;
  logic [31:0]  wdata, rdata;

  //Interfaz con el Write Buffer
  logic         wb_push, wb_ready, wb_qhit, fill_req, fill_done, snoop_req, snoop_hit, snoop_dirty;
  logic [10:0]  wb_la, wb_qla, fill_la, snoop_la;
  logic [255:0] wb_data, wb_qdata, fill_line, snoop_line;
  logic [7:0]   wb_mask, wb_qmask;

  //Contadores de rendimiento
  logic [31:0]  c_rd_acc, c_wr_acc, c_rd_hit, c_rd_miss, c_wr_hit, c_wr_miss;
  logic [31:0]  c_back_inv, c_wb_full, c_fwd_fill, c_dirty_evict, c_drain_wait;

  //Instancia del DUT (Device Under Test)
  l1d_cache #(.L1_WT(L1_WT), .BUFFER_FWD(BUFFER_FWD)) dut (.clk(clk), .rst(rst), .rd(rd), .wr(wr), .addr(addr),
      .wdata(wdata), .rdata(rdata), .stall(stall), .wb_push(wb_push), .wb_push_la(wb_la), .wb_push_data(wb_data),
      .wb_push_mask(wb_mask), .wb_push_ready(wb_ready), .wb_q_la(wb_qla), .wb_q_hit(wb_qhit), .wb_q_data(wb_qdata),
      .wb_q_mask(wb_qmask), .fill_req(fill_req), .fill_la(fill_la), .fill_done(fill_done), .fill_line(fill_line),
      .snoop_req(snoop_req), .snoop_la(snoop_la), .snoop_hit(snoop_hit), .snoop_dirty(snoop_dirty),
      .snoop_line(snoop_line), .c_rd_acc(c_rd_acc), .c_wr_acc(c_wr_acc), .c_rd_hit(c_rd_hit), .c_rd_miss(c_rd_miss),
      .c_wr_hit(c_wr_hit), .c_wr_miss(c_wr_miss), .c_back_inv(c_back_inv), .c_wb_full_stall(c_wb_full),
      .c_fwd_fill(c_fwd_fill), .c_dirty_evict(c_dirty_evict), .c_drain_wait(c_drain_wait));

  //Instancia del write buffer
  logic         h_valid, h_busy, h_pop;
  logic [10:0]  h_la;
  logic [255:0] h_data;
  logic [7:0]   h_mask;
  logic [2:0]   wb_count;
  logic [31:0]  wb_pushes, wb_merges;
  write_buffer #(.DEPTH(4)) u_wb (.clk(clk), .rst(rst), .push(wb_push), .push_la(wb_la), .push_data(wb_data),
      .push_mask(wb_mask), .push_ready(wb_ready), .head_valid(h_valid), .head_la(h_la), .head_data(h_data),
      .head_mask(h_mask), .head_busy(h_busy), .pop(h_pop), .q_la(wb_qla), .q_hit(wb_qhit), .q_data(wb_qdata),
      .q_mask(wb_qmask), .count(wb_count), .cnt_pushes(wb_pushes), .cnt_merges(wb_merges));

  //Modelo de L2 (Memoria principal simplificada)
  
  logic [255:0] l2m [0:2047];

  //Función para generar datos predecibles basados en la dirección
  function automatic logic [31:0] pat(input logic [10:0] la, input int w);
    return {5'h0, la, 8'h00, 8'(w)};
  endfunction
  integer i, w, fcnt = 0, dcnt = 0;
  logic drain_en = 0;

  //Inicialización de L2 con el patrón
  initial for (i = 0; i < 2048; i = i + 1) for (w = 0; w < 8; w = w + 1) l2m[i][32*w +: 32] = pat(11'(i), w);

  // Simulación del fill(tarda FILL_LAT ciclos en responder)
  always @(posedge clk) begin
    if (rst) begin fill_done <= 0; fcnt <= 0; end
    else if (fill_done) begin fill_done <= 0; fcnt <= 0; end
    else if (fill_req) begin
      fcnt <= fcnt + 1;
      if (fcnt + 1 == FILL_LAT) begin fill_done <= 1; fill_line <= l2m[fill_la]; end
    end
  end
  //Simulación del drenado del write buffer hacia L2
  assign h_busy = drain_en && h_valid;
  assign h_pop  = h_busy && dcnt == 2;
  always @(posedge clk) begin
    if (rst || !h_busy) dcnt <= 0;
    else if (h_pop) begin
      dcnt <= 0;
      for (int k = 0; k < 8; k++) if (h_mask[k]) l2m[h_la][32*k +: 32] <= h_data[32*k +: 32];
    end else dcnt <= dcnt + 1;
  end
  //Si L2 expulsa una línea sucia, se actualiza L2
  always @(posedge clk) if (snoop_req && snoop_dirty) l2m[snoop_la] <= snoop_line;

  //Lógica de pruebas (CPU estimulando la caché)

  integer errors = 0, cyc;
  logic [31:0] got;
  string cfg;

  //Funciones para armar direcciones a partir de tag, index y word
  function automatic logic [15:0] A(input int tg, input int idx, input int w);
    return 16'((tg << 11) | (idx << 5) | (w << 2));
  endfunction
  function automatic logic [10:0] LA(input int tg, input int idx);
    return 11'((tg << 6) | idx);
  endfunction

  integer nchecks = 0;
  task automatic check(input string what, input logic ok);
    nchecks = nchecks + 1;
    if (!ok) begin errors = errors + 1; $display("  FAIL %s", what); end
  endtask

  //Tarea de acceso a memoria (simula lo que haría la etapa EX)
  task automatic acc(input logic w, input logic [15:0] a, input logic [31:0] d, output logic [31:0] r, output integer c);
    @(negedge clk);
    rd = !w; wr = w; addr = a; wdata = d;
    #1 c = 0;
    while (stall) begin @(negedge clk); #1 c = c + 1; end
    r = rdata;
    @(posedge clk); #1 rd = 0; wr = 0;
  endtask

   //Tarea para habilitar el drenado del write buffer
  task automatic wait_drain;
    drain_en = 1;
    while (wb_count != 0) @(posedge clk);
    @(posedge clk); #1 drain_en = 0;
  endtask

  initial begin
    rd = 0; wr = 0; addr = 0; wdata = 0; snoop_req = 0; snoop_la = 0;
    repeat (3) @(posedge clk);
    #1 rst = 0;

    //1.Miss de lectura y luego hit
    acc(0, A(1, 3, 2), 0, got, cyc);
    check($sformatf("miss de lectura con stall (%0d ciclos)", cyc), cyc > FILL_LAT && got == pat(LA(1, 3), 2));
    acc(0, A(1, 3, 5), 0, got, cyc);
    check("hit de lectura sin stall", cyc == 0 && got == pat(LA(1, 3), 5));

    //2.Prueba del reemplazo LRU en el conjunto 3
    //Se llenan las 2 vías con A=1 y B=2
    acc(0, A(2, 3, 0), 0, got, cyc);
    check("miss B", cyc > 0);
    acc(0, A(1, 3, 0), 0, got, cyc);
    check("A sigue (hit)", cyc == 0);
    //Entra C=3. Debería reemplazar a B (la menos usada)
    acc(0, A(3, 3, 0), 0, got, cyc);
    check("miss C", cyc > 0 && got == pat(LA(3, 3), 0));
    acc(0, A(1, 3, 1), 0, got, cyc);
    check("LRU: A sobrevive a C", cyc == 0);
    acc(0, A(2, 3, 1), 0, got, cyc);
    check("LRU: B fue la victima", cyc > 0);
    check($sformatf("contadores de lectura acc=%0d hit=%0d miss=%0d", c_rd_acc, c_rd_hit, c_rd_miss),
          c_rd_acc == 7 && c_rd_hit == 3 && c_rd_miss == 4);


    // 3.Escrituras y comportamiento según la política
    acc(1, A(1, 3, 1), 32'hDEADBEEF, got, cyc);
    check("AP con hit sin stall", cyc == 0);
    acc(0, A(1, 3, 1), 0, got, cyc);
    check("lectura del dato escrito", cyc == 0 && got == 32'hDEADBEEF);
    
    if (!L1_WT) begin
      //Pruebas para Write-Back
      check("WB: el hit no escribe hacia abajo", wb_count == 0);
     
      //Se provoca que A (sucia) sea la víctima
      acc(0, A(2, 3, 2), 0, got, cyc);          // B pasa a MRU, A queda LRU
      acc(0, A(3, 3, 0), 0, got, cyc);
      check("WB: victima sucia al write buffer", c_dirty_evict == 1 && wb_count == 1 && h_la == LA(1, 3) && h_mask == 8'hFF);
      check("WB: L2 aun tiene el dato viejo", l2m[LA(1, 3)][63:32] == pat(LA(1, 3), 1));
      //Se forza el retorno de A para ver si el dato pendiente se rescata
      fork
        acc(0, A(1, 3, 1), 0, got, cyc);
        begin repeat (30) @(posedge clk); drain_en = 1; end
      join
      check("WB: el fill ve la escritura pendiente", got == 32'hDEADBEEF);
      if (BUFFER_FWD) check($sformatf("WB: forwarding en el fill (fwd=%0d, %0d ciclos)", c_fwd_fill, cyc),
                            c_fwd_fill == 1 && cyc < 30);
      else            check($sformatf("NOFWD: el fill espera el drenado (%0d ciclos de espera)", c_drain_wait),
                            c_drain_wait > 0 && c_fwd_fill == 0 && cyc >= 30);
      wait_drain();
      check("WB: drenado a L2", l2m[LA(1, 3)][63:32] == 32'hDEADBEEF);
      
      //Write-allocate
      acc(1, A(5, 9, 6), 32'h600DF00D, got, cyc);
      check("WA: AP con miss trae la linea", cyc > 0 && c_wr_miss == 1);
      acc(0, A(5, 9, 6), 0, got, cyc);
      check("WA: hit tras el AP", cyc == 0 && got == 32'h600DF00D);
      acc(0, A(5, 9, 7), 0, got, cyc);
      check("WA: resto de la linea desde L2", cyc == 0 && got == pat(LA(5, 9), 7));
    end else begin
      // Pruebas para Write-Through
      check("WT: el hit escribe la palabra en el write buffer", wb_count == 1 && h_mask == 8'b0000_0010);
      
      // no-write-allocate
      acc(1, A(5, 9, 6), 32'h600DF00D, got, cyc);
      check("NWA: AP con miss sin stall", cyc == 0 && c_wr_miss == 1 && wb_count == 2);
      fork
        acc(0, A(5, 9, 6), 0, got, cyc);
        begin repeat (30) @(posedge clk); drain_en = 1; end
      join
      check("NWA: la lectura falla (no hubo allocate)", cyc > 0);
      check("NWA: el fill ve la escritura pendiente", got == 32'h600DF00D);
      wait_drain();
      check("WT: drenado a L2", l2m[LA(1, 3)][63:32] == 32'hDEADBEEF && l2m[LA(5, 9)][223:192] == 32'h600DF00D);
      
      //Llenar el write buffer (4 entradas) y forzar un stall
      for (i = 0; i < 4; i = i + 1) acc(1, A(7, 20 + i, 0), i, got, cyc);
      check("WT: 4 entradas pendientes", wb_count == 4);
      fork
        acc(1, A(7, 30, 0), 32'h5, got, cyc);
        begin repeat (10) @(posedge clk); drain_en = 1; end
      join
      check($sformatf("WT: write buffer lleno -> stall (%0d ciclos)", cyc), cyc >= 10 && c_wb_full > 0);
      wait_drain();

      //Combinación de dos AP a la misma línea
      acc(1, A(7, 40, 0), 32'h1, got, cyc);
      acc(1, A(7, 40, 3), 32'h2, got, cyc);
      check("WT: combinacion en el write buffer", wb_count == 1 && h_mask == 8'b0000_1001 && wb_merges >= 1);
      wait_drain();
    end

    // 4. Invalidación hacia atrás (Snoop desde L2)
    acc(1, A(1, 3, 4), 32'hCAFEBABE, got, cyc);
    @(negedge clk);
    snoop_req = 1; snoop_la = LA(1, 3);
    #1;
    check("snoop: hit", snoop_hit);
    check("snoop: sucio solo en WB", snoop_dirty == !L1_WT);
    check("snoop: datos de la linea", snoop_line[159:128] == 32'hCAFEBABE && snoop_line[63:32] == 32'hDEADBEEF);
    @(negedge clk);
    snoop_req = 0;
    #1;
    check("snoop: linea invalidada", !snoop_hit && c_back_inv == 1);
    if (L1_WT) wait_drain();
    acc(0, A(1, 3, 4), 0, got, cyc);
    check("snoop: la siguiente lectura falla y ve el dato (sin perderlo)", cyc > 0 && got == 32'hCAFEBABE);
    snoop_la = LA(9, 9);
    snoop_req = 1; #1;
    check("snoop a una linea ausente", !snoop_hit);
    @(negedge clk); snoop_req = 0;

    //Resultados finales
    if (L1_WT)            cfg = "WT+NWA";
    else if (BUFFER_FWD)  cfg = "WB+WA";
    else                  cfg = "WB+WA sin forwarding";
    if (errors == 0) $display("tb_l1d (%s, %0d chequeos): PASS", cfg, nchecks);
    else             $display("tb_l1d (%s): FAIL (%0d errores)", cfg, errors);
    $finish;
  end
endmodule
