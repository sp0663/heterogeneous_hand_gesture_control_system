`timescale 1ns / 1ps

module uart_top_tb();
    reg clk_50MHz, reset, rx, write_uart;
    reg [7:0] write_data;
    
    wire tx, frame_ready;
    wire [335:0] landmarks_x;
    wire [335:0] landmarks_y;

    // 50MHz Clock
    always #10 clk_50MHz = ~clk_50MHz;

    // Instantiate the UPDATED Top Module
    uart_top #(
        .BR_LIMIT(27),     
        .FIFO_EXP(7)       
    ) dut (
        .clk_50MHz(clk_50MHz), 
        .reset(reset), 
        .rx(rx), 
        .write_data(write_data),
        .write_uart(write_uart),
        .tx(tx),
        .frame_ready(frame_ready),
        .landmarks_x(landmarks_x),
        .landmarks_y(landmarks_y)
    );

    initial begin
        $dumpfile("uart_sim.vcd");
        $dumpvars(0, uart_top_tb);
        
        // Initialize
        clk_50MHz = 0; reset = 1; rx = 1; 
        write_uart = 0; write_data = 0;
        
        #100 reset = 0; 
        #200;

        // --- TEST CASE: Send Landmark 0 ---
        // X = 1234, Y = 5678
        send_byte(8'h12); // X High
        send_byte(8'h34); // X Low
        send_byte(8'h56); // Y High
        send_byte(8'h78); // Y Low
        
        // --- TEST CASE: Send Landmark 1 ---
        // X = ABCD, Y = EF01
        send_byte(8'hAB); // X High
        send_byte(8'hCD); // X Low
        send_byte(8'hEF); // Y High
        send_byte(8'h01); // Y Low

        // Wait for the pipeline to process
        #2000;

        // Simulate sending a "Result" back via TX
        write_data = 8'hA5; // Result code
        write_uart = 1;
        #20 write_uart = 0;

        // Wait for the TX wire to finish toggling (approx 10 bits * 8680ns)
        #100000;

        $display("Check GTKWave: landmarks_x[15:0] should be 1234");
        $display("Check GTKWave: landmarks_x[31:16] should be ABCD");
        $finish;
    end

    // Task for 115200 baud bit-banging
    task send_byte(input [7:0] data);
        integer i;
        begin
            rx = 0; // Start
            #(8680);
            for (i=0; i<8; i=i+1) begin
                rx = data[i]; 
                #(8680);
            end
            rx = 1; // Stop
            #(8680);
            #1000; // Small gap between bytes
        end
    endtask

endmodule