// dram_ctrl.sv - Memoria principal (DRAM) de datos de 64 KB con su propio reloj.
//
// Dos dominios de reloj:
//   - clk (CPU, 100 MHz): recibe la solicitud de linea (32 B) y entrega `done` con el dato.
//   - clk_mem (fmem = fcpu / DIV, 25 MHz): motor de rafaga que lee o escribe 1 palabra por flanco.
// Cruce de dominio por handshake de 2 fases (toggle req/ack) sincronizado con 2 flip-flops:
//   CPU: registra el comando (estable hasta `done`) y alterna req_tog.
//   MEM: ve el cambio de req_tog (2 FF), hace la rafaga de 8 palabras y alterna ack_tog.
//   CPU: ve ack_tog (2 FF); el bus de datos `mline` ya esta estable desde antes.
// Modelo de tiempo del enunciado: 25 ciclos de CPU a la primera palabra + 7 palabras a
// 1 palabra por ciclo de clk_mem => Tmem = T_FIRST + 7 * DIV = 53 ciclos de CPU por linea.
// El contador del lado CPU fija esa latencia; el handshake garantiza que el dato cruzo.
// Si el ack no llega en WATCHDOG ciclos se levanta err_timeout (watchdog).
//
// IDEAL = 1: el arreglo se usa como memoria ideal de 1 ciclo (puerto de palabra en clk).
module dram_ctrl #(
  parameter int  DIV      = 4,
  parameter int  T_FIRST  = 25,
  parameter int  BYTES    = 65536,
  parameter bit  IDEAL    = 1'b0,
  parameter int  WATCHDOG = 1000
) (
  input  logic         clk,
  input  logic         rst,
  input  logic         clk_mem,
  // puerto de linea (dominio CPU)
  input  logic         req,        // se acepta cuando idle = 1
  input  logic         we,
  input  logic [10:0]  la,         // direccion de linea (addr[15:5])
  input  logic [255:0] wdata,      // palabra i en [32*i +: 32]
  input  logic [7:0]   wmask,      // palabras a escribir
  output logic         idle,
  output logic         done,       // pulso: la operacion termino (rdata valido)
  output logic [255:0] rdata,
  // puerto ideal (IDEAL = 1)
  input  logic [15:0]  i_addr,
  input  logic         i_we,
  input  logic [31:0]  i_wdata,
  output logic [31:0]  i_rdata,
  // contadores (seccion 5.3)
  output logic [31:0]  cnt_reads,
  output logic [31:0]  cnt_writes,
  output logic [31:0]  cnt_busy,
  output logic         err_timeout
);
  localparam int TMEM = T_FIRST + 7 * DIV;

  logic [7:0] mem [0:BYTES-1];
  integer k;
  initial begin
    for (k = 0; k < BYTES; k = k + 1) mem[k] = 8'h00;
  end

  // ---------------- Dominio CPU ----------------
  logic         busy;
  logic [15:0]  cnt;
  logic         c_we;
  logic [10:0]  c_la;
  logic [255:0] c_wdata;
  logic [7:0]   c_wmask;
  logic         req_tog;
  logic         ack_s1, ack_s2;      // sincronizador del ack hacia clk
  logic         ack_tog;             // (dominio clk_mem)
  logic [255:0] mline;               // (dominio clk_mem) linea leida
  initial begin req_tog = 1'b0; ack_s1 = 1'b0; ack_s2 = 1'b0; end

  assign idle  = !busy;
  assign done  = busy && (cnt >= 16'(TMEM)) && (ack_s2 == req_tog);
  assign rdata = mline;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      req_tog <= 1'b0; ack_s1 <= 1'b0; ack_s2 <= 1'b0;
      busy <= 1'b0; cnt <= '0; cnt_reads <= '0; cnt_writes <= '0; cnt_busy <= '0; err_timeout <= 1'b0;
    end else begin
      ack_s1 <= ack_tog;
      ack_s2 <= ack_s1;
      if (!busy) begin
        if (req && !IDEAL) begin
          busy    <= 1'b1;
          cnt     <= 16'd1;
          c_we    <= we;
          c_la    <= la;
          c_wdata <= wdata;
          c_wmask <= wmask;
          req_tog <= ~req_tog;
          if (we) cnt_writes <= cnt_writes + 1;
          else    cnt_reads  <= cnt_reads + 1;
        end
      end else begin
        cnt_busy <= cnt_busy + 1;
        if (done) busy <= 1'b0;
        else begin
          cnt <= cnt + 1;
          if (cnt > 16'(WATCHDOG)) begin
            err_timeout <= 1'b1;
`ifndef SYNTHESIS
            if (!err_timeout) $display("ERROR dram_ctrl: watchdog, no llego el ack del dominio de memoria");
`endif
          end
        end
      end
    end
  end

  // ---------------- Dominio de memoria ----------------
  logic       req_s1, req_s2;        // sincronizador de la solicitud hacia clk_mem
  logic       m_busy;
  logic [2:0] beat;
  initial begin req_s1 = 1'b0; req_s2 = 1'b0; ack_tog = 1'b0; m_busy = 1'b0; beat = 3'd0; mline = '0; end

  logic mclk;
  assign mclk = IDEAL ? clk : clk_mem;

  logic [15:0] base, wa;
  assign base = {c_la, 5'b0};
  assign wa   = base + {11'b0, beat, 2'b00};

  always @(posedge mclk or posedge rst) begin
    if (rst) begin
      req_s1 <= 1'b0; req_s2 <= 1'b0; ack_tog <= 1'b0;
      m_busy <= 1'b0; beat <= '0;
    end else if (IDEAL) begin
      if (i_we) begin
        mem[{i_addr[15:2], 2'b00}]     <= i_wdata[31:24];
        mem[{i_addr[15:2], 2'b01}]     <= i_wdata[23:16];
        mem[{i_addr[15:2], 2'b10}]     <= i_wdata[15:8];
        mem[{i_addr[15:2], 2'b11}]     <= i_wdata[7:0];
      end
    end else begin
      req_s1 <= req_tog;
      req_s2 <= req_s1;
      if (!m_busy) begin
        if (req_s2 != ack_tog) begin m_busy <= 1'b1; beat <= 3'd0; end
      end else begin
        if (c_we) begin
          if (c_wmask[beat]) begin
            mem[wa]     <= c_wdata[32*beat + 24 +: 8];
            mem[wa + 1] <= c_wdata[32*beat + 16 +: 8];
            mem[wa + 2] <= c_wdata[32*beat + 8 +: 8];
            mem[wa + 3] <= c_wdata[32*beat +: 8];
          end
        end else begin
          mline[32*beat +: 32] <= {mem[wa], mem[wa + 1], mem[wa + 2], mem[wa + 3]};
        end
        beat <= beat + 1'b1;
        if (beat == 3'd7) begin m_busy <= 1'b0; ack_tog <= req_s2; end
      end
    end
  end

  assign i_rdata = {mem[{i_addr[15:2], 2'b00}], mem[{i_addr[15:2], 2'b01}],
                    mem[{i_addr[15:2], 2'b10}], mem[{i_addr[15:2], 2'b11}]};

  // Lectura directa para la vista coherente del testbench (no es un puerto de hardware)
  function automatic logic [7:0] peek(input logic [15:0] a);
    return mem[a];
  endfunction
endmodule
