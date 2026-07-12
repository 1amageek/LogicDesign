module conditional_generate(input logic a, output logic y);
  parameter ENABLE = 1;
  generate
    if (ENABLE) begin : enabled
      assign y = a;
    end else begin : disabled
      assign y = 1'b0;
    end
  endgenerate
endmodule
