//Computes the angle between three landmarks (x1, y1), (x2, y2), and (x3, y3) using CORDIC algorithm.

module angle_calculator (
    input clk,
    input rst,
    input valid_in,

    input [15:0] x1,
    input [15:0] y1,
    input [15:0] x2,
    input [15:0] y2,
    input [15:0] x3,
    input [15:0] y3,

    output reg [31:0] angle,
    output reg valid_out
);
    //CORDIC IP

endmodule