import uvm_pkg::*;

`ifndef GPIO_TRANSACTION_SV
`define GPIO_TRANSACTION_SV

class gpio_transaction extends uvm_sequence_item;

    logic [31:0] gpio_out;
    logic [31:0] gpio_oe;
    time timestamp; 

    `uvm_object_utils_begin(gpio_transaction)
        `uvm_field_int(gpio_out, UVM_ALL_ON)
        `uvm_field_int(gpio_oe,  UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "gpio_transaction");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("gpio_out=0x%08h gpio_oe=0x%08h @%0t",
                          gpio_out, gpio_oe, timestamp);
    endfunction

endclass

`endif