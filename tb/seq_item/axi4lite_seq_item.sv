import uvm_pkg::*;

class axi4lite_seq_item extends uvm_sequence_item;

    logic [31:0] addr;
    logic [31:0] data;
    logic [3:0] strobe;
    logic write;
    logic [1:0] resp;
    time timestamp;
   



    `uvm_object_utils_begin(axi4lite_seq_item)
        `uvm_field_int(addr,  UVM_ALL_ON)
        `uvm_field_int(data,  UVM_ALL_ON)
        `uvm_field_int(strobe, UVM_ALL_ON)
        `uvm_field_int(write, UVM_ALL_ON)
        `uvm_field_int(resp,  UVM_ALL_ON)
        `uvm_field_int(timestamp, UVM_ALL_ON)
        
    `uvm_object_utils_end


    function new(string name = "axi4lite_seq_item");
        super.new(name);
    endfunction //new()
    
endclass //axi4_seq_item extends uvm_seq_item

