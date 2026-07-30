`ifndef AXI4LITE_AGENT_SV
`define AXI4LITE_AGENT_SV

import uvm_pkg::*;



class axi4lite_agent extends uvm_agent;
    `uvm_component_utils(axi4lite_agent)

    axi4lite_sequencer sequencer;
    axi4lite_driver driver;
    axi4lite_monitor monitor;

    uvm_analysis_port #(axi4lite_seq_item) ap;

    function new(string name = "axi4lite_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = axi4lite_sequencer::type_id::create("sequencer", this);
        driver = axi4lite_driver::type_id::create("driver",    this);
        monitor = axi4lite_monitor::type_id::create("monitor",   this);
        ap = new("ap", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
        monitor.ap.connect(ap);
    endfunction

endclass

`endif