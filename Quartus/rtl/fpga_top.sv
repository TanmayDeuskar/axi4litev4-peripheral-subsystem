module fpga_top (
    input  logic ACLK,
    input  logic ARESETn,

    input  logic [31:0] AWADDR,
    input  logic AWVALID,
    output logic AWREADY,

    input  logic [31:0] WDATA,
    input  logic [3:0] WSTRB,
    input  logic WVALID,
    output logic WREADY,

    output logic [1:0] BRESP,
    output logic BVALID,
    input  logic BREADY,

    input  logic [31:0] ARADDR,
    input  logic ARVALID,
    output logic ARREADY,

    output logic [31:0] RDATA,
    output logic [1:0] RRESP,
    output logic RVALID,
    input  logic RREADY,

    output [31:0] gpio_out,
    output [31:0] gpio_oe,
    input[31:0] gpio_in,

    output combined_irq,
    output [2:0] irq_status
    
);

    axi4lite_if axiif (
        .ACLK(ACLK),
        .ARESETn(ARESETn)
    );

    // connect flat ports to interface signals
    assign axiif.AWADDR = AWADDR;
    assign axiif.AWVALID = AWVALID;
    assign AWREADY = axiif.AWREADY;

    assign axiif.WDATA = WDATA;
    assign axiif.WSTRB = WSTRB;
    assign axiif.WVALID = WVALID;
    assign WREADY = axiif.WREADY;

    assign BRESP = axiif.BRESP;
    assign BVALID = axiif.BVALID;
    assign axiif.BREADY = BREADY;

    assign axiif.ARADDR = ARADDR;
    assign axiif.ARVALID = ARVALID;
    assign ARREADY = axiif.ARREADY;

    assign RDATA = axiif.RDATA;
    assign RRESP = axiif.RRESP;
    assign RVALID = axiif.RVALID;
    assign axiif.RREADY = RREADY;


    gpio_if gpif (
        .CLK(ACLK),
        .RESETn(ARESETn)
    );

    assign gpio_out = gpif.gpio_out;
    assign gpio_oe = gpif.gpio_oe;
    assign gpif.gpio_in = gpio_in;

    fifo_if fifoif (
        .CLK(ACLK),
        .RESETn(ARESETn)
    );

    timer_if tif (
        .CLK(ACLK),
        .RESETn(ARESETn)
    );

    irq_if irqif (
        .CLK(ACLK)
    );

    assign combined_irq = irqif.combined_irq;
    assign irq_status = irqif.irq_status;

    top dut(
        .axiif(axiif.subordinate),
        .gpif(gpif.subordinate),
        .tif(tif.subordinate),
        .fifoif(fifoif.subordinate),
        .irqif(irqif.driver)
    );

    
endmodule