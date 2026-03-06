module gesture_system_top (
    input clk,
    input rst,

    input rx,      // UART RX from Jetson Nano
    output tx      // UART TX back to Jetson Nano
);

    wire [4:0] landmark_id;
    wire [15:0] x_coord;
    wire [15:0] y_coord;
    wire landmark_valid;

    wire frame_ready;

    wire [15:0] x [0:20];
    wire [15:0] y [0:20];

    wire [3:0] gesture_id;
    wire gesture_valid;

    wire baud_tick;


    // UART Landmark Receiver (UART RX + packet parser)
    uart_landmark_rx uart_landmark_rx_inst (
        .clk(clk),
        .rst(rst),
        .rx(rx),
        .landmark_id(landmark_id),
        .x_out(x_coord),
        .y_out(y_coord),
        .valid_out(landmark_valid)
    );
    // Receives UART data and extracts landmark id and coordinates


    // Landmark Storage
    landmark_storage landmark_storage_inst (
        .clk(clk),
        .rst(rst),
        .valid_in(landmark_valid),
        .landmark_id(landmark_id),
        .x_in(x_coord),
        .y_in(y_coord),
        .frame_ready(frame_ready),
        .x_out(x),
        .y_out(y)
    );
    // Stores incoming landmarks and outputs full landmark frame


    // Gesture Classifier (includes feature extractor)
    gesture_classifier gesture_classifier_inst (
        .clk(clk),
        .rst(rst),
        .start(frame_ready),
        .x(x),
        .y(y),
        .gesture_id(gesture_id),
        .valid_out(gesture_valid)
    );
    // Computes features and classifies the hand gesture

    baud_generator baud_gen (
    .clk(clk),
    .rst(rst),
    .baud_tick(baud_tick)
    );


    // Output Interface
    output_interface output_interface_inst (
        .clk(clk),
        .rst(rst),
        .baud_tick(baud_tick),
        .gesture_id(gesture_id),
        .valid_in(gesture_valid),
        .tx(tx)
    );
    // Formats gesture packet and transmits via UART

endmodule