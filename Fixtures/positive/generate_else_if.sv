module generate_else_if #(parameter SELECT = 1) (output logic y);
    generate
        if (SELECT == 0) begin : zero
            assign y = 1'b0;
        end else if (SELECT == 1) begin : one
            assign y = 1'b1;
        end else begin : other
            assign y = 1'b0;
        end
    endgenerate
endmodule
