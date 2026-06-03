`timescale 1ns/1ps

module tb_fdrc_top;

    // ==========================================
    // Signal Declarations
    // ==========================================
    reg clk;
    reg rst_n;

    reg [3:0] heartbeat;
    reg [3:0] error_flag;
    reg       recover_ack;

    // AXI-Lite Write Channels
    reg [5:0]  s_axi_awaddr;
    reg        s_axi_awvalid;
    wire       s_axi_awready;

    reg [31:0] s_axi_wdata;
    reg        s_axi_wvalid;
    wire       s_axi_wready;

    wire [1:0] s_axi_bresp;
    wire       s_axi_bvalid;
    reg        s_axi_bready;

    // AXI-Lite Read Channels
    reg [5:0]  s_axi_araddr;
    reg        s_axi_arvalid;
    wire       s_axi_arready;

    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;

    // Outputs from DUT
    wire safe_mode;

    // Register Address Map Constants
    localparam STATUS_REG_ADDR     = 6'h00;
    localparam FAULT_CODE_REG_ADDR = 6'h04;
    localparam LOG_COUNT_REG_ADDR  = 6'h08;
    localparam CONTROL_REG_ADDR    = 6'h0C;
    localparam TIMEOUT_CFG_ADDR    = 6'h10;
    localparam RETRY_CFG_ADDR      = 6'h14;

    // ==========================================
    // Device Under Test (DUT) Instantiation
    // ==========================================
    fdrc_top dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .heartbeat     (heartbeat),
        .error_flag    (error_flag),
        .recover_ack   (recover_ack),
        .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),
        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),
        .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),
        .s_axi_bready  (s_axi_bready),
        .s_axi_araddr  (s_axi_araddr),
        .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),
        .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready  (s_axi_rready),
        .safe_mode     (safe_mode)
    );

    // ==========================================
    // Clock Generation (100MHz)
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ==========================================
    // AUTOMATIC TERMINAL LOGGER (Event-Driven)
    // ==========================================
    // This block triggers and prints to your console immediately 
    // whenever key internal simulation flags change state.
    
    wire internal_fault_det = dut.fault_detected;
    wire [1:0] internal_code = dut.fault_code;
    wire [7:0] internal_log_cnt = dut.log_count;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            // Silent during reset
        end else begin
            // Log when a fault is newly detected or cleared
            if (internal_fault_det) begin
                $display("[CORE LOG] @ %0t ns -> !! FAULT DETECTED !! Code: 2'b%b (01=HB Timeout, 10=HW Flag)", $time/1000, internal_code);
            end
            
            // Log if the FSM pushes the system into Safe Mode lockdown
            if (safe_mode) begin
                $display("[CRITICAL LOG] @ %0t ns -> !!! SYSTEM IN SAFE MODE LOCKDOWN !!!", $time/1000);
            end
        end
    end

    // Trace whenever write operations clear down through AXI
    always @(posedge clk) begin
        if (s_axi_awvalid && s_axi_awready) begin
            $display("[AXI WRITE BUS] @ %0t ns -> Address: 6'h%h, Data Written: 32'h%h", $time/1000, s_axi_awaddr, s_axi_wdata);
        end
        if (s_axi_arvalid && s_axi_arready) begin
            $display("[AXI READ BUS] @ %0t ns -> Address: 6'h%h", $time/1000, s_axi_araddr);
        end
    end


    // ==========================================
    // AXI-Lite Driver Tasks
    // ==========================================
    task axi_write;
        input [5:0]  addr;
        input [31:0] data;
        begin
            @(posedge clk);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1;
            s_axi_wdata   <= data;
            s_axi_wvalid  <= 1;
            s_axi_bready  <= 1;

            wait(s_axi_bvalid && s_axi_bready);

            @(posedge clk);
            s_axi_awvalid <= 0;
            s_axi_wvalid  <= 0;
            s_axi_bready  <= 0;
        end
    endtask

    task axi_read;
        input  [5:0]  addr;
        output [31:0] data;
        begin
            @(posedge clk);
            s_axi_araddr  <= addr;
            s_axi_arvalid <= 1;
            s_axi_rready  <= 1;

            wait(s_axi_rvalid && s_axi_rready);

            @(posedge clk);
            data          = s_axi_rdata;
            s_axi_arvalid <= 0;
            s_axi_rready  <= 0;
            $display("[AXI READ RESULT] @ %0t ns -> Address 6'h%h returned Data: 32'h%h", $time/1000, addr, data);
        end
    endtask

    // ==========================================
    // Test Scenario Sequence
    // ==========================================
    reg [31:0] rdata_buffer;

    initial begin
        $display("\n=======================================================");
        $display("STARTING FAULT DETECTION & RECOVERY TOP SIMULATION");
        $display("=======================================================\n");

        // --- 1. Initialization & Reset ---
        rst_n       = 0;
        heartbeat   = 4'b1111;
        error_flag  = 0;
        recover_ack = 0;
        
        s_axi_awaddr  = 0; s_axi_awvalid = 0; s_axi_wdata = 0; s_axi_wvalid = 0; s_axi_bready = 0;
        s_axi_araddr  = 0; s_axi_arvalid = 0; s_axi_rready = 0;

        #40;
        rst_n = 1;
        $display("[TB CONTROL] @ %0t ns -> System Reset Released.", $time/1000);

        // --- 2. Register Configuration ---
        // Setup Timeout configurations (Setting heartbeat timeout checks low for speed)
        axi_write(TIMEOUT_CFG_ADDR, 32'd5);
        axi_write(RETRY_CFG_ADDR, 32'd2);

        #50;

        // --- 3. Scenario A: Basic Heartbeat Drop ---
        $display("\n--- [SCENARIO A]: Inducing Heartbeat Fault on Channel 0 ---");
        heartbeat[0] = 0; 
        
        // Wait to allow the timeout counters to hit 5 and register the error
        #100; 
        
        // Read status registers to confirm core logged it
        axi_read(STATUS_REG_ADDR, rdata_buffer);
        axi_read(FAULT_CODE_REG_ADDR, rdata_buffer);
        axi_read(LOG_COUNT_REG_ADDR, rdata_buffer);

        // Clear the fault condition
        $display("[TB CONTROL] Sending recover acknowledgement pulse.");
        recover_ack = 1;
        #20;
        recover_ack = 0;
        heartbeat[0] = 1; // Restore channel sanity

        #100;

        // --- 4. Scenario B: Edge Case - Unresponsive Host (Timeout Escalation) ---
        $display("\n--- [SCENARIO B]: Edge Case - Unresponsive Recovery (Escalate to Safe Mode) ---");
        $display("[TB CONTROL] Dropping Heartbeat on Channel 2...");
        heartbeat[2] = 0; 

        // Withhold recovery completely. The FSM should retry up to 2 times, then trip into SAFE_MODE.
        $display("[TB CONTROL] Withholding recover_ack intentionally to force timeout thresholds...");
        #400; 

        // Check if SAFE_MODE register and output became high
        axi_read(STATUS_REG_ADDR, rdata_buffer);
        
        if (safe_mode) begin
            $display("\n[STATUS] TEST PASSED: System transitioned safely to Lockdown mode.");
        end else begin
            $display("\n[STATUS] TEST FAILED: System bypassed timeout escalation loops.");
        end

        #50;
        $display("\n=======================================================");
        $display("SIMULATION COMPLETE");
        $display("=======================================================\n");
        $finish;
    end

endmodule