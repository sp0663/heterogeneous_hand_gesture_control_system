// Instantiates the feature extractor and applies rule-based gesture classification on the computed features.


module gesture_classifier (
    input clk,
    input rst,
    input valid_in,

    input [335:0] x,
    input [335:0] y,

    output reg [2:0] gesture_id,
    output reg valid_out
);
    localparam PINCH = 3'b000, FIST = 3'b001, OPEN_HAND = 3'b010, INDEX_FINGER = 3'b011, UNKNOWN = 3'b100;
    localparam ANGLE_THRESHOLD = 32'd183016; // 160 degrees in fixed-point representation (Q16.16)

    wire [32:0] dist_thumb_index;
    wire [32:0] dist_wrist_middle;

    wire [31:0] thumb_angle;
    wire [31:0] index_angle;
    wire [31:0] middle_angle;
    wire [31:0] ring_angle;
    wire [31:0] pinky_angle;

    wire thumb_angle_valid;
    wire index_angle_valid;
    wire middle_angle_valid;
    wire ring_angle_valid;
    wire pinky_angle_valid;
    wire all_angle_valid = thumb_angle_valid & index_angle_valid & middle_angle_valid & ring_angle_valid & pinky_angle_valid;

    
    feature_extractor features (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),

        .x(x),
        .y(y),

        .dist_thumb_index(dist_thumb_index),
        .dist_wrist_middle(dist_wrist_middle),

        .thumb_angle(thumb_angle),
        .index_angle(index_angle),
        .middle_angle(middle_angle),
        .ring_angle(ring_angle),
        .pinky_angle(pinky_angle),

        .thumb_angle_valid(thumb_angle_valid),
        .index_angle_valid(index_angle_valid),
        .middle_angle_valid(middle_angle_valid),
        .ring_angle_valid(ring_angle_valid),
        .pinky_angle_valid(pinky_angle_valid)
    );

    always @(posedge clk) begin
        if (rst) begin
            gesture_id <= 0;
            valid_out <= 0;
        end
        else begin
            valid_out <= 0;
            if (valid_in && all_angle_valid) begin
                if (dist_thumb_index * 4 < dist_wrist_middle) begin
                    gesture_id <= PINCH;
                    valid_out <= 1;
                end
                else if (thumb_angle < ANGLE_THRESHOLD && index_angle < ANGLE_THRESHOLD && middle_angle < ANGLE_THRESHOLD && ring_angle < ANGLE_THRESHOLD && pinky_angle < ANGLE_THRESHOLD) begin
                    gesture_id <= FIST;
                    valid_out <= 1;
                end
                else if (thumb_angle > ANGLE_THRESHOLD && index_angle > ANGLE_THRESHOLD && middle_angle > ANGLE_THRESHOLD && ring_angle > ANGLE_THRESHOLD && pinky_angle > ANGLE_THRESHOLD) begin
                    gesture_id <= OPEN_HAND;
                    valid_out <= 1;
                end
                else if (index_angle > ANGLE_THRESHOLD && thumb_angle < ANGLE_THRESHOLD && middle_angle < ANGLE_THRESHOLD && ring_angle < ANGLE_THRESHOLD && pinky_angle < ANGLE_THRESHOLD) begin
                    gesture_id <= INDEX_FINGER;
                    valid_out <= 1;
                end
                else begin
                    gesture_id <= UNKNOWN;
                    valid_out <= 1;
                end
            end
        end
    end


endmodule