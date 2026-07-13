`define SECOND 1
`ifdef FIRST
    module conditional_compilation(input logic a, output logic y);
        assign y = 1'b0;
    endmodule
`elsif SECOND
    module conditional_compilation(input logic a, output logic y);
        assign y = a;
    endmodule
`else
    module conditional_compilation(input logic a, output logic y);
        assign y = 1'b1;
    endmodule
`endif
