`timescale 1ns/1ps

module tb_direct;

    logic clk;
    logic reset;

    axi4lite_if axiif(.ACLK(clk), .ARESETn(reset));
    axi4lite_subordinate dut(.axiif(axiif));

    initial clk = 0;
    always #5 clk = !clk;

    initial begin 
        axiif.AWVALID <= 0;
        axiif.AWADDR <= 0;
        axiif.WVALID <= 0;
        axiif.WDATA <= 0;
        axiif.WSTRB <= 0;
        axiif.BREADY <= 0;

        axiif.ARVALID <= 0;
        axiif.ARADDR <= 0;
        axiif.RREADY <= 0;

        reset = 0;

        repeat(5) @(posedge clk);
        reset = 1;

        @(posedge clk);
        $display("Starting write");
        axiif.AWADDR <= 32'h10;
        axiif.AWVALID <= 1;
        axiif.WDATA <= 32'hDEADBEEF;
        axiif.WVALID <= 1;
        axiif.WSTRB <= 4'hF;
        axiif.BREADY <= 1;
       fork
            begin
                @(posedge clk iff axiif.AWREADY);
                axiif.AWVALID <= 0;
            end
            begin
                @(posedge clk iff axiif.WREADY);
                axiif.WVALID <= 0;
            end
        join

        @(posedge clk iff axiif.BVALID)
        $display("Done Writing");    
        axiif.BREADY <= 0;
        $display("Starting Read");
        axiif.ARVALID <= 1;
        axiif.ARADDR <= 32'h10;
        axiif.RREADY <= 1;
        @(posedge clk iff axiif.ARREADY);
        axiif.ARVALID <= 0;
        @(posedge clk iff axiif.RVALID) $display("Data is %h", axiif.RDATA);
        axiif.RREADY <= 0;

       // #100 $finish;
    end

endmodule

