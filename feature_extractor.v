module feature_extractor (
    input clk,
    input rst,
    input start,

    input [15:0] x [0:20],
    input [15:0] y [0:20],

    output [31:0] dist_thumb_index,
    output [31:0] dist_wrist_middle,

    output [31:0] thumb_angle,
    output [31:0] index_angle,
    output [31:0] middle_angle,
    output [31:0] ring_angle,
    output [31:0] pinky_angle
);

    // Instantiates distance and angle feature modules operating in parallel using MediaPipe landmark indices.

    landmark_distance dist_thumb_index_unit (
        .clk(clk),
        .rst(rst),
        .start(start),
        .x1(x[4]),
        .y1(y[4]),
        .x2(x[8]),
        .y2(y[8]),
        .dist_sq(dist_thumb_index),
        .valid_out()
    );

    landmark_distance dist_wrist_middle_unit (
        .clk(clk),
        .rst(rst),
        .start(start),
        .x1(x[0]),
        .y1(y[0]),
        .x2(x[12]),
        .y2(y[12]),
        .dist_sq(dist_wrist_middle),
        .valid_out()
    );

    angle_calculator thumb_angle_unit (
        .clk(clk),
        .rst(rst),
        .start(start),
        .x1(x[2]),
        .y1(y[2]),
        .x2(x[3]),
        .y2(y[3]),
        .x3(x[4]),
        .y3(y[4]),
        .dot_product(thumb_angle),
        .valid_out()
    );

    angle_calculator index_angle_unit (
        .clk(clk),
        .rst(rst),
        .start(start),
        .x1(x[5]),
        .y1(y[5]),
        .x2(x[6]),
        .y2(y[6]),
        .x3(x[7]),
        .y3(y[7]),
        .dot_product(index_angle),
        .valid_out()
    );

    angle_calculator middle_angle_unit (
        .clk(clk),
        .rst(rst),
        .start(start),
        .x1(x[9]),
        .y1(y[9]),
        .x2(x[10]),
        .y2(y[10]),
        .x3(x[11]),
        .y3(y[11]),
        .dot_product(middle_angle),
        .valid_out()
    );

    angle_calculator ring_angle_unit (
        .clk(clk),
        .rst(rst),
        .start(start),
        .x1(x[13]),
        .y1(y[13]),
        .x2(x[14]),
        .y2(y[14]),
        .x3(x[15]),
        .y3(y[15]),
        .dot_product(ring_angle),
        .valid_out()
    );

    angle_calculator pinky_angle_unit (
        .clk(clk),
        .rst(rst),
        .start(start),
        .x1(x[17]),
        .y1(y[17]),
        .x2(x[18]),
        .y2(y[18]),
        .x3(x[19]),
        .y3(y[19]),
        .dot_product(pinky_angle),
        .valid_out()
    );

endmodule