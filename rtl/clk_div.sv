// clk_div.sv - Genera el reloj de la memoria principal a partir del reloj del procesador.
// fmem = fcpu / DIV (100 MHz / 4 = 25 MHz por omision). Corre libre desde el arranque
// (no depende del reset) para que el dominio de la DRAM tenga flancos durante el reset.
module clk_div #(parameter int DIV = 4) (
  input  logic clk,
  output logic clk_out
);
  localparam int W = (DIV > 1) ? $clog2(DIV) : 1;
  logic [W-1:0] cnt;
  initial begin cnt = '0; clk_out = 1'b0; end

  generate
    if (DIV <= 1) begin : g_passthru
      always @* clk_out = clk;
    end else begin : g_div
      always @(posedge clk) begin
        if (cnt == W'(DIV - 1)) cnt <= '0;
        else                    cnt <= cnt + 1'b1;
        // alto durante la primera mitad del periodo (para DIV impar el ciclo de trabajo no es 50 %)
        clk_out <= ((cnt == W'(DIV - 1)) ? '0 : cnt + 1'b1) < W'(DIV / 2);
      end
    end
  endgenerate
endmodule
