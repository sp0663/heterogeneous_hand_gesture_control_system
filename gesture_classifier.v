module gesture_classifier (
    input clk,
    input rst,
    input start,

    input [15:0] x [0:20],
    input [15:0] y [0:20],

    output reg [3:0] gesture_id,
    output reg valid_out
);

    wire [31:0] dist_thumb_index;
    wire [31:0] dist_wrist_middle;

    wire [31:0] thumb_angle;
    wire [31:0] index_angle;
    wire [31:0] middle_angle;
    wire [31:0] ring_angle;
    wire [31:0] pinky_angle;

    // Instantiates the feature extractor and applies rule-based gesture classification on the computed features.

    feature_extractor features (
        .clk(clk),
        .rst(rst),
        .start(start),

        .x(x),
        .y(y),

        .dist_thumb_index(dist_thumb_index),
        .dist_wrist_middle(dist_wrist_middle),

        .thumb_angle(thumb_angle),
        .index_angle(index_angle),
        .middle_angle(middle_angle),
        .ring_angle(ring_angle),
        .pinky_angle(pinky_angle)
    );

endmodule