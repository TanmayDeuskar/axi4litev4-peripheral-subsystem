`ifndef AXI4LITE_SEQUENCE_SV
`define AXI4LITE_SEQUENCE_SV
 
import uvm_pkg::*;
 
logic [31:0] gpio_known_addr [$];
logic [31:0] timer_known_addr [$];
logic [31:0] fifo_known_addr [$];



class axi_write_seq extends uvm_sequence #(axi4lite_seq_item);
    `uvm_object_utils(axi_write_seq)
 
    logic [31:0] addr;
    logic [31:0] data;
    logic [3:0]  strobe;   //defaults to full word
 
    function new(string name = "axi_write_seq");
        super.new(name);
        strobe = 4'hF;
    endfunction
 
    function void set(logic [31:0] a, logic [31:0] d, logic [3:0] s = 4'hF);
        addr = a;
        data = d;
        strobe = s;
    endfunction
 
    task body();
        axi4lite_seq_item item;
        item = axi4lite_seq_item::type_id::create("item");
        start_item(item);
        item.addr = addr;
        item.data = data;
        item.write = 1'b1;
        item.strobe = strobe;
        finish_item(item);
    endtask
 
endclass

class axi_read_seq extends uvm_sequence #(axi4lite_seq_item);
    `uvm_object_utils(axi_read_seq)
 
    logic [31:0] addr;
    logic [31:0] rdata; 
 
    function new(string name = "axi_read_seq");
        super.new(name);
    endfunction
 
    function void set(logic [31:0] a);
        addr = a;
    endfunction
 
    task body();
        axi4lite_seq_item item;
        item = axi4lite_seq_item::type_id::create("item");
        start_item(item);
        item.addr = addr;
        item.data = 32'h0;
        item.write = 1'b0;
        item.strobe = 4'hF;
        finish_item(item);
        rdata = item.data;  
    endtask
 
endclass

    
class gpio_config_seq extends uvm_sequence #(axi4lite_seq_item);
    `uvm_object_utils(gpio_config_seq)
 
    localparam logic [31:0] GPIO_BASE = 32'h000;
    localparam logic [31:0] ADDR_DATA_OUT = GPIO_BASE + 32'h00;
    localparam logic [31:0] ADDR_DIR = GPIO_BASE + 32'h08;
    localparam logic [31:0] ADDR_INT_EN = GPIO_BASE + 32'h0C;
    localparam logic [31:0] ADDR_INT_TYPE = GPIO_BASE + 32'h14;
    localparam logic [31:0] ADDR_INT_POL = GPIO_BASE + 32'h18;
 
    int unsigned pin_num;
    logic rising;        
    logic edge_triggered; 
    logic [31:0] dataout_val;
 
    function new(string name = "gpio_config_seq");
        super.new(name);
    endfunction
 
    function void randomise();
        pin_num = $urandom_range(0, 31);
        rising = logic'($urandom_range(0, 1));
        edge_triggered = logic'($urandom_range(0, 1));
        //edge_triggered = 1;
        dataout_val = $urandom;
    endfunction
 
    task body();
        axi_write_seq wr;
        logic [31:0]  pin_mask;
        pin_mask = 32'h1 << pin_num;
 
        wr = axi_write_seq::type_id::create("wr");
 
        wr.set(ADDR_DATA_OUT, dataout_val);
        wr.start(get_sequencer());
 
        wr.set(ADDR_DIR, 32'h0);
        wr.start(get_sequencer());
 
        wr.set(ADDR_INT_EN, pin_mask);
        wr.start(get_sequencer());
 
        wr.set(ADDR_INT_TYPE, edge_triggered ? pin_mask : 32'h0);
        wr.start(get_sequencer());
 
        wr.set(ADDR_INT_POL, rising ? pin_mask : 32'h0);
        wr.start(get_sequencer());
 
        gpio_known_addr.push_back(ADDR_DATA_OUT);
        gpio_known_addr.push_back(ADDR_DIR);
    endtask
 
endclass
 
 
class timer_config_seq extends uvm_sequence #(axi4lite_seq_item);
    `uvm_object_utils(timer_config_seq)
 
    localparam logic [31:0] TIMER_BASE = 32'h100;
    localparam logic [31:0] ADDR_LOAD = TIMER_BASE + 32'h00;
    localparam logic [31:0] ADDR_CTRL = TIMER_BASE + 32'h08;
    localparam logic [31:0] ADDR_STATUS = TIMER_BASE + 32'h0C;
    localparam logic [31:0] ADDR_PRESCALAR = TIMER_BASE + 32'h10;
 
    localparam logic [31:0] CTRL_ENABLE = 32'h1;
    localparam logic [31:0] CTRL_AUTO_RELOAD = 32'h2;
    localparam logic [31:0] CTRL_IRQ_EN = 32'h4;
 
    logic [31:0] load_val;
    logic [31:0] prescalar_val;
    logic auto_reload;
 
    function new(string name = "timer_config_seq");
        super.new(name);
    endfunction
 
    function void randomise();
        load_val = $urandom_range(10, 100);
        prescalar_val = $urandom_range(0, 4);
       // auto_reload = logic'($urandom_range(0, 1));
        auto_reload = 1;
    endfunction
 
    task body();
        axi_write_seq wr;
        logic [31:0]  ctrl_val;
 
        ctrl_val = CTRL_ENABLE | CTRL_IRQ_EN;
        if (auto_reload) ctrl_val |= CTRL_AUTO_RELOAD;
 
        wr = axi_write_seq::type_id::create("wr");
 
        wr.set(ADDR_STATUS, 32'hFFFF_FFFF);
        wr.start(get_sequencer());
 
        wr.set(ADDR_LOAD, load_val);
        wr.start(get_sequencer());
 
        wr.set(ADDR_PRESCALAR, prescalar_val);
        wr.start(get_sequencer());
 
        wr.set(ADDR_CTRL, ctrl_val);
        wr.start(get_sequencer());
 
        timer_known_addr.push_back(ADDR_STATUS);
        timer_known_addr.push_back(ADDR_LOAD);
    endtask
 
endclass
 
  
class fifo_write_seq extends uvm_sequence #(axi4lite_seq_item);
    `uvm_object_utils(fifo_write_seq)

    localparam logic [31:0] FIFO_BASE = 32'h200;
    localparam logic [31:0] ADDR_WDATA = FIFO_BASE + 32'h00;
    localparam logic [31:0] ADDR_STATUS = FIFO_BASE + 32'h08;
    localparam logic [31:0] ADDR_THRESH = FIFO_BASE + 32'h10;
    localparam logic [31:0] ADDR_CONTROL = FIFO_BASE + 32'h14;
    localparam logic [31:0] STATUS_FULL = 32'h1;
 
    localparam logic [31:0] CTRL_INT_EN = 32'h1;
 
    int unsigned max_entries = 15; 
    int unsigned num_entries;
    logic [31:0] thresh_val; 
    logic        irq_en;  
    logic [31:0] write_data[$];
 
    function new(string name = "fifo_write_seq");
        super.new(name);
    endfunction
 
    function void randomise();
        num_entries = $urandom_range(1, max_entries);
        thresh_val  = $urandom_range(1, max_entries);
        irq_en      = logic'($urandom_range(0, 1));
    endfunction
 
    task body();
        axi_write_seq wr;
        axi_read_seq  rd;
        logic [31:0]  wdata;
 
        wr = axi_write_seq::type_id::create("wr");
        rd = axi_read_seq::type_id::create("rd");
        write_data.delete();
 
        wr.set(ADDR_THRESH, thresh_val);
        wr.start(get_sequencer());
 
        wr.set(ADDR_CONTROL, irq_en ? CTRL_INT_EN : 32'h0);
        wr.start(get_sequencer());
 
        for (int i = 0; i < num_entries; i++) begin
            rd.set(ADDR_STATUS);
            rd.start(get_sequencer());
 
            if (rd.rdata & STATUS_FULL) begin
                `uvm_info("FIFO_WRITE_SEQ",
                    $sformatf("FIFO full at entry %0d/%0d — stopping early",
                              i, num_entries), UVM_MEDIUM)
                break;
            end
 
            wdata = $urandom;
            write_data.push_back(wdata);
 
            wr.set(ADDR_WDATA, wdata);
            wr.start(get_sequencer());
        end
 
        fifo_known_addr.push_back(ADDR_STATUS);
        fifo_known_addr.push_back(ADDR_THRESH);
        fifo_known_addr.push_back(ADDR_CONTROL);
    endtask
 
endclass


class fifo_read_seq extends uvm_sequence #(axi4lite_seq_item);
    `uvm_object_utils(fifo_read_seq)
 
    localparam logic [31:0] FIFO_BASE = 32'h200;
    localparam logic [31:0] ADDR_RDATA = FIFO_BASE + 32'h04;
    localparam logic [31:0] ADDR_STATUS = FIFO_BASE + 32'h08;
    localparam logic [31:0] STATUS_EMPTY = 32'h2;
 
    int unsigned num_reads;
    logic [31:0] read_data[$];
 
    function new(string name = "fifo_read_seq");
        super.new(name);
    endfunction
 
    task body();
        axi_read_seq rd;
        rd = axi_read_seq::type_id::create("rd");
        read_data.delete();
 
        for (int i = 0; i < num_reads; i++) begin
            rd.set(ADDR_STATUS);
            rd.start(get_sequencer());
 
            if (rd.rdata & STATUS_EMPTY) begin
                `uvm_info("FIFO_READ_SEQ",
                    $sformatf("FIFO empty at read %0d/%0d — stopping early",
                              i, num_reads), UVM_MEDIUM)
                break;
            end
 
            rd.set(ADDR_RDATA);
            rd.start(get_sequencer());
            read_data.push_back(rd.rdata);
        end
    endtask
 
endclass
 


class vseq_gpio_irq extends uvm_sequence;
    `uvm_object_utils(vseq_gpio_irq)
    `uvm_declare_p_sequencer(uvm_sequencer #(axi4lite_seq_item))
 
    virtual gpio_if gpif; 
 
    localparam logic [31:0] GPIO_BASE       = 32'h000;
    localparam logic [31:0] ADDR_INT_STATUS = GPIO_BASE + 32'h10;
 
    function new(string name = "vseq_gpio_irq");
        super.new(name);
    endfunction
 
    task body();
        gpio_config_seq cfg_seq;
        axi_write_seq wr;
        logic [31:0] pin_mask;
 
        if (!uvm_config_db#(virtual gpio_if)::get(null, "", "gpif", gpif))
            `uvm_fatal("VSEQ_GPIO_IRQ", "Could not get gpio_if from config_db")
 
        cfg_seq = gpio_config_seq::type_id::create("cfg_seq");
        cfg_seq.randomise();
        cfg_seq.start(p_sequencer);
 
        pin_mask = 32'h1 << cfg_seq.pin_num;
 
        repeat (3) @(posedge gpif.CLK);
 
        if (cfg_seq.rising) begin
            gpif.gpio_in[cfg_seq.pin_num] = 1'b0;
            repeat (2) @(posedge gpif.CLK);
            gpif.gpio_in[cfg_seq.pin_num] = 1'b1;
        end else begin
            gpif.gpio_in[cfg_seq.pin_num] = 1'b1;
            repeat (2) @(posedge gpif.CLK);
            gpif.gpio_in[cfg_seq.pin_num] = 1'b0;
        end
 
        repeat (5) @(posedge gpif.CLK);  
 
        wr = axi_write_seq::type_id::create("wr");
        wr.set(ADDR_INT_STATUS, pin_mask);
        wr.start(p_sequencer);
 
        `uvm_info("VSEQ_GPIO_IRQ",
            $sformatf("Drove pin %0d %s edge, cleared INT_STATUS",
                      cfg_seq.pin_num, cfg_seq.rising ? "rising" : "falling"),
            UVM_MEDIUM)
    endtask
 
endclass
 
`endif