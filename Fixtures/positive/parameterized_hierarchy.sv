module parameterized_leaf #(
    parameter BASE = 1,
    parameter WIDTH = BASE + 1,
    parameter COUNT = 1
) (
    input logic [WIDTH-1:0] a,
    output logic [WIDTH-1:0] y
);
    wire [COUNT-1:0] bits;
    generate
        for (genvar i = 0; i < COUNT; i = i + 1) begin : g
            assign bits[i] = a[0];
        end
    endgenerate
    assign y = a;
endmodule

module parameterized_top(input logic [2:0] a, output logic [2:0] y);
    parameterized_leaf #(.BASE(2), .COUNT(3)) u_leaf(.a(a), .y(y));
endmodule
