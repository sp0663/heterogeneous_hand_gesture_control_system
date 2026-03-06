module packet_formatter (
    input clk,
    input rst,

    input [3:0] gesture_id,
    input valid_in,

    input uart_busy,

    output reg [7:0] data_out,
    output reg valid_out
);

    // Formats the detected gesture into a 3-byte UART packet (start byte, gesture id, end byte) and feeds it sequentially to the UART transmitter.

endmodule