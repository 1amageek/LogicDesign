`timescale 1ns/1ps
`define WIDTH 4
module preprocessor(input logic [`WIDTH-1:0] a, output logic [`WIDTH-1:0] y);
  assign y = a;
endmodule
