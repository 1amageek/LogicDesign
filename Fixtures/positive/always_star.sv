module always_star(input logic a, input logic b, output logic y);
    always @* begin
        y = a | b;
    end
endmodule
