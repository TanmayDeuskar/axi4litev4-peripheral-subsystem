`ifndef AXI4LITE_ENV_SV
`define AXI4LITE_ENV_SV

import uvm_pkg::*;

class axi4lite_env extends uvm_env;
    `uvm_component_utils(axi4lite_env)

    axi4lite_agent axi_agent;

    gpio_monitor gpio_mon;
    irq_monitor irq_mon;

    axi4lite_scoreboard scoreboard;
    axi4lite_coverage coverage;


    function new(string name = "axi4lite_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        axi_agent = axi4lite_agent::type_id::create("axi_agent", this);
        gpio_mon = gpio_monitor::type_id::create("gpio_mon", this);
        irq_mon = irq_monitor::type_id::create("irq_mon", this);
        scoreboard = axi4lite_scoreboard::type_id::create("scoreboard", this);
        coverage = axi4lite_coverage::type_id::create("coverage", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        axi_agent.ap.connect(scoreboard.analysis_export);

        axi_agent.ap.connect(coverage.analysis_export);

        gpio_mon.ap.connect(scoreboard.gpio_imp);

        irq_mon.ap.connect(scoreboard.irq_imp);
    endfunction

endclass

`endif