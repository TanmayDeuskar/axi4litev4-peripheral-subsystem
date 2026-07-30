module top (
    axi4lite_if.subordinate axiif,
    gpio_if.subordinate gpif,
    timer_if.subordinate tif,
    fifo_if.subordinate fifoif,
    irq_if.driver irqif
);

    logic irq_gpio;
    logic irq_timer;
    logic irq_fifo;

    logic psel;
    logic pwrite;
    logic [31:0] paddr;
    logic [31:0] pwdata;
    logic [31:0] prdata;
    logic prdata_valid;

    logic gpio_sel;
    logic gpio_write;
    logic [7:0] gpio_addr;
    logic [31:0] gpio_wdata;
    logic [31:0] gpio_rdata;
    logic gpio_data_valid;

    logic timer_sel;
    logic timer_write;
    logic [7:0] timer_addr;
    logic [31:0] timer_wdata;
    logic [31:0] timer_rdata;
    logic timer_data_valid;

    logic fifo_sel;
    logic fifo_write;
    logic [7:0] fifo_addr;
    logic [31:0] fifo_wdata;
    logic [31:0] fifo_rdata;
    logic fifo_data_valid;

    gpio gpio1(
        .gpif(gpif),
        .psel(gpio_sel),
        .pwrite(gpio_write),
        .paddr(gpio_addr),
        .pwdata(gpio_wdata),
        .prdata(gpio_rdata),
        .prdata_valid(gpio_data_valid),
        .irq(irq_gpio)
    );

    timer timer1(
        .tif(tif),
        .psel(timer_sel),
        .pwrite(timer_write),
        .paddr(timer_addr),
        .pwdata(timer_wdata),
        .prdata(timer_rdata),
        .prdata_valid(timer_data_valid),
        .irq(irq_timer)
    );

    fifo fifo1(
        .fifoif(fifoif),
        .psel(fifo_sel),
        .pwrite(fifo_write),
        .paddr(fifo_addr),
        .pwdata(fifo_wdata),
        .prdata(fifo_rdata),
        .prdata_valid(fifo_data_valid),
        .irq(irq_fifo)
    );

    irq_aggregator aggr(
        .gpio_irq(irq_gpio),
        .timer_irq(irq_timer),
        .fifo_irq(irq_fifo),
        .irqif(irqif) 
    );
    
    axi4lite_wrapper wrapper(
        .axiif(axiif),
        .prdata(prdata),
        .prdata_valid(prdata_valid),
        .psel(psel),
        .pwrite(pwrite),
        .paddr(paddr),
        .pwdata(pwdata)
    );

    address_decoder u_decoder (
        .psel(psel),
        .pwrite(pwrite),
        .paddr(paddr),
        .pwdata(pwdata),
 
        // back to wrapper
        .prdata(prdata),
        .prdata_valid(prdata_valid),
 
        // GPIO
        .gpio_sel(gpio_sel),
        .gpio_write(gpio_write),
        .gpio_addr(gpio_addr),
        .gpio_wdata(gpio_wdata),
        .gpio_rdata(gpio_rdata),
        .gpio_data_valid(gpio_data_valid),
 
        // Timer — stubbed
        .timer_sel(timer_sel),
        .timer_write(timer_write),
        .timer_addr(timer_addr),
        .timer_wdata(timer_wdata),
        .timer_rdata(timer_rdata),
        .timer_data_valid(timer_data_valid),
 
        // FIFO — stubbed
        .fifo_sel(fifo_sel),
        .fifo_write(fifo_write),
        .fifo_addr(fifo_addr),
        .fifo_wdata(fifo_wdata),
        .fifo_rdata(fifo_rdata),
        .fifo_data_valid(fifo_data_valid)
    );
    

 
endmodule