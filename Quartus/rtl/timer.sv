module timer(
    timer_if.subordinate tif,
    
    input logic psel,
    input logic pwrite,
    input logic [7:0] paddr,
    input logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic prdata_valid,
    output logic irq
);

    localparam logic [7:0] ADDR_LOAD = 8'h00;
    localparam logic [7:0] ADDR_COUNT = 8'h04;
    localparam logic [7:0] ADDR_CONTROL = 8'h08;
    localparam logic [7:0] ADDR_STATUS = 8'h0C;
    localparam logic [7:0] ADDR_PRESCALAR = 8'h10;
    

    logic [31:0] reg_load;
    logic [31:0] reg_count;
    logic [31:0] reg_control;
    logic [31:0] reg_status;
    logic [31:0] reg_prescalar;
    
    logic [31:0] pre_scalar_counter;

    typedef enum logic{
        IDLE = 0,
        COUNT = 1
    } timer_states;

    timer_states timer_state;

    logic enable;
    logic auto_reload;
    logic irq_en;

    assign enable = reg_control[0];
    assign auto_reload = reg_control[1];
    assign irq_en = reg_control[2];
    
    always_ff @(posedge tif.CLK or negedge tif.RESETn) begin
        if(!tif.RESETn) begin
            reg_load <= 0;
            reg_count <= 0;
            reg_control <= 0;
            reg_status <= 0;
            reg_prescalar <= 0;
            timer_state <= IDLE;
            pre_scalar_counter <= 0;
        end
        else begin
            if(psel && pwrite) begin
                case(paddr)
                    ADDR_LOAD: reg_load <= pwdata;
                    ADDR_CONTROL: reg_control <= pwdata;
                    ADDR_PRESCALAR: reg_prescalar <= pwdata; 
                    default: ;
                endcase
            end
            if(enable) begin
                if(timer_state == IDLE) begin
                    reg_count <= reg_load;
                    pre_scalar_counter <= reg_prescalar;
                    timer_state <= COUNT;
                end
            end
            else timer_state <= IDLE;

            if(psel && pwrite && (paddr == ADDR_STATUS)) begin
                reg_status <= reg_status & ~(pwdata);
                //$display("clearing with w1c: %d", $time);
            end

            if(timer_state == COUNT) begin
                if(pre_scalar_counter == 0) begin
                    tick_counter();
                    pre_scalar_counter <= reg_prescalar;
                end
                else pre_scalar_counter <= pre_scalar_counter - 1;
            end
        end
    end
    
    task tick_counter();
        if(reg_count == 0) begin
            reg_status[0] <= 1'b1;
            if(auto_reload) begin
                 reg_count <= reg_load;
            end
            else begin
                timer_state <= IDLE;
                reg_control[0] <= 0;
            end
        end
        else reg_count <= reg_count - 1;
    endtask


    always_comb begin
        prdata = 0;
        prdata_valid = 0;
        if(psel && !pwrite) begin
            prdata_valid = 1;
            case (paddr)
                ADDR_LOAD: prdata = reg_load;
                ADDR_COUNT: prdata = reg_count; 
                ADDR_CONTROL: prdata = reg_control;
                ADDR_STATUS: prdata = reg_status; 
                ADDR_PRESCALAR: prdata = reg_prescalar; 
                default: begin
                    prdata = 0;
                    prdata_valid = 0;
                end
            endcase
        end
    end
    assign irq = reg_status[0] & irq_en;
    
endmodule