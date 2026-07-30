module axi4lite_wrapper (
    axi4lite_if.subordinate axiif,
    input logic [31:0] prdata,
    input logic prdata_valid,
    output logic psel,
    output logic pwrite,
    output logic [31:0] paddr,
    output logic [31:0] pwdata
);

    typedef enum logic [1:0] {w_req, w_dat, w_res} write_states;
    typedef enum logic [1:0] {r_req, r_dat, r_res} read_states;

    write_states write_state;
    read_states read_state;
    //logic [31:0] write_addr;

    always_ff @(posedge axiif.ACLK or negedge axiif.ARESETn) begin
        if (!axiif.ARESETn) begin
            axiif.AWREADY <= 1;
            axiif.WREADY <= 1;
            axiif.BVALID <= 0;
            axiif.BRESP <= 0;
            write_state <= w_req;

            axiif.ARREADY <= 1;
            axiif.RVALID <= 0;
            axiif.RDATA <= 0;
            axiif.RRESP <= 0;
            read_state <= r_req;

            psel <= 0;
            pwrite <= 0;
            pwdata <= 0;
            paddr <= 0;
        end
        else begin
            if(write_state == w_req & axiif.AWVALID) begin
               // write_addr <= axiif.AWADDR;
                axiif.WREADY <= 1;
                axiif.AWREADY <= 0;
                write_state <= w_dat;              
                //pwrite <= 1;
                paddr <= axiif.AWADDR;
            end
            if(axiif.WVALID & axiif.WREADY) begin
                psel <= 1;
                pwrite <= 1;
                pwdata <= axiif.WDATA;
                axiif.WREADY <= 0;
                axiif.BVALID <= 1;
                axiif.BRESP <= 0;
                write_state <= w_res;
            end
            else if(write_state == w_res) begin
                psel <= 0;
                pwrite <= 0;
                if(axiif.BREADY) begin
                    axiif.AWREADY <= 1;
                    axiif.WREADY <= 1;
                    axiif.BVALID <= 0;
                    axiif.BRESP <= 0;
                    write_state <= w_req;
                end
            end


            if(write_state == w_req) begin
                case (read_state)
                    r_req: begin
                        if(axiif.ARREADY & axiif.ARVALID) begin
                            paddr <= axiif.ARADDR;
                            psel <= 1;
                            pwrite <= 0;
                            axiif.ARREADY <= 0;
                            read_state <= r_dat;
                        end
                    end
                    r_dat: begin
                        if(prdata_valid) begin
                            axiif.RVALID <= 1;
                            axiif.RDATA <= prdata;
                            read_state <= r_res;
                            psel <= 0;
                        end
                    end 
                    r_res: begin
                        if(axiif.RREADY & axiif.RVALID) begin
                            axiif.ARREADY <= 1;
                            axiif.RDATA <= 0;
                            axiif.RVALID <= 0;
                            axiif.RRESP <= 0;
                            read_state <= r_req;
                        end
                    end
                    default: begin
                        psel <= 0;
                        paddr <= 0;
                        pwrite <= 0;
                        read_state <= r_req;
                    end
                endcase
            end
        end
    end




endmodule