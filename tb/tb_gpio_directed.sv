// =============================================================================
// tb_gpio_directed.sv
// Directed Testbench for GPIO Subsystem
//
// Tests (in order):
//   Test 1 — Basic write and read back (DATA_OUT, DIR)
//   Test 2 — Direction register reflected on gpio_oe
//   Test 3 — Pin input read via DATA_IN
//   Test 4 — Rising edge interrupt, clear via INT_STATUS w1c
//
// Clock: 10ns period (100MHz)
// Reset: active low, held for 5 cycles
// =============================================================================

`timescale 1ns/1ps

module tb_gpio_directed;

    // =========================================================================
    // Parameters
    // =========================================================================

    localparam CLK_PERIOD = 10;  // 10ns = 100MHz

    // Register offsets (matches gpio.sv)
    localparam logic [31:0] ADDR_DATA_OUT   = 32'h00;
    localparam logic [31:0] ADDR_DATA_IN    = 32'h04;
    localparam logic [31:0] ADDR_DIR        = 32'h08;
    localparam logic [31:0] ADDR_INT_EN     = 32'h0C;
    localparam logic [31:0] ADDR_INT_STATUS = 32'h10;
    localparam logic [31:0] ADDR_INT_TYPE   = 32'h14;
    localparam logic [31:0] ADDR_INT_POL    = 32'h18;

    // =========================================================================
    // Clock and reset
    // =========================================================================

    logic clk;
    logic rst_n;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // Interface instantiations
    // =========================================================================

    axi4lite_if axiif (.ACLK(clk), .ARESETn(rst_n));
    gpio_if     gpif  (.CLK(clk),  .RESETn(rst_n));

    // =========================================================================
    // DUT instantiation
    // =========================================================================

    logic irq;

    top dut (
        .axiif (axiif),
        .gpif  (gpif),
        .irq   (irq)
    );

    // =========================================================================
    // Test tracking
    // =========================================================================

    int pass_count = 0;
    int fail_count = 0;

    // =========================================================================
    // Task: AXI Write
    // Drives a single AXI4-Lite write transaction to the given address
    // =========================================================================

    task axi_write(input logic [31:0] addr, input logic [31:0] data);
        // drive write address channel
        @(posedge clk);
        axiif.AWVALID <= 1'b1;
        axiif.AWADDR  <= addr;
        axiif.WVALID  <= 1'b0;

        // wait for AWREADY
        @(posedge clk);
        while (!axiif.AWREADY) @(posedge clk);
        axiif.AWVALID <= 1'b0;

        // drive write data channel
        axiif.WVALID <= 1'b1;
        axiif.WDATA  <= data;
        axiif.WSTRB  <= 4'hF;  // all byte lanes valid

        // wait for WREADY
        while (!axiif.WREADY) @(posedge clk);
        @(posedge clk);
        axiif.WVALID <= 1'b0;

        // wait for BVALID
        axiif.BREADY <= 1'b1;
        while (!axiif.BVALID) @(posedge clk);
        @(posedge clk);
        axiif.BREADY <= 1'b0;
    endtask

    // =========================================================================
    // Task: AXI Read
    // Drives a single AXI4-Lite read transaction, returns data in rdata
    // =========================================================================

    task axi_read(input logic [31:0] addr, output logic [31:0] rdata);
        // drive read address channel
        @(posedge clk);
        axiif.ARVALID <= 1'b1;
        axiif.ARADDR  <= addr;

        // wait for ARREADY
        while (!axiif.ARREADY) @(posedge clk);
        @(posedge clk);
        axiif.ARVALID <= 1'b0;

        // wait for RVALID
        axiif.RREADY <= 1'b1;
        while (!axiif.RVALID) @(posedge clk);
        rdata = axiif.RDATA;
        @(posedge clk);
        axiif.RREADY <= 1'b0;
    endtask

    // =========================================================================
    // Task: Check
    // Compares actual vs expected, prints PASS or FAIL
    // =========================================================================

    task check(
        input string       test_name,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
        if (actual === expected) begin
            $display("PASS | %s | got 0x%08h", test_name, actual);
            pass_count++;
        end
        else begin
            $display("FAIL | %s | expected 0x%08h got 0x%08h",
                     test_name, expected, actual);
            fail_count++;
        end
    endtask

    // =========================================================================
    // Task: Wait N cycles
    // =========================================================================

    task wait_cycles(input int n);
        repeat(n) @(posedge clk);
    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================

    logic [31:0] rdata;

    initial begin
        // -----------------------------------------------------------------------
        // Initialise AXI master signals
        // -----------------------------------------------------------------------
        axiif.AWVALID <= 1'b0;
        axiif.AWADDR  <= 32'h0;
        axiif.WVALID  <= 1'b0;
        axiif.WDATA   <= 32'h0;
        axiif.WSTRB   <= 4'h0;
        axiif.BREADY  <= 1'b0;
        axiif.ARVALID <= 1'b0;
        axiif.ARADDR  <= 32'h0;
        axiif.RREADY  <= 1'b0;

        // Initialise GPIO pin inputs
        gpif.gpio_in <= 32'h0;

        // -----------------------------------------------------------------------
        // Reset — hold for 5 cycles
        // -----------------------------------------------------------------------
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        @(posedge clk);
        rst_n = 1'b1;
        wait_cycles(2);

        $display("------------------------------------------------------");
        $display("GPIO Directed Testbench Starting");
        $display("------------------------------------------------------");

        // =====================================================================
        // Test 1 — Basic write and read back
        // Write 0xDEADBEEF to DATA_OUT, read it back
        // =====================================================================
        $display("\n--- Test 1: DATA_OUT write and read back ---");

        axi_write(ADDR_DATA_OUT, 32'hDEADBEEF);
        wait_cycles(2);
        axi_read(ADDR_DATA_OUT, rdata);
        check("DATA_OUT read back", rdata, 32'hDEADBEEF);

        // check gpio_out reflects written value
        wait_cycles(1);
        check("gpio_out reflects DATA_OUT", gpif.gpio_out, 32'hDEADBEEF);

        // =====================================================================
        // Test 2 — Direction register reflected on gpio_oe
        // Write 0xFF to DIR, check gpio_oe matches
        // =====================================================================
        $display("\n--- Test 2: DIR register and gpio_oe ---");

        axi_write(ADDR_DIR, 32'h000000FF);  // lower 8 pins as outputs
        wait_cycles(1);
        axi_read(ADDR_DIR, rdata);
        check("DIR read back", rdata, 32'h000000FF);
        check("gpio_oe reflects DIR", gpif.gpio_oe, 32'h000000FF);

        // change to all outputs
        axi_write(ADDR_DIR, 32'hFFFFFFFF);
        wait_cycles(1);
        check("gpio_oe all outputs", gpif.gpio_oe, 32'hFFFFFFFF);

        // back to all inputs
        axi_write(ADDR_DIR, 32'h00000000);
        wait_cycles(1);
        check("gpio_oe all inputs", gpif.gpio_oe, 32'h00000000);

        // =====================================================================
        // Test 3 — Pin input read via DATA_IN
        // Drive gpio_in from TB, read DATA_IN over AXI
        // =====================================================================
        $display("\n--- Test 3: DATA_IN live pin read ---");

        // DIR already 0 (all inputs) from test 2
        gpif.gpio_in <= 32'hA5A5A5A5;
        wait_cycles(3);  // allow two synchroniser stages + margin
        axi_read(ADDR_DATA_IN, rdata);
        check("DATA_IN reads gpio_in", rdata, 32'hA5A5A5A5);

        // change pin value
        gpif.gpio_in <= 32'h12345678;
        wait_cycles(3);
        axi_read(ADDR_DATA_IN, rdata);
        check("DATA_IN updates with pin", rdata, 32'h12345678);

        // back to zero
        gpif.gpio_in <= 32'h0;
        wait_cycles(3);
        axi_read(ADDR_DATA_IN, rdata);
        check("DATA_IN returns 0", rdata, 32'h0);

        // =====================================================================
        // Test 4 — Rising edge interrupt on pin 3
        // Configure: pin 3 input, edge triggered, rising, enabled
        // Drive pin 3 high, check IRQ asserts
        // Clear INT_STATUS, check IRQ deasserts
        // =====================================================================
        $display("\n--- Test 4: Rising edge interrupt ---");

        // configure DIR — all inputs (already 0, set explicitly)
        axi_write(ADDR_DIR, 32'h00000000);

        // configure interrupt registers for pin 3
        axi_write(ADDR_INT_TYPE, 32'h00000008);  // pin 3 = edge triggered
        axi_write(ADDR_INT_POL,  32'h00000008);  // pin 3 = rising edge
        axi_write(ADDR_INT_EN,   32'h00000008);  // pin 3 interrupt enabled
        wait_cycles(2);

        // verify IRQ is low before trigger
        check("IRQ low before trigger", {31'h0, irq}, 32'h0);

        // drive pin 3 high — rising edge
        gpif.gpio_in <= 32'h00000008;
        wait_cycles(3);  // synchroniser + edge detect

        // check IRQ asserted
        check("IRQ high after rising edge", {31'h0, irq}, 32'h1);

        // check INT_STATUS shows pin 3
        axi_read(ADDR_INT_STATUS, rdata);
        check("INT_STATUS pin 3 set", rdata, 32'h00000008);

        // clear INT_STATUS via w1c — write 1 to bit 3
        axi_write(ADDR_INT_STATUS, 32'h00000008);
        wait_cycles(2);

        // check IRQ deasserted
        check("IRQ low after clear", {31'h0, irq}, 32'h0);

        // check INT_STATUS cleared
        axi_read(ADDR_INT_STATUS, rdata);
        check("INT_STATUS cleared", rdata, 32'h0);

        // verify no re-trigger — pin is still high but edge already detected
        wait_cycles(5);
        check("IRQ stays low, no re-trigger", {31'h0, irq}, 32'h0);

        // drive pin low then high again — new rising edge
        gpif.gpio_in <= 32'h0;
        wait_cycles(3);
        gpif.gpio_in <= 32'h00000008;
        wait_cycles(3);
        check("IRQ fires on second rising edge", {31'h0, irq}, 32'h1);

        // clean up
        axi_write(ADDR_INT_STATUS, 32'h00000008);
        wait_cycles(2);

        // =====================================================================
        // Results
        // =====================================================================
        $display("\n------------------------------------------------------");
        $display("Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("------------------------------------------------------");

        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED — check waveforms");

        $finish;
    end

    // =========================================================================
    // Timeout watchdog — kill simulation if it hangs
    // =========================================================================

    initial begin
        #100000;
        $display("TIMEOUT — simulation hung, check AXI handshake");
        $finish;
    end

    // =========================================================================
    // Waveform dump
    // =========================================================================

    initial begin
        $dumpfile("gpio_tb.vcd");
        $dumpvars(0, tb_gpio_directed);
    end

endmodule