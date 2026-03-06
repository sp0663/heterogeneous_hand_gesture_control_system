module angle_calculator (
    input clk,
    input rst,
    input start,

    input [15:0] x1,
    input [15:0] y1,
    input [15:0] x2,
    input [15:0] y2,
    input [15:0] x3,
    input [15:0] y3,

    output reg [31:0] dot_product,
    output reg valid_out
);

    // Computes the dot product of vectors BA and BC formed by three landmarks (A, B, C) to determine finger bend/extension without using trigonometric operations.

endmodule