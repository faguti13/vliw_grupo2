// tb_dram_ctrl.sv - Controlador de DRAM con reloj propio (clk_div + dram_ctrl).
// Verifica: latencia exacta Tmem = 25 + 7 * DIV ciclos de CPU por linea (lectura y escritura),
// escritura con mascara de palabras, lectura de vuelta, contadores de la seccion 5.3 y que el
// handshake entre dominios nunca dispara el watchdog. Se compila con DIV = 2, 4 y 5 (make unit).
module tb_dram_ctrl #(parameter int DIV = 4);
  logic clk = 0, rst = 1;
  always #5 clk = ~clk;
  logic clk_mem;
  clk_div #(.DIV(DIV)) u_div (.clk(clk), .clk_out(clk_mem));

  logic         req, we, idle, done, err;
  logic [10:0]  la;
  logic [255:0] wdata, rdata;
  logic [7:0]   wmask;
  logic [31:0]  i_rdata, n_rd, n_wr, n_busy;
  dram_ctrl #(.DIV(DIV)) dut (.clk(clk), .rst(rst), .clk_mem(clk_mem), .req(req), .we(we), .la(la),
      .wdata(wdata), .wmask(wmask), .idle(idle), .done(done), .rdata(rdata),
      .i_addr(16'h0), .i_we(1'b0), .i_wdata(32'h0), .i_rdata(i_rdata),
      .cnt_reads(n_rd), .cnt_writes(n_wr), .cnt_busy(n_busy), .err_timeout(err));

  localparam int TMEM = 25 + 7 * DIV;
  integer errors = 0, lat, k;
  logic [255:0] got, pattern;

  // Emite una operacion y mide los ciclos desde el ciclo de la solicitud hasta `done`
  task automatic op(input logic w, input logic [10:0] a, input logic [255:0] d, input logic [7:0] m,
                    output logic [255:0] r, output integer cyc);
    @(negedge clk);
    while (!idle) @(negedge clk);
    req = 1; we = w; la = a; wdata = d; wmask = m;
    cyc = 0;
    @(negedge clk);
    req = 0;
    cyc = 1;
    while (!done && cyc < TMEM + 20) begin @(negedge clk); cyc = cyc + 1; end
    if (done !== 1'b1) $fatal(1, "DRAM sin respuesta (DIV=%0d)", DIV);
    r = rdata;
  endtask

  task automatic check(input string what, input logic ok);
    if (ok !== 1'b1) begin errors = errors + 1; $display("  FAIL %s", what); end
  endtask

  initial begin
    req = 0; we = 0; la = 0; wdata = 0; wmask = 0;
    repeat (4) @(posedge clk);
    #1 rst = 0;
    // memoria inicial conocida
    for (k = 0; k < 64; k = k + 1) dut.mem[32*5 + k] = k[7:0];

    op(1'b0, 11'd5, '0, 8'h00, got, lat);
    check("latencia de lectura", lat == TMEM);
    check("dato de la lectura", got[31:0] == 32'h00010203 && got[255:224] == 32'h1c1d1e1f);

    for (k = 0; k < 8; k = k + 1) pattern[32*k +: 32] = 32'hA0000000 + k;
    op(1'b1, 11'd9, pattern, 8'b1010_0101, got, lat);
    check("latencia de escritura", lat == TMEM);
    op(1'b0, 11'd9, '0, 8'h00, got, lat);
    check("palabras escritas con mascara", got[31:0] == 32'hA0000000 && got[95:64] == 32'hA0000002 &&
                                             got[191:160] == 32'hA0000005 && got[255:224] == 32'hA0000007);
    check("palabras protegidas por la mascara", got[63:32] == 32'h0 && got[127:96] == 32'h0);

    // rafaga de solicitudes seguidas: cada una debe tardar exactamente Tmem
    for (k = 0; k < 6; k = k + 1) begin
      op(k[0], 11'(100 + k), {8{32'h12345678 + k}}, 8'hFF, got, lat);
      check("latencia entre solicitudes consecutivas", lat == TMEM);
    end
    op(1'b0, 11'd101, '0, 8'h00, got, lat);
    check("lectura de una linea escrita completa", got == {8{32'h12345679}});

    @(negedge clk);
    check("contadores de lectura y escritura", n_rd == 6 && n_wr == 4);
    check("ciclos ocupados", n_busy == (n_rd + n_wr) * TMEM);
    check("watchdog sin disparar", !err);
    // Interrumpir una lectura y volver a usar el controlador.
    req = 1; we = 0; la = 11'd5;
    @(negedge clk); req = 0;
    repeat (4 * DIV) @(negedge clk);
    rst = 1;
    repeat (2 * DIV) @(negedge clk);
    rst = 0;
    op(1'b0, 11'd101, '0, 8'h00, got, lat);
    check("primera lectura tras reset", got == {8{32'h12345679}} && lat == TMEM);
    check("contadores tras reset", n_rd == 1 && n_wr == 0 && !err);
    if (errors == 0) $display("tb_dram_ctrl (DIV=%0d, Tmem=%0d): PASS", DIV, TMEM);
    else             $fatal(1, "tb_dram_ctrl (DIV=%0d): FAIL (%0d errores)", DIV, errors);
    $finish;
  end
endmodule
