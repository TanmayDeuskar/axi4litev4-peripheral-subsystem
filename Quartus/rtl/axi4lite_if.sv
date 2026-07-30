interface axi4lite_if(input logic ACLK, input logic ARESETn);
    
        logic AWREADY;
        logic WVALID;
        logic BVALID;

        logic ARREADY;
        logic RVALID;
        logic [31:0] RDATA;
        logic [1:0] RRESP;

        
        logic AWVALID;
        logic [31:0] AWADDR;
        logic  WREADY;
        logic [31:0] WDATA;
        logic [3:0] WSTRB;
        logic BREADY;
        logic [1:0] BRESP;

        logic ARVALID;
        logic [31:0] ARADDR;
        logic RREADY;

    modport controller (
        input ACLK,
        input ARESETn,
        input AWREADY,
        input WREADY,
        input BVALID,

        input ARREADY,
        input RVALID,
        input RDATA,
        input RRESP,
        input BRESP,

        
        output AWVALID,
        output AWADDR,
        output WVALID,
        output WDATA,
        output WSTRB,
        output BREADY,

        output ARVALID,
        output ARADDR,
        output RREADY
    );

    modport subordinate (
        input ACLK,
        input ARESETn,
        input AWVALID,
        input AWADDR,
        input WVALID,
        input WDATA,
        input WSTRB,
        input BREADY,

        input ARVALID,
        input ARADDR,
        input RREADY,

        output AWREADY,
        output WREADY,
        output BVALID,
        output BRESP,

        output ARREADY,
        output RVALID,
        output RDATA,
        output RRESP

    );

endinterface //axi4lite_if(input logic ACLK, input logic ARESETn)
