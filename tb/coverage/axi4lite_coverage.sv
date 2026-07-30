class axi4lite_coverage extends uvm_subscriber #(axi4lite_seq_item);
    `uvm_component_utils(axi4lite_coverage)

    // Mirrors axi4lite_scoreboard.sv address map exactly
    localparam logic [31:0] GPIO_BASE  = 32'h000;
    localparam logic [31:0] TIMER_BASE = 32'h100;
    localparam logic [31:0] FIFO_BASE  = 32'h200;
    localparam logic [31:0] FIFO_END   = FIFO_BASE + 32'h100;

    int unsigned pass_count;
    int unsigned fail_count;

    // Per-peripheral write/read bins — replaces the old flat low/mid/high
    // address-range bins, which were built for Project 1's single 256-word
    // memory map and didn't correspond to anything meaningful here.
    int unsigned bin_write_gpio, bin_write_timer, bin_write_fifo;
    int unsigned bin_read_gpio,  bin_read_timer,  bin_read_fifo;
    int unsigned bin_unmapped;

    int unsigned bin_full_word, bin_lower_half, bin_upper_half, bin_single_byte, bin_other_strobe;

    int unsigned resp_ok, resp_exok, resp_slverr, resp_decerr;

    function new(string name = "axi4lite_coverage", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void write(axi4lite_seq_item t);
        track_coverage(t);
    endfunction

    function void track_coverage(axi4lite_seq_item seq_item);
        logic [31:0] addr = seq_item.addr;

        if (seq_item.write) begin
            if      (addr >= GPIO_BASE  && addr < TIMER_BASE) bin_write_gpio++;
            else if (addr >= TIMER_BASE && addr < FIFO_BASE)  bin_write_timer++;
            else if (addr >= FIFO_BASE  && addr < FIFO_END)   bin_write_fifo++;
            else                                              bin_unmapped++;

            case (seq_item.strobe)
                4'b1111: bin_full_word++;
                4'b1100: bin_upper_half++;
                4'b0011: bin_lower_half++;
                4'b0001, 4'b0010, 4'b0100, 4'b1000: bin_single_byte++;
                default: bin_other_strobe++;
            endcase
        end
        else begin
            if      (addr >= GPIO_BASE  && addr < TIMER_BASE) bin_read_gpio++;
            else if (addr >= TIMER_BASE && addr < FIFO_BASE)  bin_read_timer++;
            else if (addr >= FIFO_BASE  && addr < FIFO_END)   bin_read_fifo++;
            else                                              bin_unmapped++;
        end

        case (seq_item.resp)
            2'b00: resp_ok++;
            2'b01: resp_exok++;
            2'b10: resp_slverr++;
            2'b11: resp_decerr++;
        endcase
    endfunction

    function void report_phase(uvm_phase phase);
        int unsigned total_bins, hit_bins;

        `uvm_info("COVERAGE", "=== Per-Peripheral Address Coverage ===", UVM_NONE)
        `uvm_info("COVERAGE", $sformatf("Write - GPIO: %0d, Timer: %0d, FIFO: %0d, Unmapped: %0d",
                  bin_write_gpio, bin_write_timer, bin_write_fifo, bin_unmapped), UVM_NONE)
        `uvm_info("COVERAGE", $sformatf("Read  - GPIO: %0d, Timer: %0d, FIFO: %0d",
                  bin_read_gpio, bin_read_timer, bin_read_fifo), UVM_NONE)

        `uvm_info("COVERAGE", "=== Strobe Bin Coverage ===", UVM_NONE)
        `uvm_info("COVERAGE", $sformatf(
            "full_word: %0d, lower_half: %0d, upper_half: %0d, single_byte: %0d, other: %0d",
            bin_full_word, bin_lower_half, bin_upper_half, bin_single_byte, bin_other_strobe), UVM_NONE)

        `uvm_info("COVERAGE", "=== Response Code Coverage ===", UVM_NONE)
        `uvm_info("COVERAGE", $sformatf(
            "OKAY: %0d, EXOKAY: %0d, SLVERR: %0d, DECERR: %0d",
            resp_ok, resp_exok, resp_slverr, resp_decerr), UVM_NONE)

        total_bins = 10;
        hit_bins = (bin_write_gpio>0) + (bin_write_timer>0) + (bin_write_fifo>0) +
                   (bin_read_gpio>0)  + (bin_read_timer>0)  + (bin_read_fifo>0)  +
                   (bin_full_word>0) + (bin_lower_half>0) + (bin_upper_half>0) + (bin_single_byte>0);

        `uvm_info("COVERAGE", $sformatf(
            "TOTAL FUNCTIONAL COVERAGE: %0d/%0d bins = %0.1f%%",
            hit_bins, total_bins, (hit_bins*100.0)/total_bins), UVM_NONE)

        if (bin_write_gpio  == 0) `uvm_warning("COVERAGE", "BIN MISS: GPIO write never hit")
        if (bin_write_timer == 0) `uvm_warning("COVERAGE", "BIN MISS: Timer write never hit")
        if (bin_write_fifo  == 0) `uvm_warning("COVERAGE", "BIN MISS: FIFO write never hit")
        if (bin_read_gpio   == 0) `uvm_warning("COVERAGE", "BIN MISS: GPIO read never hit")
        if (bin_read_timer  == 0) `uvm_warning("COVERAGE", "BIN MISS: Timer read never hit")
        if (bin_read_fifo   == 0) `uvm_warning("COVERAGE", "BIN MISS: FIFO read never hit")
        if (bin_full_word   == 0) `uvm_warning("COVERAGE", "BIN MISS: full word strobe never hit")
        if (bin_lower_half  == 0) `uvm_warning("COVERAGE", "BIN MISS: lower half strobe never hit")
        if (bin_upper_half  == 0) `uvm_warning("COVERAGE", "BIN MISS: upper half strobe never hit")
        if (bin_single_byte == 0) `uvm_warning("COVERAGE", "BIN MISS: single byte strobe never hit")
        if (resp_ok         == 0) `uvm_warning("COVERAGE", "BIN MISS: OKAY response never observed")
        if (resp_exok       == 0) `uvm_warning("COVERAGE", "BIN MISS: EXOKAY response never observed")
        if (resp_slverr     == 0) `uvm_warning("COVERAGE", "BIN MISS: SLVERR response never observed")
        if (resp_decerr     == 0) `uvm_warning("COVERAGE", "BIN MISS: DECERR response never observed")
    endfunction
endclass