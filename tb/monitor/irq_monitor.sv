import uvm_pkg::*;


class irq_monitor extends uvm_monitor;
    `uvm_component_utils(irq_monitor)

    virtual irq_if.monitor vif;

    uvm_analysis_port #(irq_transaction) ap;

    function new(string name = "irq_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db#(virtual irq_if.monitor)::get(this, "", "vif", vif))
            `uvm_fatal("IRQ_MONITOR", "Could not get virtual interface from config db")
    endfunction

    task run_phase(uvm_phase phase);
        logic prev_irq;
        irq_transaction txn;

        @(posedge vif.CLK);
        prev_irq = vif.combined_irq;

        forever begin
            @(posedge vif.CLK);

            if (vif.combined_irq !== prev_irq) begin
                txn = irq_transaction::type_id::create("txn");
                txn.irq_value  = vif.combined_irq;
                txn.irq_status = vif.irq_status;
                txn.timestamp  = $time;

                `uvm_info("IRQ_MONITOR", txn.convert2string(), UVM_LOW)
                ap.write(txn);

                prev_irq = vif.combined_irq;
            end
        end
    endtask

endclass