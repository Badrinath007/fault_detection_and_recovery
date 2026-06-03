module axi_lite_slave #(
    parameter ADDR_WIDTH = 6,
    parameter DATA_WIDTH = 32
)(
    input  wire clk,
    input  wire rst_n,

    input  wire [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire                  s_axi_awvalid,
    output reg                   s_axi_awready,

    input  wire [DATA_WIDTH-1:0] s_axi_wdata,
    input  wire                  s_axi_wvalid,
    output reg                   s_axi_wready,

    output reg [1:0]             s_axi_bresp,
    output reg                   s_axi_bvalid,
    input  wire                  s_axi_bready,

    input  wire [ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire                  s_axi_arvalid,
    output reg                   s_axi_arready,

    output reg [DATA_WIDTH-1:0]  s_axi_rdata,
    output reg [1:0]             s_axi_rresp,
    output reg                   s_axi_rvalid,
    input  wire                  s_axi_rready,

    input  wire                  fault_detected,
    input  wire                  safe_mode,
    input  wire [1:0]            fault_code,
    input  wire [7:0]            log_count,

    output reg                   clear_fault,
    output reg                   clear_logs,
    output reg [7:0]             timeout_cfg,
    output reg [7:0]             retry_cfg
);

localparam STATUS_REG_ADDR      = 6'h00;
localparam FAULT_CODE_REG_ADDR  = 6'h04;
localparam LOG_COUNT_REG_ADDR   = 6'h08;
localparam CONTROL_REG_ADDR     = 6'h0C;
localparam TIMEOUT_CFG_ADDR     = 6'h10;
localparam RETRY_CFG_ADDR       = 6'h14;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        s_axi_awready <= 0;
        s_axi_wready  <= 0;
        s_axi_bvalid  <= 0;
        s_axi_bresp   <= 0;

        timeout_cfg <= 8'd8;
        retry_cfg   <= 8'd3;

        clear_fault <= 0;
        clear_logs <= 0;

    end else begin

        s_axi_awready <= 0;
        s_axi_wready <= 0;

        clear_fault <= 0;
        clear_logs <= 0;

        if(s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid) begin

            s_axi_awready <= 1;
            s_axi_wready <= 1;

            case(s_axi_awaddr)

                CONTROL_REG_ADDR: begin
                    clear_fault <= s_axi_wdata[0];
                    clear_logs  <= s_axi_wdata[1];
                end

                TIMEOUT_CFG_ADDR:
                    timeout_cfg <= s_axi_wdata[7:0];

                RETRY_CFG_ADDR:
                    retry_cfg <= s_axi_wdata[7:0];

            endcase

            s_axi_bvalid <= 1;
            s_axi_bresp <= 2'b00;

        end

        if(s_axi_bvalid && s_axi_bready)
            s_axi_bvalid <= 0;

    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        s_axi_arready <= 0;
        s_axi_rvalid <= 0;
        s_axi_rresp <= 0;
        s_axi_rdata <= 0;
    end else begin

        s_axi_arready <= 0;

        if(s_axi_arvalid && !s_axi_rvalid) begin

            s_axi_arready <= 1;
            s_axi_rvalid <= 1;
            s_axi_rresp <= 2'b00;

            case(s_axi_araddr)

                STATUS_REG_ADDR:
                    s_axi_rdata <= {30'b0, safe_mode, fault_detected};

                FAULT_CODE_REG_ADDR:
                    s_axi_rdata <= {30'b0, fault_code};

                LOG_COUNT_REG_ADDR:
                    s_axi_rdata <= {24'b0, log_count};

                TIMEOUT_CFG_ADDR:
                    s_axi_rdata <= {24'b0, timeout_cfg};

                RETRY_CFG_ADDR:
                    s_axi_rdata <= {24'b0, retry_cfg};

                default:
                    s_axi_rdata <= 32'hDEADBEEF;

            endcase
        end

        if(s_axi_rvalid && s_axi_rready)
            s_axi_rvalid <= 0;

    end
end

endmodule
