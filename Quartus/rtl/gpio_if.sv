interface gpio_if(input logic CLK, input logic RESETn);
    logic [31:0] gpio_out;
    logic [31:0] gpio_in;
    logic [31:0] gpio_oe;

    modport controller (
        input CLK,
        input RESETn,
        input gpio_out,
        output gpio_in,
        input gpio_oe
    );

    modport subordinate (
        input CLK,
        input RESETn,
        input gpio_in,
        output gpio_oe,
        output gpio_out
    );

endinterface