module unknown_parameter_leaf #(parameter WIDTH = 1) (
    input logic [WIDTH-1:0] a,
    output logic [WIDTH-1:0] y
);
    assign y = a;
endmodule

module unknown_parameter_top(input logic a, output logic y);
    unknown_parameter_leaf #(.UNKNOWN(4)) u_leaf(.a(a), .y(y));
endmodule
