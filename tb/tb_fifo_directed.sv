// =============================================================================
// tb_fifo_directed.sv
// Directed Testbench for FIFO Peripheral via AXI4-Lite Subsystem
//
// DUT: top.sv
// FIFO base address: 0x200 (per address_decoder)
//
// Tests:
//   Test 1 — THRESH and CONTROL register write/read back
//   Test 2 — Write and read single entry, verify data integrity
//   Test 3 — Fill to full, verify full flag, write to full is dropped
//   Test 4 — Drain to empty, verify empty flag, read from empty returns 0
//   Test 5 — DEPTH_REG reads back correctly
//   Test 6 — Threshold IRQ: set THRESH=4, fill to 4, verify IRQ fires
//   Test 7 — IRQ deasserts when fill drops below threshold
//   Test 8 — IRQ gating: irq_en=0, threshold crossed, IRQ must stay low
//   Test 9 — FIFO ordering: write N values, read back in same order
//   Test 10 — Wrap around: fill, drain, fill again across pointer wrap
//
// Clock: 10ns period (100MHz)
// Reset: active low, held for 5 cycles
// =============================================================================

`timescale 1ns/1ps

module tb_fifo_directed;

    // =========================================================================
    // Parameters
    // =========================================================================

    localparam CLK_PERIOD = 10;

    // FIFO base address
    localparam logic [31:0] FIFO_BASE = 32'h200;

    // Register offsets
    localparam logic [31:0] OFF_WDATA   = 32'h00;
    localparam logic [31:0] OFF_RDATA   = 32'h04;
    localparam logic [31:0] OFF_STATUS  = 32'h08;
    localparam logic [31:0] OFF_DEPTH   = 32'h0C;
    localparam logic [31:0] OFF_THRESH  = 32'h10;
    localparam logic [31:0] OFF_CONTROL = 32'h14;

    // STATUS bit masks
    localparam logic [31:0] STATUS_FULL   = 32'h1;
    localparam logic [31:0] STATUS_EMPTY  = 32'h2;
    localparam logic [31:0] STATUS_THRESH = 32'h4;

    // CONTROL bit masks
    localparam logic [31:0] CTRL_IRQ_EN = 32'h1;

    // FIFO depth — must match parameter in RTL
    localparam int FIFO_DEPTH = 16;

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
    fifo_if     fifoif (.CLK(clk),   .RESETn(rst_n));

    // =========================================================================
    // DUT
    // =========================================================================

    logic irq;

    top dut (
        .axiif  (axiif),
        .gpif   (gpif),
        .tif    (tif),
        .fifoif  (fifoif),
        .irq    (irq)
    );

    // =========================================================================
    // Test tracking
    // =========================================================================

    int pass_count = 0;
    int fail_count = 0;
    int test_num   = 0;

    // =========================================================================
    // Task: AXI Write
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
    // Helper: FIFO register full address
    // =========================================================================

    function automatic logic [31:0] FREG(input logic [31:0] offset);
        return FIFO_BASE + offset;
    endfunction

    // =========================================================================
    // Main test sequence
    // =========================================================================

    logic [31:0] rdata;
    logic [31:0] rdata2;

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

        // Reset
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        @(posedge clk);
        rst_n = 1'b1;
        wait_cycles(2);

        $display("------------------------------------------------------");
        $display("FIFO Directed Testbench Starting");
        $display("FIFO base: 0x%03h  depth: %0d", FIFO_BASE, FIFO_DEPTH);
        $display("------------------------------------------------------");

        // =====================================================================
        // Test 1 — Register write and read back
        // THRESH and CONTROL survive a write/read round trip.
        // IRQ must be low (irq_en=0 after reset).
        // =====================================================================
        test_num = 1;
        $display("\n--- Test %0d: Register write/read back ---", test_num);

        axi_write(FREG(OFF_THRESH),  32'd8);
        axi_write(FREG(OFF_CONTROL), 32'h0); // irq_en=0

        axi_read(FREG(OFF_THRESH),  rdata);
        check("THRESH read back",   rdata, 32'd8);

        axi_read(FREG(OFF_CONTROL), rdata);
        check("CONTROL read back",  rdata, 32'h0);

        // STATUS should show empty after reset
        axi_read(FREG(OFF_STATUS), rdata);
        check("STATUS empty at reset", rdata & STATUS_EMPTY, STATUS_EMPTY);
        check("STATUS not full",       rdata & STATUS_FULL,  32'h0);

        check("IRQ low at reset", {31'h0, irq}, 32'h0);

        wait_cycles(2);

        // =====================================================================
        // Test 2 — Single write then read, verify data integrity
        // Write 0xDEADBEEF, read it back, verify match
        // =====================================================================
        test_num = 2;
        $display("\n--- Test %0d: Single write/read ---", test_num);

        // Reset THRESH to 1 so STATUS[2] is easy to observe
        axi_write(FREG(OFF_THRESH), 32'd1);

        axi_write(FREG(OFF_WDATA), 32'hDEAD_BEEF);
        wait_cycles(1);

        // STATUS should show not empty, not full
        axi_read(FREG(OFF_STATUS), rdata);
        check("Not empty after write",  rdata & STATUS_EMPTY, 32'h0);
        check("Not full after 1 write", rdata & STATUS_FULL,  32'h0);
        check("Thresh flag set (>=1)",  rdata & STATUS_THRESH, STATUS_THRESH);

        axi_read(FREG(OFF_RDATA), rdata);
        check("Read back matches write", rdata, 32'hDEAD_BEEF);

        // Now empty again
        axi_read(FREG(OFF_STATUS), rdata);
        check("Empty after read", rdata & STATUS_EMPTY, STATUS_EMPTY);

        wait_cycles(2);

        // =====================================================================
        // Test 3 — Fill to full
        // Write DEPTH entries, verify full flag sets, extra write is dropped
        // =====================================================================
        test_num = 3;
        $display("\n--- Test %0d: Fill to full ---", test_num);

        // Write DEPTH entries
        for (int i = 0; i < FIFO_DEPTH; i++) begin
            axi_write(FREG(OFF_WDATA), 32'(i + 1)); // values 1..16
        end
        wait_cycles(2);

        axi_read(FREG(OFF_STATUS), rdata);
        check("Full flag set",    rdata & STATUS_FULL,  STATUS_FULL);
        check("Not empty (full)", rdata & STATUS_EMPTY, 32'h0);

        // Write one more — must be dropped
        axi_write(FREG(OFF_WDATA), 32'hDEAD_DEAD);
        wait_cycles(2);

        // First read must still be 1 (not 0xDEADDEAD)
        axi_read(FREG(OFF_RDATA), rdata);
        check("Write to full dropped — first entry intact", rdata, 32'd1);

        // Drain remaining 15 entries
        for (int i = 0; i < FIFO_DEPTH - 1; i++) begin
            axi_read(FREG(OFF_RDATA), rdata);
        end
        wait_cycles(2);

        axi_read(FREG(OFF_STATUS), rdata);
        check("Empty after full drain", rdata & STATUS_EMPTY, STATUS_EMPTY);

        wait_cycles(2);

        // =====================================================================
        // Test 4 — Read from empty returns 0, pointer does not move
        // Write one entry, drain it, then read again — must get 0
        // =====================================================================
        test_num = 4;
        $display("\n--- Test %0d: Read from empty ---", test_num);

        axi_write(FREG(OFF_WDATA), 32'hABCD_1234);
        axi_read(FREG(OFF_RDATA),  rdata);
        check("Valid read",         rdata, 32'hABCD_1234);

        // FIFO now empty — read again
        axi_read(FREG(OFF_RDATA), rdata);
        check("Read from empty = 0", rdata, 32'h0);

        // Write another entry — pointer must not have advanced on empty read
        axi_write(FREG(OFF_WDATA), 32'h1111_2222);
        axi_read(FREG(OFF_RDATA),  rdata);
        check("Pointer intact after empty read", rdata, 32'h1111_2222);

        wait_cycles(2);

        // =====================================================================
        // Test 5 — DEPTH_REG reads back FIFO_DEPTH
        // =====================================================================
        test_num = 5;
        $display("\n--- Test %0d: DEPTH_REG read back ---", test_num);

        axi_read(FREG(OFF_DEPTH), rdata);
        check("DEPTH_REG = 16", rdata, 32'(FIFO_DEPTH));

        wait_cycles(2);

        // =====================================================================
        // Test 6 — Threshold IRQ
        // Set THRESH=4, irq_en=1. Write 3 entries — IRQ must stay low.
        // Write 4th entry — IRQ must assert.
        // =====================================================================
        test_num = 6;
        $display("\n--- Test %0d: Threshold IRQ (THRESH=4) ---", test_num);

        axi_write(FREG(OFF_THRESH),  32'd4);
        axi_write(FREG(OFF_CONTROL), CTRL_IRQ_EN);

        // Write 3 — below threshold
        axi_write(FREG(OFF_WDATA), 32'hAAAA_0001);
        axi_write(FREG(OFF_WDATA), 32'hAAAA_0002);
        axi_write(FREG(OFF_WDATA), 32'hAAAA_0003);
        wait_cycles(2);
        check("IRQ low below threshold", {31'h0, irq}, 32'h0);

        axi_read(FREG(OFF_STATUS), rdata);
        check("Thresh flag low (fill=3)", rdata & STATUS_THRESH, 32'h0);

        // Write 4th — at threshold
        axi_write(FREG(OFF_WDATA), 32'hAAAA_0004);
        wait_cycles(2);
        check("IRQ asserts at threshold", {31'h0, irq}, 32'h1);

        axi_read(FREG(OFF_STATUS), rdata);
        check("Thresh flag set (fill=4)", rdata & STATUS_THRESH, STATUS_THRESH);

        // Drain all 4
        for (int i = 0; i < 4; i++) axi_read(FREG(OFF_RDATA), rdata);
        wait_cycles(2);

        axi_write(FREG(OFF_CONTROL), 32'h0); // disable irq_en
        wait_cycles(2);

        // =====================================================================
        // Test 7 — IRQ deasserts when fill drops below threshold
        // Fill to threshold, verify IRQ, read one entry, verify IRQ drops
        // =====================================================================
        test_num = 7;
        $display("\n--- Test %0d: IRQ deasserts below threshold ---", test_num);

        axi_write(FREG(OFF_THRESH),  32'd4);
        axi_write(FREG(OFF_CONTROL), CTRL_IRQ_EN);

        for (int i = 0; i < 4; i++)
            axi_write(FREG(OFF_WDATA), 32'(32'hBBBB_0000 + i));
        wait_cycles(2);
        check("IRQ high at fill=4",      {31'h0, irq}, 32'h1);

        // Read one entry — fill drops to 3, below threshold
        axi_read(FREG(OFF_RDATA), rdata);
        wait_cycles(2);
        check("IRQ deasserts at fill=3", {31'h0, irq}, 32'h0);

        // Drain rest
        for (int i = 0; i < 3; i++) axi_read(FREG(OFF_RDATA), rdata);
        axi_write(FREG(OFF_CONTROL), 32'h0);
        wait_cycles(2);

        // =====================================================================
        // Test 8 — IRQ gating: irq_en=0, threshold crossed, IRQ must stay low
        // STATUS[2] must still set — software can poll
        // =====================================================================
        test_num = 8;
        $display("\n--- Test %0d: IRQ gating (irq_en=0) ---", test_num);

        axi_write(FREG(OFF_THRESH),  32'd2);
        axi_write(FREG(OFF_CONTROL), 32'h0); // irq_en=0

        axi_write(FREG(OFF_WDATA), 32'hCCCC_0001);
        axi_write(FREG(OFF_WDATA), 32'hCCCC_0002);
        wait_cycles(2);

        axi_read(FREG(OFF_STATUS), rdata);
        check("Thresh flag set without irq_en", rdata & STATUS_THRESH, STATUS_THRESH);
        check("IRQ line stays low",             {31'h0, irq},          32'h0);

        // Drain
        for (int i = 0; i < 2; i++) axi_read(FREG(OFF_RDATA), rdata);
        wait_cycles(2);

        // =====================================================================
        // Test 9 — FIFO ordering: write 8 values, read back in same order
        // =====================================================================
        test_num = 9;
        $display("\n--- Test %0d: FIFO ordering (8 entries) ---", test_num);

        axi_write(FREG(OFF_CONTROL), 32'h0);

        for (int i = 0; i < 8; i++)
            axi_write(FREG(OFF_WDATA), 32'(32'hF000_0000 + i));

        for (int i = 0; i < 8; i++) begin
            axi_read(FREG(OFF_RDATA), rdata);
            check($sformatf("Order entry %0d", i), rdata, 32'(32'hF000_0000 + i));
        end

        wait_cycles(2);

        // =====================================================================
        // Test 10 — Wrap around
        // Fill DEPTH/2, drain DEPTH/2, fill DEPTH/2 again.
        // Pointers have wrapped. Verify data still correct.
        // =====================================================================
        test_num = 10;
        $display("\n--- Test %0d: Pointer wrap-around ---", test_num);

        // First half
        for (int i = 0; i < FIFO_DEPTH/2; i++)
            axi_write(FREG(OFF_WDATA), 32'(32'hA000_0000 + i));

        for (int i = 0; i < FIFO_DEPTH/2; i++) begin
            axi_read(FREG(OFF_RDATA), rdata);
            check($sformatf("Pre-wrap entry %0d", i), rdata, 32'(32'hA000_0000 + i));
        end

        // Pointers have both advanced to DEPTH/2 = 8
        axi_read(FREG(OFF_STATUS), rdata);
        check("Empty after first half drain", rdata & STATUS_EMPTY, STATUS_EMPTY);

        // Second half — pointers will wrap during this
        for (int i = 0; i < FIFO_DEPTH/2; i++)
            axi_write(FREG(OFF_WDATA), 32'(32'hB000_0000 + i));

        for (int i = 0; i < FIFO_DEPTH/2; i++) begin
            axi_read(FREG(OFF_RDATA), rdata);
            check($sformatf("Post-wrap entry %0d", i), rdata, 32'(32'hB000_0000 + i));
        end

        axi_read(FREG(OFF_STATUS), rdata);
        check("Empty after wrap drain", rdata & STATUS_EMPTY, STATUS_EMPTY);

        wait_cycles(5);

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
        #500_000;
        $display("TIMEOUT — simulation hung");
        $finish;
    end

    // =========================================================================
    // Waveform dump
    // =========================================================================

    initial begin
        $dumpfile("fifo_tb.vcd");
        $dumpvars(0, tb_fifo_directed);
    end

endmodule