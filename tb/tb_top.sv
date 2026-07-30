`ifndef TB_TOP_SV
`define TB_TOP_SV

import axi4lite_pkg::*;

import uvm_pkg::*;
`include "uvm_macros.svh"

module tb_top;

    logic ACLK;
    logic ARESETn;

    initial ACLK = 1'b0;
    always #5 ACLK = ~ACLK;

    initial begin
        ARESETn = 1'b0;
        repeat (5) @(posedge ACLK); 
        @(negedge ACLK); 
        ARESETn = 1'b1;
    end

    axi4lite_if axi_if (.ACLK(ACLK), .ARESETn(ARESETn));
    gpio_if gpio_if_inst (.CLK(ACLK), .RESETn(ARESETn));
    timer_if timer_if_inst(.CLK(ACLK), .RESETn(ARESETn));
    fifo_if fifo_if_inst (.CLK(ACLK), .RESETn(ARESETn));
    irq_if irq_if_inst (.CLK(ACLK));

    top dut (
        .axiif (axi_if),
        .gpif (gpio_if_inst),
        .tif (timer_if_inst),
        .fifoif (fifo_if_inst),
        .irqif (irq_if_inst)
    );

    initial begin
        uvm_config_db #(virtual axi4lite_if)::set(
            null, "uvm_test_top.*", "vif", axi_if);

        uvm_config_db #(virtual gpio_if)::set(
            null, "uvm_test_top.*", "vif", gpio_if_inst);

        uvm_config_db #(virtual gpio_if)::set(
            null, "", "gpif", gpio_if_inst);

        uvm_config_db #(virtual irq_if.monitor)::set(
            null, "uvm_test_top.*", "vif", irq_if_inst);

        run_test();
    end

endmodule

`endif