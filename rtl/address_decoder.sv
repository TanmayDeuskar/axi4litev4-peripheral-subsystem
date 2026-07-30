module address_decoder (
    input logic psel,
    input logic pwrite,
    input logic [31:0] paddr,
    input logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic prdata_valid,

    output logic gpio_sel,
    output logic gpio_write,
    output logic [7:0] gpio_addr,
    output logic [31:0] gpio_wdata,
    input logic [31:0] gpio_rdata,
    input logic gpio_data_valid,

    output logic timer_sel,
    output logic timer_write,
    output logic [7:0] timer_addr,
    output logic [31:0] timer_wdata,
    input logic [31:0] timer_rdata,
    input logic timer_data_valid,

    output logic fifo_sel,
    output logic fifo_write,
    output logic [7:0] fifo_addr,
    output logic [31:0] fifo_wdata,
    input logic [31:0] fifo_rdata,
    input logic fifo_data_valid   
);


 

localparam logic [31:0] gpio_base_addr = 32'h000;
localparam logic [31:0] timer_base_addr = 32'h100;
localparam logic [31:0] fifo_base_addr = 32'h200;
localparam logic [31:0] p_size = 32'h100;
always_comb begin
    gpio_sel = 0;
    gpio_write = 0;
    gpio_addr = 0;
    gpio_wdata = 0;

    timer_sel = 0;
    timer_write = 0;
    timer_addr = 0;
    timer_wdata = 0;
    
    fifo_sel = 0;
    fifo_write = 0;
    fifo_addr = 0;
    fifo_wdata = 0;

    prdata = 0;
    prdata_valid = 0;
    

    if(paddr >= gpio_base_addr && paddr < gpio_base_addr + p_size) begin
        gpio_sel = psel;
        gpio_write = pwrite;
        gpio_addr = paddr[7:0] - gpio_base_addr[7:0];
        gpio_wdata = pwdata;
        prdata = gpio_rdata;
        prdata_valid = gpio_data_valid;
    end
    else if(paddr >= timer_base_addr && paddr < timer_base_addr + p_size) begin
        timer_sel = psel;
        timer_write = pwrite;
        timer_addr = paddr[7:0] - timer_base_addr[7:0];
        timer_wdata = pwdata;
        prdata = timer_rdata;
        prdata_valid = timer_data_valid;
    end
    else if(paddr >= fifo_base_addr && paddr < fifo_base_addr + p_size) begin
        fifo_sel = psel;
        fifo_write = pwrite;
        fifo_addr = paddr[7:0] - fifo_base_addr[7:0];
        fifo_wdata = pwdata;
        prdata = fifo_rdata;
        prdata_valid = fifo_data_valid;
    end
    
    
end


    
endmodule