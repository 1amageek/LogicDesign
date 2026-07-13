module memory_leaf #(parameter WIDTH = 2, parameter DEPTH = 4) (
    input logic [1:0] address,
    output logic [WIDTH-1:0] value
);
    logic [WIDTH-1:0] memory [0:DEPTH-1];
    assign value = memory[address];
endmodule
module memory_top(input logic [1:0] address, output logic [1:0] value);
    memory_leaf #(.WIDTH(2), .DEPTH(8)) u_leaf(.address(address), .value(value));
endmodule
