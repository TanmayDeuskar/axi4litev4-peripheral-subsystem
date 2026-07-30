interface irq_if (input logic CLK);
    logic combined_irq;
    logic [2:0] irq_status;

     modport monitor (
        input CLK,
        input combined_irq,
        input irq_status
    );

    modport driver (
        input CLK,
        output combined_irq,
        output irq_status
    );
endinterface