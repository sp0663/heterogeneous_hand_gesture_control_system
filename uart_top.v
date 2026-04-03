module uart_top
    #(
        parameter   DBITS = 8,          
                    SB_TICK = 16,       
                    BR_LIMIT = 27,     
                    BR_BITS = 5,       
                    FIFO_EXP = 7        
    )
    (
        input clk_50MHz,               
        input reset,                    
        input write_uart,               // Remains for TX (sending data back)
        input rx,                       
        input [DBITS-1:0] write_data,   
        output tx,                      
        
        // Landmark Outputs
        output frame_ready,             // High when all 21 points are stored
        output [335:0] landmarks_x,     // Full X vector for the recognizer
        output [335:0] landmarks_y      // Full Y vector for the recognizer
    );
    
    // Internal Connection Signals
    wire tick;                          
    wire rx_done_tick;                  
    wire tx_done_tick;                  
    wire tx_empty;                      
    wire tx_fifo_not_empty;             
    wire [DBITS-1:0] tx_fifo_out;       
    wire [DBITS-1:0] rx_data_out;       
    wire [DBITS-1:0] fifo_rx_data;      // Data leaving FIFO
    wire rx_empty;                      // FIFO status
    
    // Assembler to Storage Wires
    wire [15:0] assemble_x, assemble_y;
    wire [4:0]  assemble_id;
    wire        assemble_valid;
    wire        fifo_rd_en;             // Automated read signal from Assembler

    // 1. Baud Rate Generator
    baud_rate_generator #( .M(BR_LIMIT), .N(BR_BITS) ) BAUD_RATE_GEN (
        .clk_50MHz(clk_50MHz), .reset(reset), .tick(tick)
    );
    
    // 2. UART Receiver
    uart_rx #( .DBITS(DBITS), .SB_TICK(SB_TICK) ) UART_RX_UNIT (
        .clk_50MHz(clk_50MHz), .reset(reset), .rx(rx),
        .sample_tick(tick), .data_ready(rx_done_tick), .data_out(rx_data_out)
    );
    
    // 3. FIFO Receiver Buffer
    fifo #( .DATA_SIZE(DBITS), .ADDR_SPACE_EXP(FIFO_EXP) ) FIFO_RX_UNIT (
        .clk(clk_50MHz), .reset(reset),
        .write_to_fifo(rx_done_tick),   // Written by UART_RX
        .read_from_fifo(fifo_rd_en),    // Read by Assembler
        .write_data_in(rx_data_out),
        .read_data_out(fifo_rx_data),
        .empty(rx_empty),
        .full()                         // Open
    );

    // 4. Coordinate Assembler 
    // Takes 8-bit bytes from FIFO, outputs 16-bit X, Y
    coord_assembler ASSEMBLER_UNIT (
        .clk(clk_50MHz), .rst(reset),
        .fifo_data(fifo_rx_data),
        .fifo_empty(rx_empty),
        .fifo_rd_en(fifo_rd_en),
        .x_out(assemble_x), .y_out(assemble_y),
        .landmark_id(assemble_id),
        .valid_out(assemble_valid)
    );

    // 5. Landmark Storage 
    // Takes 16-bit points, stores them in the 336-bit vector
    landmark_storage STORAGE_UNIT (
        .clk(clk_50MHz), .rst(reset),
        .valid_in(assemble_valid),
        .landmark_id(assemble_id),
        .x_in(assemble_x), .y_in(assemble_y),
        .frame_ready(frame_ready),
        .x_out(landmarks_x),
        .y_out(landmarks_y)
    );
    
    // 6. UART Transmitter (For sending results back to PC)
    uart_transmitter #( .DBITS(DBITS), .SB_TICK(SB_TICK) ) UART_TX_UNIT (
        .clk_50MHz(clk_50MHz), .reset(reset),
        .tx_start(tx_fifo_not_empty), .sample_tick(tick),
        .data_in(tx_fifo_out), .tx_done(tx_done_tick), .tx(tx)
    );
    
    // 7. FIFO Transmitter Buffer
    fifo #( .DATA_SIZE(DBITS), .ADDR_SPACE_EXP(FIFO_EXP) ) FIFO_TX_UNIT (
        .clk(clk_50MHz), .reset(reset),
        .write_to_fifo(write_uart),
        .read_from_fifo(tx_done_tick),
        .write_data_in(write_data),
        .read_data_out(tx_fifo_out),
        .empty(tx_empty),
        .full()                
    );

    assign tx_fifo_not_empty = ~tx_empty;
  
endmodule