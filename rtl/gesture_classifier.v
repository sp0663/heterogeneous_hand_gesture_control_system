// Instantiates the feature extractor and applies rule-based gesture classification on the computed features.


module gesture_classifier (
    input clk,
    input rst,
    input valid_in,

    input [335:0] x,
    input [335:0] y,

    output reg [7:0] gesture_id,
    output reg valid_out
);
    localparam PINCH = 0, FIST = 1, OPEN_HAND = 2, INDEX_FINGER = 3, UNKNOWN = 4;

    wire [32:0] dist_thumb_index;
    wire [32:0] dist_wrist_middle;

    wire thumb_extended;
    wire index_extended;
    wire middle_extended;
    wire ring_extended;
    wire pinky_extended;

    wire thumb_angle_valid;
    wire index_angle_valid;
    wire middle_angle_valid;
    wire ring_angle_valid;
    wire pinky_angle_valid;
    wire all_angle_valid = thumb_angle_valid & index_angle_valid & middle_angle_valid & ring_angle_valid & pinky_angle_valid;

    reg valid_in_1, valid_in_2, valid_in_3;  // Delayed versions of valid_in for timing alignment
    
    feature_extractor features (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),

        .x(x),
        .y(y),

        .dist_thumb_index(dist_thumb_index),
        .dist_wrist_middle(dist_wrist_middle),

        .thumb_extended(thumb_extended),
        .index_extended(index_extended),
        .middle_extended(middle_extended),
        .ring_extended(ring_extended),
        .pinky_extended(pinky_extended),

        .thumb_angle_valid(thumb_angle_valid),
        .index_angle_valid(index_angle_valid),
        .middle_angle_valid(middle_angle_valid),
        .ring_angle_valid(ring_angle_valid),
        .pinky_angle_valid(pinky_angle_valid)
    );

    always @(posedge clk) begin
        if (rst) begin
            valid_in_1 <= 0;
            valid_in_2 <= 0;
            valid_in_3 <= 0;
        end else begin
            valid_in_1 <= valid_in;
            valid_in_2 <= valid_in_1;
            valid_in_3 <= valid_in_2;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            gesture_id <= 0;
            valid_out <= 0;
        end
        else begin
            if (valid_in_3 && all_angle_valid) begin
                if (dist_thumb_index * 16 < dist_wrist_middle) begin
                    gesture_id <= PINCH;
                    valid_out <= 1;
                end
                else if (!index_extended && !middle_extended && !ring_extended && !pinky_extended) begin
                    gesture_id <= FIST;
                    valid_out <= 1;
                end
                else if (thumb_extended && index_extended && middle_extended && ring_extended && pinky_extended) begin
                    gesture_id <= OPEN_HAND;
                    valid_out <= 1;
                end
                else if (index_extended && !middle_extended && !ring_extended && !pinky_extended) begin
                    gesture_id <= INDEX_FINGER;
                    valid_out <= 1;
                end    
                else begin
                    gesture_id <= UNKNOWN;
                    valid_out <= 1;
                end
            end
            else begin
                valid_out <= 0;
            end
        end
    end


endmodule