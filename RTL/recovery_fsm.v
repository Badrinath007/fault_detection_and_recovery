
module recovery_fsm #(
    parameter ACK_TIMEOUT   = 8,
    parameter COUNTER_WIDTH = 8
)(
    input  wire clk,
    input  wire rst_n,
    input  wire fault_detected,
    input  wire recover_ack,
    input  wire [7:0] retry_cfg,
    output reg  recovery_req,
    output reg  safe_mode,
    output reg  fault_clear
);

localparam IDLE           = 3'd0;
localparam MONITOR        = 3'd1;
localparam RECOVERY_START = 3'd2;
localparam WAIT_ACK       = 3'd3;
localparam SAFE_MODE      = 3'd4;

reg [2:0] current_state, next_state;
reg [COUNTER_WIDTH-1:0] retry_counter;
reg [COUNTER_WIDTH-1:0] ack_timeout_counter;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        current_state <= IDLE;
    else
        current_state <= next_state;
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        retry_counter <= 0;
        ack_timeout_counter <= 0;
    end else begin
        if(current_state == WAIT_ACK) begin

            if(recover_ack) begin
                retry_counter <= 0;
                ack_timeout_counter <= 0;
            end else begin
                ack_timeout_counter <= ack_timeout_counter + 1'b1;

                if(ack_timeout_counter >= ACK_TIMEOUT) begin
                    ack_timeout_counter <= 0;

                    if(retry_counter < retry_cfg)
                        retry_counter <= retry_counter + 1'b1;
                end
            end

        end else begin
            ack_timeout_counter <= 0;
        end
    end
end

always @(*) begin
    next_state = current_state;

    case(current_state)

        IDLE:
            next_state = MONITOR;

        MONITOR:
            if(fault_detected)
                next_state = RECOVERY_START;

        RECOVERY_START:
            next_state = WAIT_ACK;

        WAIT_ACK: begin
            if(recover_ack)
                next_state = MONITOR;
            else if(retry_counter >= retry_cfg)
                next_state = SAFE_MODE;
            else if(ack_timeout_counter >= ACK_TIMEOUT)
                next_state = RECOVERY_START;
        end

        SAFE_MODE:
            next_state = SAFE_MODE;

        default:
            next_state = IDLE;

    endcase
end

always @(*) begin
    recovery_req = 0;
    safe_mode = 0;
    fault_clear = 0;

    case(current_state)

        RECOVERY_START:
            recovery_req = 1;

        WAIT_ACK:
            if(recover_ack)
                fault_clear = 1;

        SAFE_MODE:
            safe_mode = 1;

    endcase
end

endmodule
