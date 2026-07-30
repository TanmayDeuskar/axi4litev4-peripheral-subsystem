module irq_aggregator (
    input  logic gpio_irq,
    input  logic timer_irq,
    input  logic fifo_irq,
    irq_if.driver irqif 
);
    assign irqif.combined_irq = gpio_irq | timer_irq | fifo_irq;
    assign irqif.irq_status = {fifo_irq, timer_irq, gpio_irq};
endmodule