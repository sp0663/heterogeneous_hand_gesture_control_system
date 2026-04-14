module gesture_system_top (
    input clk,
    input rst,
    input rx,
	 output tx
);

    wire frame_ready;

    wire [335:0] x;
    wire [335:0] y;

    wire [2:0] gesture_id;
    wire gesture_valid;

    gesture_classifier gesture_classifier_inst (
        .clk(clk),
        .rst(rst),
        .valid_in(frame_ready),
        .x(x),
        .y(y),
        .gesture_id(gesture_id),
        .valid_out(gesture_valid)
    );
	 
	 uart_top uart_top_inst (
		  .clk_50MHz(clk),               
        .reset(rst),                    
        .write_uart(gesture_valid),             
        .rx(rx),       
		  .write_data(gesture_id),
        .tx(tx),                      
        .frame_ready(frame_ready),
		  .landmarks_x(x),     
        .landmarks_y(y)  
	 );

endmodule