// Computes whether the angle between two vectors formed by three landmarks
// exceeds 160 degrees using dot product comparison with hysteresis (120-160 deg).
// No division — comparison is rearranged to use only multiplications.
// All bit widths are sized to prevent overflow.
//
// angle > 160 deg  iff  dot < 0  AND  dot^2 * 8192 > 7234 * mag1_sq * mag2_sq
// angle < 120 deg  iff  dot > 0  OR   dot^2 * 8192 < 2048 * mag1_sq * mag2_sq

module angle_calculator (
    input clk,
    input rst,
    input valid_in,

    input [15:0] x1, y1,  // first point
    input [15:0] x2, y2,  // middle point (vertex)
    input [15:0] x3, y3,  // third point

    output reg finger_extended,
    output reg valid_out
);

    // Stage 1 registers — vectors and products
    reg signed [16:0] vx1, vy1, vx2, vy2;  // 17-bit signed vectors
    reg signed [34:0] dot;                   // 35-bit signed dot product
    reg        [34:0] mag1_sq, mag2_sq;      // 35-bit unsigned magnitudes
    reg               valid_s1;

    // Stage 2 registers
    reg signed [34:0] dot_r;
    reg        [34:0] mag1_sq_r, mag2_sq_r;
    reg               valid_s2;

    // Stage 3 wires — wide multiplications (83-bit)
    wire [82:0] lhs;       // dot^2 * 8192
    wire [82:0] rhs_160;   // 7234 * mag1_sq * mag2_sq
    wire [82:0] rhs_150;   // 6144 * mag1_sq * mag2_sq
    wire [69:0] mag_prod;  // mag1_sq * mag2_sq

    assign mag_prod  = mag1_sq_r * mag2_sq_r;
    assign lhs       = (dot_r * dot_r) * 83'd8192;
    assign rhs_160   = 83'd7234 * mag_prod;
    assign rhs_150   = 83'd6144 * mag_prod;

    // Stage 1 — compute vectors, dot product, magnitudes
    always @(posedge clk) begin
        if (rst) begin
            vx1      <= 0; vy1     <= 0;
            vx2      <= 0; vy2     <= 0;
            dot      <= 0;
            mag1_sq  <= 0;
            mag2_sq  <= 0;
            valid_s1 <= 0;
        end else begin
            valid_s1 <= valid_in;

            vx1 <= $signed({1'b0, x1}) - $signed({1'b0, x2});
            vy1 <= $signed({1'b0, y1}) - $signed({1'b0, y2});
            vx2 <= $signed({1'b0, x3}) - $signed({1'b0, x2});
            vy2 <= $signed({1'b0, y3}) - $signed({1'b0, y2});

            dot     <= vx1 * vx2 + vy1 * vy2;
            mag1_sq <= vx1 * vx1 + vy1 * vy1;
            mag2_sq <= vx2 * vx2 + vy2 * vy2;
        end
    end

    // Stage 2 — register for timing
    always @(posedge clk) begin
        if (rst) begin
            dot_r     <= 0;
            mag1_sq_r <= 0;
            mag2_sq_r <= 0;
            valid_s2  <= 0;
        end else begin
            dot_r     <= dot;
            mag1_sq_r <= mag1_sq;
            mag2_sq_r <= mag2_sq;
            valid_s2  <= valid_s1;
        end
    end

    // Stage 3 — compare and output with hysteresis
    always @(posedge clk) begin
        if (rst) begin
            finger_extended <= 0;
            valid_out       <= 0;
        end else begin
            valid_out <= valid_s2;
            if (valid_s2) begin
                if (dot_r < 0 && lhs > rhs_160)
                    finger_extended <= 1;        // angle > 160 deg — turn on
                else if (dot_r >= 0 || lhs < rhs_150)
                    finger_extended <= 0;      
            end
        end
    end

endmodule