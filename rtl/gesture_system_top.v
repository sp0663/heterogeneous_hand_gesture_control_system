module gesture_system_top (
    input  clk_100MHz,
    input  rst,
    input  rx,
    output tx,
    output [15:0] led
);

    // MMCM generated 50 MHz clock
    wire clk_50MHz;

    clk_wiz_0 clk_inst (
        .clk_in1  (clk_100MHz),
        .clk_out1 (clk_50MHz)
    );

    // Internal wires
    wire frame_ready;
    wire [335:0] x, y;
    wire [2:0]   gesture_id;
    wire         gesture_valid;
    wire         debug_rx_done;
    wire         debug_assemble_valid;
    wire [4:0]   debug_landmark_id;
    wire         debug_frame_toggle;

    // UART top
    uart_top uart_top_inst (
        .clk_50MHz           (clk_50MHz),
        .reset               (rst),
        .write_uart          (gesture_valid),
        .rx                  (rx),
        .write_data          ({5'b00000, gesture_id}),
        .tx                  (tx),
        .frame_ready         (frame_ready),
        .landmarks_x         (x),
        .landmarks_y         (y),
        .debug_rx_done       (debug_rx_done),
        .debug_assemble_valid(debug_assemble_valid),
        .debug_landmark_id   (debug_landmark_id),
        .debug_frame_toggle  (debug_frame_toggle)
    );


    // Gesture classifier
    gesture_classifier gesture_classifier_inst (
        .clk        (clk_50MHz),
        .rst        (rst),
        .valid_in   (frame_ready),
        .x          (x),
        .y          (y),
        .gesture_id (gesture_id),
        .valid_out  (gesture_valid)
    );

    // LED debug
    //  LED15    : frame toggle  - toggles each complete frame
    //  LED14    : UART RX       - on while bytes arriving
    //  LED13    : assemble      - on while landmarks assembling
    //  LED12    : gesture valid - on after classification fires
    //  LED[7:5] : gesture_id
    //  LED[4:0] : last landmark ID (0-20)
    localparam STRETCH = 25_000_000; // 0.5s at 50MHz

    reg [24:0] rx_stretch, assemble_stretch, gesture_stretch;

    always @(posedge clk_50MHz) begin
        if (rst) begin
            rx_stretch       <= 0;
            assemble_stretch <= 0;
            gesture_stretch  <= 0;
        end else begin
            rx_stretch       <= debug_rx_done       ? STRETCH : (rx_stretch > 0       ? rx_stretch - 1       : 0);
            assemble_stretch <= debug_assemble_valid ? STRETCH : (assemble_stretch > 0 ? assemble_stretch - 1 : 0);
            gesture_stretch  <= gesture_valid        ? STRETCH : (gesture_stretch > 0  ? gesture_stretch - 1  : 0);
        end
    end

    assign led[15]   = debug_frame_toggle;
    assign led[14]   = (rx_stretch > 0);
    assign led[13]   = (assemble_stretch > 0);
    assign led[12]   = (gesture_stretch > 0);
    assign led[11:8] = 4'b0000;
    assign led[7:5]  = gesture_id;
    assign led[4:0]  = debug_landmark_id;

endmodule