module fifo #(
    parameter int DEPTH = 256
) (
    fifo_if.subordinate fifoif,
    
    input logic psel,
    input logic pwrite,
    input logic [7:0] paddr,
    input logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic prdata_valid,
    output logic irq
);

    localparam ptr_width = $clog2(DEPTH);//4 bits
    
    localparam [7:0] ADDR_WDATA = 8'h00;
    localparam [7:0] ADDR_RDATA = 8'h04;
    localparam [7:0] ADDR_STATUS = 8'h08;
    localparam [7:0] ADDR_DEPTH = 8'h0C;
    localparam [7:0] ADDR_THRESH = 8'h10;
    localparam [7:0] ADDR_CONTROL = 8'h14;


     
    logic [31:0] memory [DEPTH-1:0];
    logic [31:0] control;
    logic [ptr_width-1:0] wptr;
    logic [ptr_width-1:0] rptr;
    logic [ptr_width:0] fill;
    logic [ptr_width:0] thresh;
    logic int_en;
    logic full;
    logic empty;

    logic rd_req, rd_req_prev;
    assign rd_req = psel && !pwrite && (paddr == ADDR_RDATA);



    assign full = (fill == DEPTH);
    assign empty = (fill == 0);
    assign int_en = control[0];

    always_ff @(posedge fifoif.CLK or negedge fifoif.RESETn) begin
        if(!fifoif.RESETn) begin
            //for (int i = 0; i < DEPTH; i++) memory[i] <= 0;
            wptr <= 0;
            rptr <= 0;
            fill <= 0;
            thresh <= DEPTH;
            control <= 0;
            prdata_valid <= 0;

        end
        else begin
            prdata_valid <= 0;
            rd_req_prev <= rd_req;
            if(psel && pwrite) begin
                if(paddr == ADDR_THRESH) begin
                    thresh <= pwdata[ptr_width:0];
                end
                else if(paddr == ADDR_CONTROL) control <= pwdata;
                else if(paddr == ADDR_WDATA) begin
                    if(fill < DEPTH) begin
                        memory[wptr] <= pwdata;
                        wptr <= ptr_width'(wptr + 1);
                        fill <= ptr_width'(fill + 1);
                    end
                end
            end
            else if(psel && !pwrite) begin
                prdata_valid <= 1;
                if(rd_req && !rd_req_prev) begin
                    if(!empty) begin
                        prdata <= memory[rptr];
                        rptr <= ptr_width'(rptr+1);
                        fill <= fill-{{ptr_width{1'b0}}, 1'b1};
                    end
                    else begin
                        prdata <= 0;
                    end
                end
                else if(paddr == ADDR_STATUS) begin
                    prdata <= {29'h0, fill >= thresh, (empty == 1), (full == 1)};
                end
                else if(paddr == ADDR_DEPTH) begin
                    prdata <= DEPTH;
                end
                else if (paddr == ADDR_THRESH) begin
                  prdata <= {{(31-ptr_width){1'b0}}, thresh};
                end
                else if (paddr == ADDR_CONTROL) begin
                    prdata <= control;
                end
            end
        end
    end

    assign irq = (fill >= thresh) && int_en;
    
endmodule