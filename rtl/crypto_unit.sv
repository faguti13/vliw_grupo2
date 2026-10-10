// crypto_unit.sv - Unidad criptografica y de seguridad (slot 3).
// Cripto (100): LOADKEY, FROUND. Seguridad (101): AUTH, LOGOUT, RDSR.
// Contiene el registro de estado SR: bit0 AUTH, bit1 VAULT_ERR (sticky), bits[4:2] ERR_CODE.
// El bloqueo es de hardware: vault_we = SR.AUTH & loadkey_valid; fround_we = SR.AUTH & fround_valid.
module crypto_unit #(parameter logic [31:0] CRED = 32'hCAFE1234) (
  input  logic        clk,
  input  logic        rst,
  input  logic        valid,     // el bundle esta en EX y no fue descartado
  input  logic [31:0] instr,
  input  logic [31:0] a,         // GPR[rs_L]
  input  logic [31:0] b,         // GPR[rs_R] / fuente de LOADKEY / credencial
  output logic        wen_l,
  output logic [4:0]  rd_l,
  output logic [31:0] y_l,
  output logic        wen_r,
  output logic [4:0]  rd_r,
  output logic [31:0] y_r,
  output logic        illegal,
  output logic [31:0] sr_o
);
  import vliw_pkg::*;

  logic [31:0] sr;
  logic sr_auth, sr_err;
  logic [2:0] sr_code;
  assign sr_auth = sr[0];
  assign sr_err  = sr[1];
  assign sr_code = sr[4:2];
  assign sr_o    = sr;

  logic [2:0] opc;
  logic [3:0] funct;
  logic [1:0] key_idx, sub_idx;
  assign opc     = instr[2:0];
  assign funct   = instr[6:3];
  assign key_idx = instr[18:17];
  assign sub_idx = instr[20:19];

  logic loadkey_valid, fround_valid, auth_op, logout_op, rdsr_op;
  assign loadkey_valid = valid && opc == OP_CRY && funct == 4'b0000;
  assign fround_valid  = valid && opc == OP_CRY && funct == 4'b0001;
  assign auth_op       = valid && opc == OP_SEC && funct == 4'b0000;
  assign logout_op     = valid && opc == OP_SEC && funct == 4'b0001;
  assign rdsr_op       = valid && opc == OP_SEC && funct == 4'b0010;

  logic vault_we, fround_we;
  assign vault_we  = sr_auth & loadkey_valid;
  assign fround_we = sr_auth & fround_valid;

  logic [31:0] subkey;
  key_vault u_vault (
    .clk(clk), .we(vault_we), .wkey(key_idx), .wsub(sub_idx), .wdata(b),
    .rkey(key_idx), .rsub(sub_idx), .rdata(subkey)
  );

  logic [31:0] f;
  assign f = feistel_f(b, subkey);

  always @* begin
    wen_l = 1'b0; wen_r = 1'b0;
    rd_l  = instr[30:26]; rd_r = instr[25:21];
    y_l   = b;            y_r  = a ^ f;
    illegal = 1'b0;
    if (opc == OP_CRY) begin
      case (funct)
        4'b0000, 4'b1111: ;
        4'b0001: begin wen_l = fround_we; wen_r = fround_we; end
        default: illegal = 1'b1;
      endcase
    end else if (opc == OP_SEC) begin
      case (funct)
        4'b0000, 4'b0001: ;
        4'b0010: begin wen_l = rdsr_op; rd_l = instr[11:7]; y_l = sr; end
        4'b1111: ;
        default: illegal = 1'b1;
      endcase
    end else illegal = 1'b1;
  end

  always @(posedge clk) begin
    if (rst) sr <= 32'h0;
    else begin
      if (auth_op) begin
        if (b == CRED) sr <= 32'h1;                                // AUTH ok: limpia errores
        else           sr <= {27'b0, 3'b010, 1'b1, 1'b0};          // fallo: ERR_CODE=010, VAULT_ERR=1
      end else if (logout_op) begin
        sr[0] <= 1'b0;
      end else if ((loadkey_valid || fround_valid) && !sr_auth) begin
        sr[1]   <= 1'b1;                                           // VAULT_ERR sticky
        sr[4:2] <= 3'b001;                                         // acceso no autorizado
      end
    end
  end
endmodule
