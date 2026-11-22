// Informa violaciones del contrato. Con stall de cache no se cuentan hazards del bundle congelado.
module hazard_monitor (
  input  logic         clk,
  input  logic         rst,
  input  logic [127:0] ifid_bundle,
  input  logic         ifid_valid,
  input  logic         ex_flush,
  input  logic [127:0] idex_bundle,
  input  logic         idex_valid,
  input  logic [4:0]   exwb_wen,
  input  logic [24:0]  exwb_waddr,
  input  logic         stall,
  input  logic         trace,
  output integer       raw_count,
  output integer       waw_count
);
  logic [39:0] ra_i; logic [7:0] ru_i; logic [24:0] wa_i; logic [4:0] wu_i; logic il_i;
  logic [39:0] ra_e; logic [7:0] ru_e; logic [24:0] wa_e; logic [4:0] wu_e; logic il_e;
  logic [31:0] u0, u1, u2, u3, v0, v1, v2, v3;

  dispatch d_id (.bundle(ifid_bundle), .slot0(u0), .slot1(u1), .slot2(u2), .slot3(u3),
                 .raddr(ra_i), .ruse(ru_i), .waddr(wa_i), .wuse(wu_i), .illegal_op(il_i));
  dispatch d_ex (.bundle(idex_bundle), .slot0(v0), .slot1(v1), .slot2(v2), .slot3(v3),
                 .raddr(ra_e), .ruse(ru_e), .waddr(wa_e), .wuse(wu_e), .illegal_op(il_e));

  integer p, q, w;
  initial begin raw_count = 0; waw_count = 0; end

  always @(posedge clk) begin
    if (!rst && ifid_valid && !ex_flush && !stall) begin
      for (p = 0; p < 8; p = p + 1) begin
        if (ru_i[p] && ra_i[5*p +: 5] != 5'd0) begin
          for (w = 0; w < 5; w = w + 1) begin
            if (idex_valid && wu_e[w] && wa_e[5*w +: 5] == ra_i[5*p +: 5]) begin
              raw_count = raw_count + 1;
              if (trace) $display("HAZARD RAW: r%0d leido en ID mientras se escribe desde EX (slot %0d)", ra_i[5*p +: 5], w);
            end
            if (exwb_wen[w] && exwb_waddr[5*w +: 5] == ra_i[5*p +: 5]) begin
              raw_count = raw_count + 1;
              if (trace) $display("HAZARD RAW: r%0d leido en ID mientras se escribe desde WB (puerto %0d)", ra_i[5*p +: 5], w);
            end
          end
        end
      end
      for (p = 0; p < 5; p = p + 1)
        for (q = p + 1; q < 5; q = q + 1)
          if (wu_i[p] && wu_i[q] && wa_i[5*p +: 5] == wa_i[5*q +: 5] && wa_i[5*p +: 5] != 5'd0 &&
              !(p == 3 && q == 4)) begin
            waw_count = waw_count + 1;
            if (trace) $display("HAZARD WAW: r%0d escrito por dos slots del mismo bundle", wa_i[5*p +: 5]);
          end
    end
  end
endmodule
