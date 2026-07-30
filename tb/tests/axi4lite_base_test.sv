`ifndef AXI4LITE_TEST_SV
`define AXI4LITE_TEST_SV

import uvm_pkg::*;

class axi4lite_base_test extends uvm_test;
    `uvm_component_utils(axi4lite_base_test)

    axi4lite_env env;

    function new(string name = "axi4lite_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = axi4lite_env::type_id::create("env", this);
    endfunction

   
    function axi4lite_sequencer get_sequencer();
        return env.axi_agent.sequencer;
    endfunction

    task run_phase(uvm_phase phase);
    endtask

endclass

class test_gpio_basic extends axi4lite_base_test;
    `uvm_component_utils(test_gpio_basic)

    function new(string name = "test_gpio_basic", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        vseq_gpio_irq gpio_seq;
        phase.raise_objection(this);

        gpio_seq = vseq_gpio_irq::type_id::create("gpio_seq");
        gpio_seq.start(get_sequencer());

        // Let any IRQ activity propagate and be captured by irq_monitor
        #200ns;

        phase.drop_objection(this);
    endtask

endclass

class test_timer_basic extends axi4lite_base_test;
    `uvm_component_utils(test_timer_basic)

    function new(string name = "test_timer_basic", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        timer_config_seq  cfg_seq;
        axi_read_seq      rd;
        axi_write_seq     wr;
        phase.raise_objection(this);

        cfg_seq = timer_config_seq::type_id::create("cfg_seq");
        cfg_seq.randomise();
        cfg_seq.start(get_sequencer());

        
        #6000ns;

        rd = axi_read_seq::type_id::create("rd");
        rd.set(32'h10C);
        rd.start(get_sequencer());

        wr = axi_write_seq::type_id::create("wr");
        wr.set(32'h10C, 32'hFFFF_FFFF);
        wr.start(get_sequencer());

        rd.start(get_sequencer());

        #100ns;
        phase.drop_objection(this);
    endtask

endclass


class test_fifo_basic extends axi4lite_base_test;
    `uvm_component_utils(test_fifo_basic)

    function new(string name = "test_fifo_basic", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        fifo_write_seq wr_seq;
        fifo_read_seq  rd_seq;
        phase.raise_objection(this);

        wr_seq = fifo_write_seq::type_id::create("wr_seq");
        wr_seq.randomise();
        wr_seq.start(get_sequencer());

        rd_seq = fifo_read_seq::type_id::create("rd_seq");
        rd_seq.num_reads = wr_seq.write_data.size();
        rd_seq.start(get_sequencer());

        #100ns;
        phase.drop_objection(this);
    endtask

endclass


class test_all_peripherals extends axi4lite_base_test;
    `uvm_component_utils(test_all_peripherals)

    function new(string name = "test_all_peripherals", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        gpio_config_seq  gpio_cfg;
        timer_config_seq timer_cfg;
        fifo_write_seq   fifo_wr;
        fifo_read_seq    fifo_rd;
        phase.raise_objection(this);

        gpio_cfg = gpio_config_seq::type_id::create("gpio_cfg");
        gpio_cfg.randomise();
        gpio_cfg.start(get_sequencer());

        timer_cfg = timer_config_seq::type_id::create("timer_cfg");
        timer_cfg.randomise();
        timer_cfg.start(get_sequencer());

        fifo_wr = fifo_write_seq::type_id::create("fifo_wr");
        fifo_wr.randomise();
        fifo_wr.start(get_sequencer());

        #6000ns;

        fifo_rd = fifo_read_seq::type_id::create("fifo_rd");
        fifo_rd.num_reads = fifo_wr.write_data.size();
        fifo_rd.start(get_sequencer());

        #200ns;
        phase.drop_objection(this);
    endtask

endclass

`endif