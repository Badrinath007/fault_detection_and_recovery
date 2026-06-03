
module fault_monitor #(
    parameter NUM_MODULES   = 4,
    parameter COUNTER_WIDTH = 8
)(
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire [NUM_MODULES-1:0]      heartbeat,
    input  wire [NUM_MODULES-1:0]      error_flag,
    input  wire [7:0]                  timeout_cfg,
    input  wire                        fault_clear,
    output reg                         fault_detected,
    output reg [1:0]                   fault_code
);

reg [COUNTER_WIDTH-1:0] heartbeat_counter [0:NUM_MODULES-1];
integer i;

// Inside fault_monitor.v
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fault_detected <= 0;
        fault_code <= 0;
        for(i=0; i<NUM_MODULES; i=i+1)
            heartbeat_counter[i] <= 0;
    end else begin
        if (fault_clear) begin
            // Explicitly flush and reset the health monitors upon clear command
            fault_detected <= 0;
            fault_code     <= 0;
            for(i=0; i<NUM_MODULES; i=i+1) begin
                heartbeat_counter[i] <= 0;
            end
        end else begin
            // Normal monitoring routine logic
            fault_detected <= 0;
            
            for(i=0; i<NUM_MODULES; i=i+1) begin
                if(heartbeat[i])
                    heartbeat_counter[i] <= 0;
                else
                    heartbeat_counter[i] <= heartbeat_counter[i] + 1'b1;

                if(heartbeat_counter[i] >= timeout_cfg) begin
                    fault_detected <= 1;
                    fault_code     <= 2'b01; // Heartbeat fault
                end
                
                if(error_flag[i]) begin
                    fault_detected <= 1;
                    fault_code     <= 2'b10; // Hardware Error flag fault
                end
            end
        end
    end
end

endmodule
