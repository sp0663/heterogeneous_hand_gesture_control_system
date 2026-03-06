module uart_rx (
    input clk,
    input rst,

    input rx,

    output reg [4:0] landmark_id,
    output reg [15:0] x_out,
    output reg [15:0] y_out,
    output reg valid_out
);

    // Receives UART bytes and parses the incoming landmark packet to extract landmark ID and coordinates.

endmodule