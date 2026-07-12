module generated(input logic a, output logic y);
    generate
        if (a) begin : g
            assign y = a;
        end
    endgenerate
endmodule
