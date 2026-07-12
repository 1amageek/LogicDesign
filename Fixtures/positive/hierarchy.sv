module leaf(input logic a, output logic y);
    assign y = a;
endmodule

module top(input logic a, output logic y);
    leaf u_leaf(.a(a), .y(y));
endmodule
