// Computes cosine of the angle between two vectors formed by three landmarks.
// Uses dot product method: cos(angle) = dot(v1,v2) / (|v1| * |v2|)
// Output is the dot product scaled comparison result — finger_extended is high
// when angle > 160 degrees (i.e. cos < cos(160) = -0.9397)
//
// To avoid division, we compare:
//   dot(v1,v2) < COS_THRESHOLD * |v1| * |v2|
// Rearranged to avoid floating point:
//   dot(v1,v2)^2 * sign > COS_THRESHOLD^2 * |v1|^2 * |v2|^2
//
// Ports:
//   x1,y1 — first point
//   x2,y2 — middle point (vertex)
//   x3,y3 — third point
//   finger_extended — high when angle between vectors > 160 degrees
//   valid_out       — registered one cycle after valid_in

module angle_calculator (
    input clk,
    input rst,
    input valid_in,

    input [15:0] x1, y1,
    input [15:0] x2, y2,
    input [15:0] x3, y3,

    output reg finger_extended,
    output reg valid_out
);

    // cos(160 deg)^2 * 2^16 scaled numerator for comparison
    // cos(160)^2 = 0.8830, we use scaled integer arithmetic
    // comparison: dot^2 > 0.8830 * mag1_sq * mag2_sq AND dot < 0 (obtuse)
    // We use Q0 integer arithmetic throughout since inputs are 16-bit integers

    reg signed [16:0] vx1, vy1, vx2, vy2;
    reg signed [33:0] dot;
    reg signed [33:0] dot_r;
    reg [33:0]        mag1_sq, mag2_sq;
    reg [33:0]        mag1_sq_r, mag2_sq_r;
    reg               valid_r;

    // Stage 1 — compute vectors and dot product / magnitudes (combinational regs)
    always @(posedge clk) begin
        if (rst) begin
            vx1      <= 0; vy1      <= 0;
            vx2      <= 0; vy2      <= 0;
            dot      <= 0;
            mag1_sq  <= 0;
            mag2_sq  <= 0;
            valid_r  <= 0;
        end else begin
            valid_r <= valid_in;

            vx1 = $signed({1'b0, x1}) - $signed({1'b0, x2});
            vy1 = $signed({1'b0, y1}) - $signed({1'b0, y2});
            vx2 = $signed({1'b0, x3}) - $signed({1'b0, x2});
            vy2 = $signed({1'b0, y3}) - $signed({1'b0, y2});

            dot     <= vx1 * vx2 + vy1 * vy2;
            mag1_sq <= vx1 * vx1 + vy1 * vy1;
            mag2_sq <= vx2 * vx2 + vy2 * vy2;
        end
    end

    // Stage 2 — register dot and mags, then compare
    // cos(angle) < cos(160) iff:
    //   dot < 0  AND  dot^2 > cos(160)^2 * mag1_sq * mag2_sq
    // cos(160)^2 = 0.8830, approximated as 7237/8192 (13-bit shift)
    // i.e. dot^2 * 8192 > 7237 * mag1_sq * mag2_sq
    always @(posedge clk) begin
        if (rst) begin
            dot_r     <= 0;
            mag1_sq_r <= 0;
            mag2_sq_r <= 0;
        end else begin
            dot_r     <= dot;
            mag1_sq_r <= mag1_sq;
            mag2_sq_r <= mag2_sq;
        end
    end

    // Stage 3 — final comparison and output
    always @(posedge clk) begin
        if (rst) begin
            finger_extended <= 0;
            valid_out       <= 0;
        end else begin
            valid_out <= valid_r;
            if (valid_r) begin
                // angle > 160 deg iff dot < 0 and dot^2 > cos(160)^2 * mag1*mag2
                if (dot_r < 0 && (dot_r * dot_r) * 8192 > 7237 * (mag1_sq_r * mag2_sq_r))
                    finger_extended <= 1;
                else
                    finger_extended <= 0;
            end
        end
    end

endmodule