import uvm_pkg::*;


class axi4lite_monitor extends uvm_monitor;
    `uvm_component_utils(axi4lite_monitor)
    virtual axi4lite_if vif;

    uvm_analysis_port #(axi4lite_seq_item) ap;

    function new(string name = "axi4lite_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if(!uvm_config_db #(virtual axi4lite_if)::get(this, "", "vif", vif))
            `uvm_fatal("MONITOR", "Could not get virtual interface from config db")
    endfunction

    // task wait_for_signal_or_reset(logic sig);
    //     while(!sig && vif.ARESETn)
    //         @(posedge vif.ACLK);
    // endtask

    task run_phase(uvm_phase phase);
        forever begin
            axi4lite_seq_item seq_item;
            seq_item = axi4lite_seq_item::type_id::create("seq_item");
            if(!vif.ARESETn) begin
                `uvm_info("MONITOR", "Reset detected - aborting current transaction", UVM_LOW)             
            end
            @(posedge vif.ACLK iff vif.ARESETn);

            if(vif.AWREADY && vif.AWVALID) begin
                seq_item.write = 1;
                seq_item.addr = vif.AWADDR;

                if(!(vif.WREADY && vif.WVALID)) begin
                    //@(posedge vif.ACLK iff (vif.WREADY && vif.WVALID));
                    do @(posedge vif.ACLK);
                    while(!(vif.WREADY && vif.WVALID) && vif.ARESETn);
                    if(!vif.ARESETn) continue;
                end
                seq_item.data = vif.WDATA;
                seq_item.strobe = vif.WSTRB;
                seq_item.timestamp = $time;

                //@(posedge vif.ACLK iff (vif.BREADY && vif.BVALID));
                do @(posedge vif.ACLK);
                while(!(vif.BREADY && vif.BVALID) && vif.ARESETn);
                if(!vif.ARESETn) continue;
                seq_item.resp = vif.BRESP;
                `uvm_info("MONITOR", $sformatf("Write observed: addr=0x%0h data=0x%0h resp=%0b strobe =%0b",
                          seq_item.addr, seq_item.data, seq_item.resp, seq_item.strobe), UVM_MEDIUM)
                ap.write(seq_item);
            end
            else if(vif.ARREADY && vif.ARVALID) begin
                seq_item.write = 0;
                seq_item.addr = vif.ARADDR;

                //@(posedge vif.ACLK iff (vif.RREADY && vif.RVALID));
                do @(posedge vif.ACLK);
                while(!(vif.RREADY && vif.RVALID) && vif.ARESETn);

                if(!vif.ARESETn) continue;
                seq_item.data = vif.RDATA;
                seq_item.resp = vif.RRESP;
                seq_item.timestamp = $time;

                `uvm_info("MONITOR", $sformatf("Read observed: addr=0x%0h data=0x%0h resp=%0b",
                          seq_item.addr, seq_item.data, seq_item.resp), UVM_MEDIUM)
                ap.write(seq_item);
            end
            
        end
    endtask
endclass //axi4lite_monitor extends uvm_monitor