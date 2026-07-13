module macro_expansion #(parameter BASE = 2) (output logic y);
    `define OFFSET (BASE + 1)
    `define ADD(a, b) ((a) + (b))
    wire [`OFFSET-1:0] data;
    assign data = 3'b101;
    assign y = `ADD(data[0], 1'b0);
endmodule
