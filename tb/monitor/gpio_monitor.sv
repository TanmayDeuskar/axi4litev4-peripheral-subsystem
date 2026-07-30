import uvm_pkg::*;

class gpio_monitor extends uvm_monitor;
    `uvm_component_utils(gpio_monitor)

    virtual gpio_if vif;

    uvm_analysis_port #(gpio_transaction) ap;

    function new(string name = "gpio_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db#(virtual gpio_if)::get(this, "", "vif", vif))
            `uvm_fatal("GPIO_MONITOR", "Could not get virtual interface from config db")
    endfunction

    task run_phase(uvm_phase phase);
        gpio_transaction txn;
        logic [31:0] prev_out;
        logic [31:0] prev_oe;

       
        @(posedge vif.CLK iff vif.RESETn);
        prev_out = vif.gpio_out;
        prev_oe = vif.gpio_oe;

        forever begin
            @(posedge vif.CLK);

        
            if (!vif.RESETn) begin
                @(posedge vif.CLK iff vif.RESETn);
                prev_out = vif.gpio_out;
                prev_oe = vif.gpio_oe;
                continue;
            end

            if (vif.gpio_out !== prev_out || vif.gpio_oe !== prev_oe) begin

                txn = gpio_transaction::type_id::create("txn");
                txn.gpio_out = vif.gpio_out;
                txn.gpio_oe = vif.gpio_oe;
                txn.timestamp = $time;

                `uvm_info("GPIO_MONITOR", txn.convert2string(), UVM_LOW)

                ap.write(txn);  

                prev_out = vif.gpio_out;
                prev_oe = vif.gpio_oe;
            end
        end
    endtask

endclass