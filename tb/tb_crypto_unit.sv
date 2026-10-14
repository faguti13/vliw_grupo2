// tb_crypto_unit.sv - Unidad cripto/seguridad: AUTH, bloqueo por SR, LOADKEY, FROUND,
// cifrado/descifrado de 4 rondas contra vectores de la referencia en C (build/vectors.hex).
module tb_crypto_unit;
  logic clk = 0, rst = 1, valid = 0; logic [31:0] instr, a, b;
  logic wen_l, wen_r, illegal; logic [4:0] rd_l, rd_r; logic [31:0] y_l, y_r, sr_o;
  crypto_unit #(.CRED(32'hCAFE1234)) dut (.*);
  always #5 clk = ~clk;
  integer errs = 0, i, r;
  reg [127:0] vec [0:15];
  reg [31:0] key [0:3];
  reg [31:0] L, R;

  function automatic [31:0] loadkey(input [1:0] k, input [1:0] s, input [4:0] src);
    loadkey = {1'b0, 5'b0, 5'b0, s, k, 5'b0, src, 4'b0000, 3'b100};
  endfunction
  function automatic [31:0] fround(input [1:0] k, input [1:0] rr, input [4:0] rl, rrr, dl, dr);
    fround = {1'b0, dl, dr, rr, k, rl, rrr, 4'b0001, 3'b100};
  endfunction
  function automatic [31:0] sec(input [3:0] f, input [4:0] r);
    sec = {20'b0, r, f, 3'b101};
  endfunction

  task automatic step(input [31:0] ins, input [31:0] va, input [31:0] vb);
    @(negedge clk); instr = ins; a = va; b = vb; valid = 1; @(negedge clk); valid = 0;
  endtask
  task automatic expect_sr(input [31:0] exp, input string n);
    #1; if (sr_o !== exp) begin errs++; $display("FAIL %s: SR=%h esp %h", n, sr_o, exp); end
  endtask

  // Ejecuta una ronda y devuelve (L',R') combinacionalmente (wen debe estar activo)
  task automatic do_round(input [1:0] k, input [1:0] rr, input [31:0] lin, input [31:0] rin,
                          output [31:0] lout, output [31:0] rout, output w);
    @(negedge clk); instr = fround(k, rr, 5'd1, 5'd2, 5'd3, 5'd4); a = lin; b = rin; valid = 1; #1;
    lout = y_l; rout = y_r; w = wen_l & wen_r;
    @(negedge clk); valid = 0;
  endtask

  reg [31:0] lo, ro; reg w;
  initial begin
    $readmemh("build/vectors.hex", vec);
    key[0] = 32'h00112233; key[1] = 32'h44556677; key[2] = 32'h8899aabb; key[3] = 32'hccddeeff;
    instr = 0; a = 0; b = 0;
    repeat (2) @(negedge clk); rst = 0;
    expect_sr(32'h0, "reset");
    // LOADKEY sin autenticar: bloqueado, VAULT_ERR + ERR_CODE=001
    step(loadkey(2, 0, 5'd1), 0, key[0]);
    expect_sr({27'b0, 3'b001, 1'b1, 1'b0}, "loadkey bloqueado");
    // FROUND sin auth: no escribe
    do_round(2, 0, 32'h1, 32'h2, lo, ro, w);
    if (w) begin errs++; $display("FAIL FROUND sin AUTH escribio"); end
    // AUTH incorrecto
    step(sec(4'd0, 5'd1), 0, 32'hBAD);
    expect_sr({27'b0, 3'b010, 1'b1, 1'b0}, "auth fallido");
    // AUTH correcto: limpia errores
    step(sec(4'd0, 5'd1), 0, 32'hCAFE1234);
    expect_sr(32'h1, "auth ok");
    // RDSR
    @(negedge clk); instr = sec(4'd2, 5'd9); valid = 1; #1;
    if (!wen_l || rd_l !== 5'd9 || y_l !== 32'h1) begin errs++; $display("FAIL RDSR"); end
    @(negedge clk); valid = 0;
    // Carga la llave 2
    for (i = 0; i < 4; i++) step(loadkey(2, i[1:0], 5'd1), 0, key[i]);
    expect_sr(32'h1, "sr tras loadkey");
    // Cifrado de los vectores: 4 FROUND encadenados
    for (i = 0; i < 6; i++) begin
      L = vec[i][127:96]; R = vec[i][95:64];
      for (r = 0; r < 4; r++) begin
        do_round(2, r[1:0], L, R, lo, ro, w);
        if (!w) begin errs++; $display("FAIL FROUND no escribio"); end
        L = lo; R = ro;
      end
      if (L !== vec[i][63:32] || R !== vec[i][31:0]) begin
        errs++; $display("FAIL cifrado vec %0d: %h %h esp %h %h", i, L, R, vec[i][63:32], vec[i][31:0]);
      end
      // Descifrado: mismas rondas en orden inverso con operandos cruzados
      // (FROUND rR,rL,...): L' va a R_nuevo y R' a L_nuevo
      for (r = 3; r >= 0; r--) begin
        do_round(2, r[1:0], R, L, lo, ro, w);   // entra (L=R_act, R=L_act)
        // salida: L'=L_act (nuevo R), R' = nuevo L
        L = ro; R = lo;
      end
      if (L !== vec[i][127:96] || R !== vec[i][95:64]) begin
        errs++; $display("FAIL descifrado vec %0d: %h %h", i, L, R);
      end
    end
    // LOGOUT y bloqueo otra vez
    step(sec(4'd1, 5'd0), 0, 0);
    expect_sr({27'b0, 3'b000, 1'b0, 1'b0}, "logout");
    do_round(2, 0, 1, 2, lo, ro, w);
    if (w) begin errs++; $display("FAIL FROUND tras LOGOUT escribio"); end
    expect_sr({27'b0, 3'b001, 1'b1, 1'b0}, "error tras logout");
    if (errs == 0) $display("tb_crypto_unit: PASS"); else begin $display("tb_crypto_unit: FAIL (%0d)", errs); $fatal(1); end
    $finish;
  end
endmodule
