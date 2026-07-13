module expression_leaf(input logic a, output logic y, inout wire io);
    assign y = a;
    assign io = a;
endmodule
module expression_top(input logic a, output logic [1:0] y, inout wire io);
    expression_leaf u_leaf(.a(a), .y(y[0]), .io(io));
endmodule
