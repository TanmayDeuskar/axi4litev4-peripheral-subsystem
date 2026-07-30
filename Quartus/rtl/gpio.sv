module gpio(
    gpio_if.subordinate gpif,

    input logic psel,
    input logic pwrite,
    input logic [7:0] paddr,
    input logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic prdata_valid,
    output logic irq
    
);

logic [31:0] data_out_reg;
logic [31:0] direction;
logic [31:0] int_en_reg;
logic [31:0] int_status_reg;
logic [31:0] int_type_reg;
logic [31:0] int_polarity_reg;

localparam logic [7:0] ADDR_DATA_OUT = 8'h00;
localparam logic [7:0] ADDR_DATA_IN = 8'h04;
localparam logic [7:0] ADDR_DIRECTION = 8'h08;
localparam logic [7:0] ADDR_INT_EN = 8'h0C;
localparam logic [7:0] ADDR_INT_STATUS = 8'h10;
localparam logic [7:0] ADDR_INT_TYPE = 8'h14;
localparam logic [7:0] ADDR_INT_POLARITY = 8'h18;

always_ff @(posedge gpif.CLK or negedge gpif.RESETn) begin
    if(!gpif.RESETn) begin
        data_out_reg <= 0;
        direction <= 0;
        int_en_reg <= 0;
        //int_status_reg <= 0;
        int_type_reg <= 0;
        int_polarity_reg <= 0;
    end
    else if(psel && pwrite) begin
        case (paddr)
            ADDR_DATA_OUT: data_out_reg <= pwdata;
            ADDR_DIRECTION: direction <= pwdata;
            ADDR_INT_EN: int_en_reg <= pwdata;
            ADDR_INT_TYPE: int_type_reg <= pwdata;
            ADDR_INT_POLARITY: int_polarity_reg <= pwdata; 
            default:;
        endcase
    end
end

always_comb begin
    prdata = 0;
    prdata_valid = 0;
    if(psel && !pwrite) begin
        prdata_valid = 1;
        case (paddr)
            ADDR_DATA_OUT: prdata = data_out_reg;
            ADDR_DATA_IN: prdata = gpif.gpio_in;
            ADDR_DIRECTION: prdata = direction;
            ADDR_INT_EN: prdata = int_en_reg;
            ADDR_INT_STATUS: prdata = int_status_reg;
            ADDR_INT_TYPE: prdata = int_type_reg;
            ADDR_INT_POLARITY: prdata = int_polarity_reg; 
            default:begin
                        prdata = 0;
                        prdata_valid = 0;
                    end
        endcase
    end
end

logic [31:0] prev_gpio_state;
always_ff@(posedge gpif.CLK or negedge gpif.RESETn) begin
    if(!gpif.RESETn) begin
        prev_gpio_state <= 0;
    end
    else begin
        prev_gpio_state <= gpif.gpio_in;
    end
end

logic [31:0] posedge_det;
logic [31:0] negedge_det;
logic [31:0] edge_trig;
logic [31:0] level_trig;
logic [31:0] trig_sel;
logic [31:0] trig;

assign posedge_det = gpif.gpio_in & ~prev_gpio_state;
assign negedge_det = ~gpif.gpio_in & prev_gpio_state;
assign edge_trig = (int_polarity_reg & posedge_det) | (~(int_polarity_reg) & negedge_det);
assign level_trig = int_polarity_reg ~^ gpif.gpio_in;
assign trig_sel = (int_type_reg & edge_trig) | (~(int_type_reg) & level_trig);
assign trig = int_en_reg & trig_sel & ~(direction);

always_ff@(posedge gpif.CLK or negedge gpif.RESETn) begin
    if(!gpif.RESETn) begin
        int_status_reg <= 0;
    end
    else if(psel && pwrite && paddr == ADDR_INT_STATUS) begin
        int_status_reg <= (int_status_reg | trig) & ~pwdata;
    end
    else begin
        int_status_reg <= (int_status_reg | trig);
    end
end
assign gpif.gpio_out = data_out_reg;
assign gpif.gpio_oe  = direction;
assign irq = |int_status_reg;
    
endmodule