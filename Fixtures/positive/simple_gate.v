module top(a, y);
    wire n1;
    NAND2_X1 u1(.A(a), .B(a), .Y(n1));
    INV_X1 u2(.A(n1), .Y(y));
endmodule
