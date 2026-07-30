module axi4lite_assertions;
    logic aw_handshake_done, w_handshake_done, ar_handshake_done;

    always_ff @(posedge axiif.ACLK or negedge axiif.ARESETn) begin
        if(!axiif.ARESETn) begin
            aw_handshake_done = 0;
            w_handshake_done = 0;
            ar_handshake_done = 0;
        end
        else begin
            if(axiif.AWREADY && axiif.AWVALID) aw_handshake_done <= 1;
            if(axiif.WREADY && axiif.WVALID) w_handshake_done <= 1;
            if(axiif.BREADY && axiif.BVALID) begin
                aw_handshake_done <= 0;
                w_handshake_done <= 0;
            end
            if(axiif.ARREADY && axiif.ARVALID) ar_handshake_done <= 1;
            if(axiif.RVALID && axiif.RREADY) begin
                ar_handshake_done <= 0;
            end
            
            
        end
    end

    property bvalid_needs_aw_w;
        @(posedge axiif.ACLK) disable iff(!axiif.ARESETn)
        (axiif.BVALID) |-> (aw_handshake_done || (axiif.AWREADY && axiif.AWVALID)) && (w_handshake_done || (axiif.WREADY && axiif.WVALID));
    endproperty
    assert property(bvalid_needs_aw_w)
        else $error("BVALID asserted before AW and W handshakes");

    property wvalid_needs_aw;
        @(posedge axiif.ACLK) disable iff(!axiif.ARESETn)
        (axiif.WVALID) |-> (aw_handshake_done || (axiif.AWREADY && axiif.AWVALID));
    endproperty
    assert property(wvalid_needs_aw)
        else $error("WVALID asserted before AW handshake");

    property rvalid_needs_ar;
        @(posedge axiif.ACLK) disable iff(!axiif.ARESETn)
        (axiif.RVALID) |-> (ar_handshake_done || (axiif.ARREADY && axiif.ARVALID));
    endproperty
    assert property(rvalid_needs_ar)
        else $error("RVALID asserted before AR handshake");

    property write_addr_aligned;
        @(posedge axiif.ACLK) disable iff(!axiif.ARESETn)
        (axiif.AWVALID) |-> axiif.AWADDR[1:0] == 2'b00;
    endproperty
    assert property(write_addr_aligned)
        else $error("AWADDR not word aligned: %0h", axiif.AWADDR);

    property read_addr_aligned;
        @(posedge axiif.ACLK) disable iff(!axiif.ARESETn)
        (axiif.ARVALID) |-> axiif.ARADDR[1:0] == 2'b00;
    endproperty
    assert property(read_addr_aligned)
        else $error("ARADDR not word aligned: %0h", axiif.ARADDR);

    property aw_valid_stable;
        @(posedge axiif.ACLK) disable iff(!axiif.ARESETn)
        (axiif.AWVALID && !axiif.AWREADY) |=> axiif.AWVALID;
    endproperty
    assert property(aw_valid_stable)
        else $error("AWVALID dropped before handshake completed");

    property w_valid_stable;
        @(posedge axiif.ACLK) disable iff(!axiif.ARESETn)
        (axiif.WVALID && !axiif.WREADY) |=> axiif.WVALID;
    endproperty
    assert property(w_valid_stable)
        else $error("WVALID dropped before handshake completed");

    property ar_valid_stable;
        @(posedge axiif.ACLK) disable iff(!axiif.ARESETn)
        (axiif.ARVALID && !axiif.ARREADY) |=> axiif.ARVALID;
    endproperty
    assert property(ar_valid_stable)
        else $error("ARVALID dropped before handshake completed");

    property r_valid_stable;
        @(posedge axiif.ACLK) disable iff(!axiif.ARESETn)
        (axiif.RVALID && !axiif.RREADY) |=> axiif.RVALID;
    endproperty
    assert property(r_valid_stable)
        else $error("RVALID dropped before handshake completed");

    property b_valid_stable;
        @(posedge axiif.ACLK) disable iff(!axiif.ARESETn)
        (axiif.BVALID && !axiif.BREADY) |=> axiif.BVALID;
    endproperty
    assert property(b_valid_stable)
        else $error("BVALID dropped before handshake completed");

    property strobe_non_zero;
        @(posedge axiif.ACLK) disable iff(!axiif.ARESETn)
        (axiif.WVALID) |-> axiif.WSTRB > 0;
    endproperty
    assert property(strobe_non_zero)
        else $error("WSTRB is zero when WVALID is asserted");

    property aw_handshake_timeout;
        @(posedge axiif.ACLK) disable iff(!axiif.ARESETn)
        (axiif.AWVALID) |-> ##[0:20] axiif.AWREADY;
    endproperty
    assert property(aw_handshake_timeout)
        else $error("AWREADY did not arrive within 20 cycles");

    property w_handshake_timeout;
        @(posedge axiif.ACLK) disable iff(!axiif.ARESETn)
        (axiif.WVALID) |-> ##[0:20] axiif.WREADY;
    endproperty
    assert property(w_handshake_timeout)
        else $error("WREADY did not arrive within 20 cycles");
    
    property ar_handshake_timeout;
        @(posedge axiif.ACLK) disable iff(!axiif.ARESETn)
        (axiif.ARVALID) |-> ##[0:20] axiif.ARREADY;
    endproperty
    assert property(ar_handshake_timeout)
        else $error("ARREADY did not arrive within 20 cycles");

    property r_handshake_timeout;
        @(posedge axiif.ACLK) disable iff(!axiif.ARESETn)
        (axiif.RVALID) |-> ##[0:20] axiif.RREADY;
    endproperty
    assert property(r_handshake_timeout)
        else $error("RREADY did not arrive within 20 cycles");

    property b_handshake_timeout;
        @(posedge axiif.ACLK) disable iff(!axiif.ARESETn)
        (axiif.BVALID) |-> ##[0:20] axiif.BREADY;
    endproperty
    assert property(b_handshake_timeout)
        else $error("BREADY did not arrive within 20 cycles");

endmodule