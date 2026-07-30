module axi4lite_subordinate (
    axi4lite_if.subordinate axiif
);
    typedef enum logic [1:0] {w_req, w_dat, w_res} write_states;
    write_states write_state;
    logic [31:0] memory [255:0];
    logic [31:0] write_addr;
    //logic [31:0] strobe_vec;
    //assign strobe_vec = {8{axiif.WSTRB[3]}, 8{axiif.WSTRB[2]}, 8{axiif.WSTRB[1]}, 8{axiif.WSTRB[0]}};
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
        end
        else begin
            if(write_state == w_req & axiif.AWVALID) begin
                write_addr <= axiif.AWADDR;
                axiif.WREADY <= 1;
                axiif.AWREADY <= 0;
                write_state <= w_dat;
                
                `ifdef BUG_PREMATURE_BVALID
                    axiif.BVALID <=1;
                `endif
            end
            if(axiif.WVALID & axiif.WREADY) begin
                if(write_state == w_dat) begin
                    `ifndef BUG_DISABLE_WDAT
                        for(int i = 0; i < 4; i++) begin
                            if(axiif.WSTRB[i]) begin
                                memory[write_addr[9:2]][i*8 +: 8] <= axiif.WDATA[i*8 +: 8];
                            end
                        end
                    `endif
                    //memory[write_addr[9:2]] <= axiif.WDATA;
                end
                else begin
                    for(int i = 0; i < 4; i++) begin
                        if(axiif.WSTRB[i]) begin
                            memory[axiif.AWADDR[9:2]][i*8 +: 8] <= axiif.WDATA[i*8 +: 8];
                        end
                    end
                    //memory[axiif.AWADDR[9:2]] <= axiif.WDATA;
                end
                `ifdef BUG_DATA_CORRUPTION
                    memory[axiif.AWADDR[9:2]] <= axiif.WDATA ^ 32'h01010101;
                `endif
                axiif.WREADY <= 0;
                axiif.BVALID <= 1;
                axiif.BRESP <= 0;
                write_state <= w_res;
            end
            else if(write_state == w_res & axiif.BREADY) begin
                axiif.AWREADY <= 1;
                axiif.WREADY <= 1;
                axiif.BVALID <= 0;
                axiif.BRESP <= 0;
                write_addr <= 0;
                write_state <= w_req;
            end

            if(axiif.ARREADY & axiif.ARVALID & write_state == w_req) begin
                axiif.RDATA <= memory[axiif.ARADDR[9:2]];
                axiif.RVALID <= 1;
                axiif.ARREADY <= 0;
            end
            else if(axiif.RREADY & axiif.RVALID & write_state == w_req) begin
                axiif.ARREADY <= 1;
                axiif.RDATA <= 0;
                axiif.RVALID <= 0;
                axiif.RRESP <= 0;
            end
            `ifdef BUG_RVALID_UNSTABLE
                if(axiif.RVALID && !axiif.RREADY) begin
                    axiif.RVALID <= 0;
                end 
            `endif
        end
    end
endmodule