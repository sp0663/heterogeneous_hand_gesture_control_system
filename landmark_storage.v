module landmark_storage (
    input clk,
    input rst,

    input valid_in,              // new landmark available
    input [4:0] landmark_id,     // 0–20
    input [15:0] x_in,
    input [15:0] y_in,

    output reg frame_ready,      // high when all landmarks for a frame received

    output reg [15:0] x_out [0:20],
    output reg [15:0] y_out [0:20]
);

    // Stores incoming landmark coordinates into register arrays indexed by landmark_id and asserts frame_ready when the last landmark of the frame is received.

endmodule