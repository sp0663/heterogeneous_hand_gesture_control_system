`timescale 1ns / 1ps

module uart_top_tb();
    reg clk, reset, read_uart, write_uart, rx;
    reg [7:0] write_data;
    wire rx_full, rx_empty, tx;
    wire [7:0] read_data;

    // 50MHz Clock (20ns period)
    always #10 clk = ~clk;

    // Instantiate your Top Module
    uart_top #(
        .BR_LIMIT(27),     // 115200 baud @ 50MHz
        .FIFO_EXP(7)       // 128-byte buffer
    ) dut (
        .clk_50MHz(clk), .reset(reset), .read_uart(read_uart),
        .write_uart(write_uart), .rx(rx), .write_data(write_data),
        .rx_full(rx_full), .rx_empty(rx_empty), .tx(tx), .read_data(read_data)
    );

    // GTKWave Setup: Generate the .vcd file
    initial begin
        $dumpfile("uart_sim.vcd"); // Name of the file for GTKWave
        $dumpvars(0, uart_top_tb);   // Dump all signals in the testbench
    end

    // Bit period for 115200 baud = 1/115200 = 8.68us = 8680ns
    task send_byte(input [7:0] data);
        integer i;
        begin
            rx = 0; // Start bit
            #(8680);
            for (i=0; i<8; i=i+1) begin
                rx = data[i]; // Send LSB first
                #(8680);
            end
            rx = 1; // Stop bit
            #(8680);
        end
    endtask

    initial begin
        // Initialize
        clk = 0; reset = 1; rx = 1; 
        read_uart = 0; write_uart = 0; write_data = 0;
        
        #100 reset = 0; // Release reset
        #200;

        // Send a 4-byte Landmark Packet (X=0x1234, Y=0x5678)
        send_byte(8'hAA); // Header
        send_byte(8'h12); // X High
        send_byte(8'h34); // X Low
        send_byte(8'h56); // Y High
        send_byte(8'h78); // Y Low

        // Simulate the Gesture Recognizer sending a "Result" (e.g., 0x01 for Palm)
        #100000;             // Wait until RX is done
        write_data = 8'h01;  // Put '01' on the TX bus
        write_uart = 1;      // Pulse the "Write" signal to TX FIFO
        #20 write_uart = 0;

#1000000;            // Wait a long time to see the 'tx' wire toggle bit-by-bit     
        
        // Pulse read_uart to see data coming out of FIFO
        repeat(5) begin
            #100 read_uart = 1;
            #20 write_uart = 0; // Pulse duration
            read_uart = 0;
            #500;
        end

        $display("Simulation Finished");
        $finish;
    end
endmodule