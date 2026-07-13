module always_sensitivity_list(input logic a, input logic b, output logic y);
    always @(a or b) begin
        y = a ^ b;
    end
endmodule
