module frame_sync (
    input  wire clk,
    input  wire rst,
    input  wire [7:0] rx_data,
    input  wire rx_valid,

    output wire [7:0] frame_data,
    output wire frame_valid,
    output wire frame_start
);

    // Detects frame boundaries in the UART byte stream, implement a counter 

endmodule