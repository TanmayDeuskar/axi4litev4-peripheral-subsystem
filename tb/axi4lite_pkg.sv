`ifndef AXI4LITE_PKG_SV
`define AXI4LITE_PKG_SV

package axi4lite_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

   
    `include "../tb/seq_item/axi4lite_seq_item.sv"
    `include "../tb/seq_item/gpio_transaction.sv"
    `include "../tb/seq_item/irq_transaction.sv"

   
    `include "../tb/driver/axi4lite_driver.sv"
    `include "../tb/monitor/axi4lite_monitor.sv"
    `include "../tb/monitor/gpio_monitor.sv"
    `include "../tb/monitor/irq_monitor.sv"

   
    `include "../tb/scoreboard/axi4lite_scoreboard.sv"

    `include "../tb/coverage/axi4lite_coverage.sv"

    `include "../tb/sequencer/axi4lite_sequencer.sv"

    `include "../tb/agent/axi4lite_agent.sv"

    `include "../tb/sequence/axi4lite_sequence.sv"

    `include "../tb/env/axi4lite_env.sv"

    `include "../tb/tests/axi4lite_base_test.sv"

endpackage

`endif