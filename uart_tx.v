module uart_tx(
    input clk,
    input rst,
    input baud_tick,

    input [7:0] data_in,
    input valid_in,

    output reg tx,
    output reg busy
);

    // Serializes an input byte into UART format (start bit, 8 data bits, stop bit) and transmits it on the tx line.

endmodule