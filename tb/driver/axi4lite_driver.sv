import uvm_pkg::*;


class axi4lite_driver extends uvm_driver #(axi4lite_seq_item);
    `uvm_component_utils(axi4lite_driver)

    virtual axi4lite_if vif;

    function new(string name = "axi4lite_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi4lite_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRIVER", "Could not get virtual interface from config db")
    endfunction

    task run_phase(uvm_phase phase);
        axi4lite_seq_item seq_item;

        reset_signals();

        forever begin
            seq_item_port.get_next_item(seq_item);

            if (seq_item.write)
                driver_write(seq_item);
            else
                driver_read(seq_item);

            if (!vif.ARESETn) begin
                `uvm_info("DRIVER", "Reset detected - aborting current transaction", UVM_LOW)
                reset_signals();
            end

            seq_item_port.item_done();
        end
    endtask

    
    task reset_signals();
        vif.AWVALID <= 0;
        vif.AWADDR  <= 0;
        vif.WVALID  <= 0;
        vif.WDATA   <= 0;
        vif.WSTRB   <= 0;
        vif.BREADY  <= 0;

        vif.ARVALID <= 0;
        vif.ARADDR  <= 0;
        vif.RREADY  <= 0;

        @(posedge vif.ACLK iff vif.ARESETn);
    endtask

    
    task wait_for_signal_or_reset(ref logic sig);
        do begin
            @(posedge vif.ACLK);
        end
        while (!sig && vif.ARESETn);
    endtask

    

    task driver_write(axi4lite_seq_item seq_item);
        vif.AWADDR  <= seq_item.addr;
        vif.AWVALID <= 1;
        wait_for_signal_or_reset(vif.AWREADY);
        if (!vif.ARESETn) return;
        vif.AWVALID <= 0;

        vif.WDATA  <= seq_item.data;
        vif.WSTRB  <= seq_item.strobe;
        vif.WVALID <= 1;
        wait_for_signal_or_reset(vif.WREADY);
        if (!vif.ARESETn) return;
        vif.WVALID <= 0;

        vif.BREADY <= 1;
        wait_for_signal_or_reset(vif.BVALID);
        if (!vif.ARESETn) return;
        vif.BREADY <= 0;

        seq_item.resp = vif.BRESP;

        `uvm_info("DRIVER",
            $sformatf("Write done: addr=0x%0h data=0x%0h", seq_item.addr, seq_item.data),
            UVM_MEDIUM)
    endtask

   
    task driver_read(axi4lite_seq_item seq_item);
        vif.ARADDR  <= seq_item.addr;
        vif.ARVALID <= 1;
        vif.RREADY  <= 1;

        wait_for_signal_or_reset(vif.ARREADY);
        if (!vif.ARESETn) return;
        vif.ARVALID <= 0;

        wait_for_signal_or_reset(vif.RVALID);
        if (!vif.ARESETn) return;
        vif.RREADY <= 0;

        seq_item.data = vif.RDATA;   
        seq_item.resp = vif.RRESP;

        `uvm_info("DRIVER",
            $sformatf("Read done: addr=0x%0h data=0x%0h", seq_item.addr, seq_item.data),
            UVM_MEDIUM)
    endtask

endclass