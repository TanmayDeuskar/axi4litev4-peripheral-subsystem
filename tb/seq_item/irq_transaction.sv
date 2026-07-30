import uvm_pkg::*;


`ifndef IRQ_TRANSACTION_SV
`define IRQ_TRANSACTION_SV

class irq_transaction extends uvm_sequence_item;

    logic irq_value;  
    logic [2:0]  irq_status; 
    time timestamp;

    `uvm_object_utils_begin(irq_transaction)
        `uvm_field_int(irq_value,  UVM_ALL_ON)
        `uvm_field_int(irq_status, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "irq_transaction");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("irq=%0b status=0b%03b @%0t",
                          irq_value, irq_status, timestamp);
    endfunction

endclass

`endif