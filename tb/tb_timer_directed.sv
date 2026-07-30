// =============================================================================
// tb_timer_directed.sv
// Directed Testbench for Timer Peripheral via AXI4-Lite Subsystem
//
// DUT: top.sv (axi4lite_wrapper + address_decoder + gpio + timer)
// Timer base address: 0x100 (per address_decoder)
//
// Tests (in order):
//   Test 1 — LOAD and CONTROL register write/read back
//   Test 2 — One-shot: fires once, hardware clears enable, stops
//   Test 3 — Auto-reload: three consecutive periods, verify period length
//   Test 4 — LOAD=0 corner case: overflow on very first tick
//   Test 5 — IRQ gating: overflow with irq_en=0, IRQ must stay low
//   Test 6 — w1c STATUS clear mid-run, re-trigger on next overflow
//   Test 7 — Prescaler: LOAD=3 PRESCALAR=4, verify 20-cycle period
//   Test 8 — LOAD write mid-count: new value takes effect only on reload
//
// Clock: 10ns period (100MHz)
// Reset: active low, held for 5 cycles
// =============================================================================

`timescale 1ns/1ps

module tb_timer_directed;

    // =========================================================================
    // Parameters
    // =========================================================================

    localparam CLK_PERIOD = 10;  // 10ns = 100MHz

    // Timer base address
    localparam logic [31:0] TIMER_BASE = 32'h100;

    // Register offsets
    localparam logic [31:0] OFF_LOAD      = 32'h00;
    localparam logic [31:0] OFF_COUNT     = 32'h04;
    localparam logic [31:0] OFF_CONTROL   = 32'h08;
    localparam logic [31:0] OFF_STATUS    = 32'h0C;
    localparam logic [31:0] OFF_PRESCALAR = 32'h10;

    // CTRL bit masks
    localparam logic [31:0] CTRL_ENABLE      = 32'h1;
    localparam logic [31:0] CTRL_AUTO_RELOAD = 32'h2;
    localparam logic [31:0] CTRL_IRQ_EN      = 32'h4;

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

    axi4lite_if axiif (.ACLK(clk),  .ARESETn(rst_n));
    gpio_if     gpif  (.CLK(clk),   .RESETn(rst_n));
    timer_if    tif   (.CLK(clk),   .RESETn(rst_n));

    // =========================================================================
    // DUT instantiation
    // =========================================================================

    logic irq;

    top dut (
        .axiif (axiif),
        .gpif  (gpif),
        .tif   (tif),
        .irq   (irq)
    );

    // =========================================================================
    // Test tracking
    // =========================================================================

    int pass_count = 0;
    int fail_count = 0;
    int test_num   = 0;

    // =========================================================================
    // Task: AXI Write — identical handshake to tb_gpio_directed
    // =========================================================================

    task axi_write(input logic [31:0] addr, input logic [31:0] data);
        @(posedge clk);
        axiif.AWVALID <= 1'b1;
        axiif.AWADDR  <= addr;
        axiif.WVALID  <= 1'b0;

        @(posedge clk);
        while (!axiif.AWREADY) @(posedge clk);
        axiif.AWVALID <= 1'b0;

        axiif.WVALID <= 1'b1;
        axiif.WDATA  <= data;
        axiif.WSTRB  <= 4'hF;

        while (!axiif.WREADY) @(posedge clk);
        @(posedge clk);
        axiif.WVALID <= 1'b0;

        axiif.BREADY <= 1'b1;
        while (!axiif.BVALID) @(posedge clk);
        @(posedge clk);
        axiif.BREADY <= 1'b0;
    endtask

    // =========================================================================
    // Task: AXI Read
    // =========================================================================

    task axi_read(input logic [31:0] addr, output logic [31:0] rdata);
        @(posedge clk);
        axiif.ARVALID <= 1'b1;
        axiif.ARADDR  <= addr;

        while (!axiif.ARREADY) @(posedge clk);
        @(posedge clk);
        axiif.ARVALID <= 1'b0;

        axiif.RREADY <= 1'b1;
        while (!axiif.RVALID) @(posedge clk);
        rdata = axiif.RDATA;
        @(posedge clk);
        axiif.RREADY <= 1'b0;
    endtask

    // =========================================================================
    // Task: Check
    // =========================================================================

    task check(
        input string       test_name,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
        if (actual === expected) begin
            $display("PASS | T%0d | %s | got 0x%08h", test_num, test_name, actual);
            pass_count++;
        end else begin
            $display("FAIL | T%0d | %s | expected 0x%08h  got 0x%08h",
                     test_num, test_name, expected, actual);
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
    // Task: Wait for IRQ, timeout after max_cycles
    // =========================================================================

    task wait_irq(input int max_cycles, output logic timed_out);
        timed_out = 1'b1;
        for (int i = 0; i < max_cycles; i++) begin
            @(posedge clk);
            if (irq) begin
                timed_out = 1'b0;
                return;
            end
        end
    endtask

    // =========================================================================
    // Helper: timer register full address
    // =========================================================================

    function automatic logic [31:0] TREG(input logic [31:0] offset);
        return TIMER_BASE + offset;
    endfunction

    // =========================================================================
    // Main test sequence
    // =========================================================================

    logic [31:0] rdata;
    logic        timed_out;
    longint      cycle_start;
    int          period_cycles;

    initial begin
        // Initialise AXI master signals
        axiif.AWVALID <= 1'b0;
        axiif.AWADDR  <= 32'h0;
        axiif.WVALID  <= 1'b0;
        axiif.WDATA   <= 32'h0;
        axiif.WSTRB   <= 4'h0;
        axiif.BREADY  <= 1'b0;
        axiif.ARVALID <= 1'b0;
        axiif.ARADDR  <= 32'h0;
        axiif.RREADY  <= 1'b0;

        gpif.gpio_in <= 32'h0;

        // Reset — 5 cycles active low
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        @(posedge clk);
        rst_n = 1'b1;
        wait_cycles(2);

        $display("------------------------------------------------------");
        $display("Timer Directed Testbench Starting");
        $display("Timer base address: 0x%03h", TIMER_BASE);
        $display("------------------------------------------------------");

        // =====================================================================
        // Test 1 — Register write and read back
        // Timer not running (enable=0). Verify LOAD, PRESCALAR, CONTROL
        // survive a write/read round trip. STATUS must be 0.
        // =====================================================================
        test_num = 1;
        $display("\n--- Test %0d: Register write and read back ---", test_num);

        axi_write(TREG(OFF_LOAD),      32'hABCD_1234);
        axi_write(TREG(OFF_PRESCALAR), 32'h0000_0009);
        axi_write(TREG(OFF_CONTROL),   32'h0000_0006); // auto_reload+irq_en, no enable

        axi_read(TREG(OFF_LOAD),      rdata);
        check("LOAD read back",      rdata, 32'hABCD_1234);

        axi_read(TREG(OFF_PRESCALAR), rdata);
        check("PRESCALAR read back", rdata, 32'h0000_0009);

        axi_read(TREG(OFF_CONTROL),   rdata);
        check("CONTROL read back",   rdata, 32'h0000_0006);

        axi_read(TREG(OFF_STATUS),    rdata);
        check("STATUS clear at rest", rdata, 32'h0);

        check("IRQ low before run",  {31'h0, irq}, 32'h0);

        axi_write(TREG(OFF_CONTROL), 32'h0);
        wait_cycles(2);

        // =====================================================================
        // Test 2 — One-shot: LOAD=10, no prescaler
        // Period = 11 ticks (10 down to 0, then overflow)
        // Hardware must auto-clear enable so timer stops
        // COUNT must read 0 after firing, must not restart
        // =====================================================================
        test_num = 2;
        $display("\n--- Test %0d: One-shot (LOAD=10) ---", test_num);

        axi_write(TREG(OFF_STATUS),   32'hFFFF_FFFF);
        axi_write(TREG(OFF_LOAD),     32'd10);
        axi_write(TREG(OFF_PRESCALAR),32'd0);
        axi_write(TREG(OFF_CONTROL),  CTRL_ENABLE | CTRL_IRQ_EN);

        wait_irq(50, timed_out);
        check("One-shot IRQ fires",       timed_out,       1'b0);
        check("IRQ line asserted",        {31'h0, irq},    32'h1);

        axi_read(TREG(OFF_STATUS),  rdata);
        check("STATUS[0] set",            rdata[0],        1'b1);

        axi_read(TREG(OFF_COUNT),   rdata);
        check("COUNT at 0",               rdata,           32'd0);

        axi_read(TREG(OFF_CONTROL), rdata);
        check("enable auto-cleared",      rdata[0],        1'b0);

        wait_cycles(5);
        axi_read(TREG(OFF_COUNT),   rdata);
        check("COUNT stays 0 (stopped)",  rdata,           32'd0);

        axi_write(TREG(OFF_STATUS), 32'h1);
        wait_cycles(1);
        check("IRQ deasserts after clear",{31'h0, irq},    32'h0);
        axi_read(TREG(OFF_STATUS),  rdata);
        check("STATUS cleared",           rdata[0],        1'b0);

        wait_cycles(3);

        // =====================================================================
        // Test 3 — Auto-reload: LOAD=5, measure 3 consecutive periods
        // Period = LOAD+1 = 6 ticks
        // =====================================================================
        test_num = 3;
        $display("\n--- Test %0d: Auto-reload period (LOAD=49) ---", test_num);

        axi_write(TREG(OFF_STATUS),   32'hFFFF_FFFF);
        axi_write(TREG(OFF_LOAD),     32'd49);        // 50-cycle period
        axi_write(TREG(OFF_PRESCALAR),32'd0);
        axi_write(TREG(OFF_CONTROL),  CTRL_ENABLE | CTRL_AUTO_RELOAD | CTRL_IRQ_EN);

        // Burn the first IRQ — partial period from wherever the enable write landed
        wait_irq(100, timed_out);
        axi_write(TREG(OFF_STATUS), 32'h1);
        wait_cycles(2);

        // Measure 3 clean IRQ-to-IRQ periods
        for (int p = 1; p <= 3; p++) begin
            wait_irq(100, timed_out);
            cycle_start = $time;                   // stamp when IRQ fires
            check($sformatf("Period %0d IRQ", p), timed_out, 1'b0);
            axi_write(TREG(OFF_STATUS), 32'h1);   // clear — timer has ~42 cycles left, no race

            wait_irq(100, timed_out);             // wait for the NEXT IRQ
            period_cycles = int'(($time - cycle_start) / CLK_PERIOD);
            $display("  INFO: Period %0d = %0d cycles (expected 50)", p, period_cycles);
            check($sformatf("Period %0d length", p), period_cycles, 32'd50);
            cycle_start = $time;                  // this IRQ becomes the start of next iteration
            axi_write(TREG(OFF_STATUS), 32'h1);
            wait_cycles(2);
        end
        axi_write(TREG(OFF_CONTROL),  CTRL_ENABLE | CTRL_IRQ_EN);
        wait_cycles(50);
        // =====================================================================
        // Test 4 — LOAD=0 corner case
        // COUNT starts at 0; first tick must immediately overflow.
        // If RTL decrements before checking it wraps to 0xFFFFFFFF (bug).
        // =====================================================================
        test_num = 4;
        $display("\n--- Test %0d: LOAD=0 corner case ---", test_num);

        axi_write(TREG(OFF_STATUS),   32'hFFFF_FFFF);
        axi_write(TREG(OFF_LOAD),     32'd0);
        axi_write(TREG(OFF_PRESCALAR),32'd0);
        axi_write(TREG(OFF_CONTROL),  CTRL_ENABLE | CTRL_IRQ_EN);

        wait_irq(10, timed_out);
        check("LOAD=0 IRQ fires fast",    timed_out,    1'b0);

        axi_read(TREG(OFF_STATUS), rdata);
        check("LOAD=0 STATUS[0] set",     rdata[0],     1'b1);

        axi_read(TREG(OFF_COUNT),  rdata);
        check("LOAD=0 COUNT=0 (no wrap)", rdata,        32'd0);

        axi_write(TREG(OFF_STATUS),  32'h1);
        axi_write(TREG(OFF_CONTROL), 32'h0);
        wait_cycles(3);

        // =====================================================================
        // Test 5 — IRQ gating: overflow with irq_en=0
        // STATUS[0] must set (software can poll), IRQ line must stay low
        // =====================================================================
        test_num = 5;
        $display("\n--- Test %0d: IRQ gating (irq_en=0) ---", test_num);

        axi_write(TREG(OFF_STATUS),   32'hFFFF_FFFF);
        axi_write(TREG(OFF_LOAD),     32'd5);
        axi_write(TREG(OFF_PRESCALAR),32'd0);
        axi_write(TREG(OFF_CONTROL),  CTRL_ENABLE); // no IRQ_EN

        wait_cycles(20);

        axi_read(TREG(OFF_STATUS), rdata);
        check("STATUS[0] set without irq_en", rdata[0],     1'b1);
        check("IRQ line stays low",           {31'h0, irq}, 32'h0);

        axi_write(TREG(OFF_CONTROL), 32'h0);
        axi_write(TREG(OFF_STATUS),  32'h1);
        wait_cycles(3);

        // =====================================================================
        // Test 6 — w1c clear mid-run, re-trigger
        // Auto-reload running. Clear STATUS while counting.
        // IRQ must deassert then fire again on the next overflow.
        // =====================================================================
        test_num = 6;
        $display($time);
        $display("\n--- Test %0d: w1c clear mid-run, re-trigger ---", test_num);

        axi_write(TREG(OFF_STATUS),   32'hFFFF_FFFF);
        axi_write(TREG(OFF_LOAD),     32'd15);
        axi_write(TREG(OFF_PRESCALAR),32'd0);
        axi_write(TREG(OFF_CONTROL),  CTRL_ENABLE | CTRL_AUTO_RELOAD | CTRL_IRQ_EN);

        wait_irq(50, timed_out);
        $display($time);
        check("First IRQ fires",           timed_out,    1'b0);
        check("IRQ high",                  {31'h0, irq}, 32'h1);

        axi_write(TREG(OFF_STATUS), 32'h1); // clear while running
        wait_cycles(1);
        $display($time);

        check("IRQ deasserts after clear", {31'h0, irq}, 32'h0);

        wait_irq(50, timed_out);
        check("Second IRQ fires",          timed_out,    1'b0);
        check("IRQ high again",            {31'h0, irq}, 32'h1);

        axi_write(TREG(OFF_CONTROL), 32'h0);
        axi_write(TREG(OFF_STATUS),  32'h1);
        wait_cycles(3);

        // =====================================================================
        // Test 7 — Prescaler: LOAD=3, PRESCALAR=4
        // Prescaler counts 4→3→2→1→0→tick (5 clocks per tick)
        // Period = (LOAD+1) * (PRESCALAR+1) = 4 * 5 = 20 clock cycles
        // =====================================================================
        test_num = 7;
        $display("\n--- Test %0d: Prescaler (LOAD=3, PRESCALAR=4) ---", test_num);

        axi_write(TREG(OFF_STATUS),   32'hFFFF_FFFF);
        axi_write(TREG(OFF_LOAD),     32'd3);
        axi_write(TREG(OFF_PRESCALAR),32'd4);
        axi_write(TREG(OFF_CONTROL),  CTRL_ENABLE | CTRL_IRQ_EN);

        @(posedge clk);
        cycle_start = $time;
        wait_irq(100, timed_out);
        check("Prescaler IRQ fires",   timed_out, 1'b0);
        period_cycles = int'(($time - cycle_start) / CLK_PERIOD);
        $display("  INFO: Prescaled period = %0d cycles (expected 20)", period_cycles);
        check("Prescaled period = 20", period_cycles, 32'd20);

        axi_write(TREG(OFF_CONTROL), 32'h0);
        axi_write(TREG(OFF_STATUS),  32'h1);
        wait_cycles(3);

        // =====================================================================
        // Test 8 — LOAD write mid-count
        // Start LOAD=20. After ~5 ticks, write LOAD=2.
        // Current count runs to 0 unaffected.
        // Second period must be 3 cycles (LOAD=2: counts 2 1 0).
        // =====================================================================
        test_num = 8;
        $display("\n--- Test %0d: LOAD write mid-count ---", test_num);

        axi_write(TREG(OFF_STATUS),   32'hFFFF_FFFF);
        axi_write(TREG(OFF_LOAD),     32'd19);
        axi_write(TREG(OFF_PRESCALAR),32'd0);
        axi_write(TREG(OFF_CONTROL),  CTRL_ENABLE | CTRL_AUTO_RELOAD | CTRL_IRQ_EN);

        // Write new LOAD mid-count
        axi_write(TREG(OFF_LOAD), 32'd49);

        // First IRQ — don't measure this one, period is unknown (mid-flight when LOAD changed)
        wait_irq(50, timed_out);
        check("First overflow still fires", timed_out, 1'b0);
        axi_write(TREG(OFF_STATUS), 32'h1);
        wait_cycles(2);

        // Second IRQ — stamp when it fires, this is our reference point
        wait_irq(100, timed_out);
        cycle_start = $time;              // stamp HERE, at the IRQ event itself
        check("Second IRQ with new LOAD", timed_out, 1'b0);
        axi_write(TREG(OFF_STATUS), 32'h1);
        wait_cycles(2);

        // Third IRQ — measure from second to third = clean 50-cycle period
        wait_irq(100, timed_out);
        period_cycles = int'(($time - cycle_start) / CLK_PERIOD);
        $display("  INFO: Period = %0d cycles (expected 50)", period_cycles);
        check("New LOAD takes effect on reload", period_cycles, 32'd50);
        axi_write(TREG(OFF_STATUS), 32'h1);
        // =====================================================================
        // Results
        // =====================================================================
        $display("\n------------------------------------------------------");
        $display("Results: %0d PASSED  %0d FAILED", pass_count, fail_count);
        $display("------------------------------------------------------");

        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED — check waveforms");

        $finish;
    end

    // =========================================================================
    // Timeout watchdog
    // =========================================================================

    initial begin
        #200_000;
        $display("TIMEOUT — simulation hung, check AXI handshake");
        $finish;
    end

    // =========================================================================
    // Waveform dump
    // =========================================================================

    initial begin
        $dumpfile("timer_tb.vcd");
        $dumpvars(0, tb_timer_directed);
    end

endmodule   