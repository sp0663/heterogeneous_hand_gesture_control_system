module coord_assembler (
    input  clk,
    input  rst,
    
    // Interface to FIFO
    input  [7:0] fifo_data,
    input  fifo_empty,
    output reg fifo_rd_en,
    
    // Interface to Landmark Storage
    output reg [15:0] x_out,
    output reg [15:0] y_out,
    output reg [4:0]  landmark_id,
    output reg        valid_out
);

    reg [2:0] state, next_state;
    reg [4:0] id_count;
    reg [15:0] x_next, y_next;

    // State definitions
    localparam IDLE   = 3'd0,
               GET_XH = 3'd1,
               GET_XL = 3'd2,
               GET_YH = 3'd3,
               GET_YL = 3'd4;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            fifo_rd_en <= 0;
            valid_out <= 0;
            id_count <= 0;
            landmark_id <= 0;
            x_out <= 0;
            y_out <= 0;
        end else begin
            valid_out <= 0; // Default pulse low
            fifo_rd_en <= 0;
            state <= next_state;
            x_out <= x_next;
            y_out <= y_next;
        end
    end
    always @ (*) begin
        x_next = x_out;
        y_next = y_out;
        next_state = state;
        case (state)
                IDLE: begin
                    if (!fifo_empty) begin
                        fifo_rd_en = 1;
                        next_state = GET_XH;
                    end
                end

                GET_XH: begin
                    x_next[15:8] = fifo_data;
                    if (!fifo_empty) begin
                        fifo_rd_en = 1;
                        next_state = GET_XL;
                    end
                end

                GET_XL: begin
                    x_next[7:0] = fifo_data;
                    if (!fifo_empty) begin
                        fifo_rd_en = 1;
                        next_state = GET_YH;
                    end
                end

                GET_YH: begin
                    y_next[15:8] = fifo_data;
                    if (!fifo_empty) begin
                        fifo_rd_en = 1;
                        next_state = GET_YL;
                    end
                end

                GET_YL: begin
                    y_next[7:0] = fifo_data;
                    next_state = IDLE;
                end
            endcase
    end
    always @ (posedge clk) begin
        // Increment ID for next landmark
        if (state == GET_YH) begin
                if (id_count == 20)
                    id_count <= 0;
                else
                    id_count <= id_count + 1;
                landmark_id <= id_count;
                valid_out <= 1; // Coordinate complete!
        end
    end


endmodule