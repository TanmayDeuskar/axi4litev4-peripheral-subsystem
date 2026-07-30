interface fifo_if(input logic CLK, input logic RESETn);

    modport controller (
        input CLK,
        input RESETn
    );

    modport subordinate (
        input CLK,
        input RESETn
    );

endinterface