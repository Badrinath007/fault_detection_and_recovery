
module fdrc_top(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [3:0]  heartbeat,
    input  wire [3:0]  error_flag,
    input  wire        recover_ack,

    input  wire [5:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,

    input  wire [31:0] s_axi_wdata,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,

    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,

    input  wire [5:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,

    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,

    output wire        safe_mode
);

wire fault_detected;
wire [1:0] fault_code;
wire recovery_req;
wire fault_clear;
wire log_valid;
wire [7:0] log_count;
wire clear_fault;
wire clear_logs;
wire [7:0] timeout_cfg;
wire [7:0] retry_cfg;

fault_monitor u_fault_monitor(
    .clk(clk),
    .rst_n(rst_n),
    .heartbeat(heartbeat),
    .error_flag(error_flag),
    .timeout_cfg(timeout_cfg),
    .fault_clear(clear_fault | fault_clear),
    .fault_detected(fault_detected),
    .fault_code(fault_code)
);

recovery_fsm u_recovery_fsm(
    .clk(clk),
    .rst_n(rst_n),
    .fault_detected(fault_detected),
    .recover_ack(recover_ack),
    .retry_cfg(retry_cfg),
    .recovery_req(recovery_req),
    .safe_mode(safe_mode),
    .fault_clear(fault_clear)
);

fault_logger u_fault_logger(
    .clk(clk),
    .rst_n(rst_n),
    .clear_logs(clear_logs),
    .fault_detected(fault_detected),
    .fault_code(fault_code),
    .module_id(2'b00),
    .log_valid(log_valid),
    .log_count(log_count)
);

axi_lite_slave u_axi(
    .clk(clk),
    .rst_n(rst_n),

    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),

    .s_axi_wdata(s_axi_wdata),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),

    .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),

    .s_axi_araddr(s_axi_araddr),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),

    .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready),

    .fault_detected(fault_detected),
    .safe_mode(safe_mode),
    .fault_code(fault_code),
    .log_count(log_count),

    .clear_fault(clear_fault),
    .clear_logs(clear_logs),

    .timeout_cfg(timeout_cfg),
    .retry_cfg(retry_cfg)
);

endmodule
