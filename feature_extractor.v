// Instantiates distance and angle feature modules operating in parallel using MediaPipe landmark indices.

module feature_extractor (
    input clk,
    input rst,
    input valid_in,

    input [335:0] x,
    input [335:0] y,

    output [32:0] dist_thumb_index,
    output [32:0] dist_wrist_middle,

    output [31:0] thumb_angle,
    output [31:0] index_angle,
    output [31:0] middle_angle,
    output [31:0] ring_angle,
    output [31:0] pinky_angle,
    
    output thumb_angle_valid,
    output index_angle_valid,
    output middle_angle_valid,
    output ring_angle_valid,
    output pinky_angle_valid
);



    landmark_distance dist_thumb_index_unit (
        .x1(x[4 * 16 +: 16]),
        .y1(y[4 * 16 +: 16]),
        .x2(x[8 * 16 +: 16]),
        .y2(y[8 * 16 +: 16]),
        .dist_sq(dist_thumb_index)
    );

    landmark_distance dist_wrist_middle_unit (
        .x1(x[0 * 16 +: 16]),
        .y1(y[0 * 16 +: 16]),
        .x2(x[12 * 16 +: 16]),
        .y2(y[12 * 16 +: 16]),
        .dist_sq(dist_wrist_middle)
    );

    angle_calculator thumb_angle_unit (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .x1(x[2 * 16 +: 16]),
        .y1(y[2 * 16 +: 16]),
        .x2(x[3 * 16 +: 16]),
        .y2(y[3 * 16 +: 16]),
        .x3(x[4 * 16 +: 16]),
        .y3(y[4 * 16 +: 16]),
        .angle(thumb_angle),
        .valid_out(thumb_angle_valid)
    );

    angle_calculator index_angle_unit (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .x1(x[5 * 16 +: 16]),
        .y1(y[5 * 16 +: 16]),
        .x2(x[6 * 16 +: 16]),
        .y2(y[6 * 16 +: 16]),
        .x3(x[7 * 16 +: 16]),
        .y3(y[7 * 16 +: 16]),
        .angle(index_angle),
        .valid_out(index_angle_valid)
    );

    angle_calculator middle_angle_unit (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .x1(x[9 * 16 +: 16]),
        .y1(y[9 * 16 +: 16]),
        .x2(x[10 * 16 +: 16]),
        .y2(y[10 * 16 +: 16]),
        .x3(x[11 * 16 +: 16]),
        .y3(y[11 * 16 +: 16]),
        .angle(middle_angle),
        .valid_out(middle_angle_valid)
    );

    angle_calculator ring_angle_unit (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .x1(x[13 * 16 +: 16]),
        .y1(y[13 * 16 +: 16]),
        .x2(x[14 * 16 +: 16]),
        .y2(y[14 * 16 +: 16]),
        .x3(x[15 * 16 +: 16]),
        .y3(y[15 * 16 +: 16]),
        .angle(ring_angle),
        .valid_out(ring_angle_valid)
    );

    angle_calculator pinky_angle_unit (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .x1(x[17 * 16 +: 16]),
        .y1(y[17 * 16 +: 16]),
        .x2(x[18 * 16 +: 16]),
        .y2(y[18 * 16 +: 16]),
        .x3(x[19 * 16 +: 16]),
        .y3(y[19 * 16 +: 16]),
        .angle(pinky_angle),
        .valid_out(pinky_angle_valid)
    );

endmodule