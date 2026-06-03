module fault_logger #(
    parameter LOG_DEPTH       = 16,
    parameter TIMESTAMP_WIDTH = 16,
    parameter MODULE_ID_WIDTH = 2
)(
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       clear_logs,
    input  wire                       fault_detected,
    input  wire [1:0]                 fault_code,
    input  wire [MODULE_ID_WIDTH-1:0] module_id,
    output reg                        log_valid,
    output reg [7:0]                  log_count
);

localparam LOG_INDEX_WIDTH = 4;

reg [TIMESTAMP_WIDTH-1:0] timestamp_counter;
reg [TIMESTAMP_WIDTH-1:0] log_timestamp [0:LOG_DEPTH-1];
reg [MODULE_ID_WIDTH-1:0] log_module_id [0:LOG_DEPTH-1];
reg [1:0]                 log_fault_code [0:LOG_DEPTH-1];

reg [LOG_INDEX_WIDTH-1:0] write_pointer;
reg fault_detected_d1;

integer i;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        timestamp_counter <= 0;
    else
        timestamp_counter <= timestamp_counter + 1'b1;
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin

		  fault_detected_d1 <= 0;
        write_pointer <= 0;
        log_count <= 0;
        log_valid <= 0;

        for(i=0;i<LOG_DEPTH;i=i+1) begin
            log_timestamp[i] <= 0;
            log_module_id[i] <= 0;
            log_fault_code[i] <= 0;
        end

    end 
	 else begin

		  if (clear_logs) begin
            log_count <= 0;
            write_pointer <= 0;
        end else if (fault_detected && !fault_detected_d1) begin
            // Triggered ONLY on the initial assertion edge!
            log_timestamp[write_pointer]  <= timestamp_counter;
            log_module_id[write_pointer]  <= module_id;
            log_fault_code[write_pointer] <= fault_code;
            
            write_pointer <= write_pointer + 1'b1;
            log_valid     <= 1;
            
            if (log_count < LOG_DEPTH)
                log_count <= log_count + 1'b1;
        end
    end
end

endmodule
