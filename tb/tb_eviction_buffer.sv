module tb_eviction_buffer;
  logic clk = 0, rst = 1;
  always #5 clk = ~clk;

  logic push, pop, full, empty, head_valid, hit;
  logic [10:0] push_la, head_la, q_la;
  logic [255:0] push_line, head_line, q_line;
  logic [1:0] count;
  logic [31:0] pushes, max_occupancy;

  eviction_buffer #(.DEPTH(3)) dut (.clk(clk), .rst(rst), .push(push), .push_la(push_la),
      .push_line(push_line), .full(full), .empty(empty), .head_valid(head_valid),
      .head_la(head_la), .head_line(head_line), .pop(pop), .q_la(q_la), .q_hit(hit),
      .q_line(q_line), .count(count), .cnt_pushes(pushes), .cnt_max_occupancy(max_occupancy));

  task automatic step(input bit put, input bit take, input logic [10:0] address, input logic [31:0] word);
    push = put; pop = take; push_la = address; push_line = {8{word}};
    @(negedge clk);
    push = 0; pop = 0;
  endtask

  task automatic check_head(input logic [10:0] address, input logic [31:0] word);
    if ({head_valid, head_la, head_line} !== {1'b1, address, {8{word}}})
      $fatal(1, "Cabeza incorrecta, se esperaba la linea %0d", address);
  endtask

  initial begin
    push = 0; pop = 0; push_la = 0; push_line = 0; q_la = 11'd7;
    repeat (3) @(negedge clk);
    rst = 0;
    step(0, 1, 0, 0);
    if ({empty, head_valid, count} !== {1'b1, 1'b0, 2'd0}) $fatal(1, "FIFO vacia");

    step(1, 0, 7, 32'h70000000);
    step(1, 0, 8, 32'h80000000);
    step(1, 0, 7, 32'h71111111);
    if (full !== 1 || count !== 3 || max_occupancy !== 3) $fatal(1, "FIFO llena");
    if (hit !== 1 || q_line !== {8{32'h71111111}}) $fatal(1, "Forwarding de la linea 7");

    step(1, 0, 9, 32'h90000000);
    repeat (4) @(negedge clk);
    check_head(7, 32'h70000000);
    if (pushes !== 3) $fatal(1, "Escritura aceptada con la FIFO llena");

    step(0, 1, 0, 0);
    check_head(8, 32'h80000000);
    step(1, 1, 9, 32'h90000000);
    check_head(7, 32'h71111111);
    if (count !== 2) $fatal(1, "Push y pop simultaneos");

    step(0, 1, 0, 0);
    check_head(9, 32'h90000000);
    if (hit !== 0) $fatal(1, "La linea 7 ya salio");
    step(0, 1, 0, 0);
    if (empty !== 1 || head_valid !== 0 || pushes !== 4 || max_occupancy !== 3)
      $fatal(1, "Drenado de la FIFO");
    $display("tb_eviction_buffer: PASS");
    $finish;
  end
endmodule
