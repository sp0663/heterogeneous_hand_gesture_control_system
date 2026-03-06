module output_interface (
    input wire clk,
    input wire rst,
    input wire [7:0] gesture_id,   // gesture detected by classifier
    input wire valid_in,           // classifier indicates new gesture
    output wire tx                 // UART transmit pin
);

// Internal wires
wire [7:0] packet_data;
wire packet_valid;
wire uart_busy;


// Packet Formatter
packet_formatter packet_formatter_inst (
    .clk(clk),
    .rst(rst),
    .gesture_id(gesture_id),
    .valid_in(valid_in),
    .data_out(packet_data),
    .valid_out(packet_valid),
    .busy(uart_busy)
);
// Formats gesture ID into UART packet bytes


// UART Transmitter
uart_tx uart_tx_inst (
    .clk(clk),
    .rst(rst),
    .data_in(packet_data),
    .valid_in(packet_valid),
    .tx(tx),
    .busy(uart_busy)
);
// Serializes bytes and transmits them over UART

endmodule