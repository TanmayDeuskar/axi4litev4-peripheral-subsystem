`ifndef AXI4LITE_SCOREBOARD_SV
`define AXI4LITE_SCOREBOARD_SV


import uvm_pkg::*;
`include "uvm_macros.svh"


`uvm_analysis_imp_decl(_gpio)
`uvm_analysis_imp_decl(_irq)


localparam logic [31:0] GPIO_BASE = 32'h000;
localparam logic [31:0] TIMER_BASE = 32'h100;
localparam logic [31:0] FIFO_BASE = 32'h200;

localparam logic [31:0] GPIO_ADDR_DATA_OUT = GPIO_BASE + 32'h00;
localparam logic [31:0] GPIO_ADDR_DATA_IN = GPIO_BASE + 32'h04;
localparam logic [31:0] GPIO_ADDR_DIRECTION = GPIO_BASE + 32'h08;
localparam logic [31:0] GPIO_ADDR_INT_EN = GPIO_BASE + 32'h0C;
localparam logic [31:0] GPIO_ADDR_INT_STATUS = GPIO_BASE + 32'h10;
localparam logic [31:0] GPIO_ADDR_INT_TYPE = GPIO_BASE + 32'h14;
localparam logic [31:0] GPIO_ADDR_INT_POLARITY = GPIO_BASE + 32'h18;

localparam logic [31:0] TIMER_ADDR_LOAD = TIMER_BASE + 32'h00;
localparam logic [31:0] TIMER_ADDR_COUNT = TIMER_BASE + 32'h04;
localparam logic [31:0] TIMER_ADDR_CONTROL = TIMER_BASE + 32'h08;
localparam logic [31:0] TIMER_ADDR_STATUS = TIMER_BASE + 32'h0C;
localparam logic [31:0] TIMER_ADDR_PRESCALAR = TIMER_BASE + 32'h10;

localparam logic [31:0] FIFO_ADDR_WDATA = FIFO_BASE + 32'h00;
localparam logic [31:0] FIFO_ADDR_RDATA = FIFO_BASE + 32'h04;
localparam logic [31:0] FIFO_ADDR_STATUS = FIFO_BASE + 32'h08;
localparam logic [31:0] FIFO_ADDR_DEPTH = FIFO_BASE + 32'h0C;
localparam logic [31:0] FIFO_ADDR_THRESH = FIFO_BASE + 32'h10;
localparam logic [31:0] FIFO_ADDR_CONTROL = FIFO_BASE + 32'h14;

localparam int FIFO_DEPTH = 16;   

localparam int GPIO_IRQ_BIT = 0;
localparam int TIMER_IRQ_BIT = 1;
localparam int FIFO_IRQ_BIT = 2;

// Timer IRQ timing tolerance — absorbs the fixed ~1-2 cycle offset between

localparam int TIMER_IRQ_WINDOW_CYCLES = 3;
localparam time CLK_PERIOD = 10ns;  // TB clock

typedef enum logic {
    TIMER_IDLE = 1'b0,
    TIMER_COUNT = 1'b1
} timer_fsm_state_e;


typedef struct {
    logic [31:0] data_out;
    logic [31:0] direction;
    logic [31:0] int_en;
    logic [31:0] int_status;
    logic [31:0] int_type;
    logic [31:0] int_polarity;
} gpio_shadow_t;

typedef struct {
    logic [31:0] load;
    logic [31:0] control;
    logic [31:0] status;
    logic [31:0] prescalar;
    logic [31:0] count;
    logic [31:0] pre_scalar_counter;
    timer_fsm_state_e state;
} timer_shadow_t;

typedef struct {
    logic [31:0] thresh;
    logic [31:0] control;
    int unsigned fill;
} fifo_shadow_t;

class axi4lite_scoreboard extends uvm_subscriber #(axi4lite_seq_item);
    `uvm_component_utils(axi4lite_scoreboard)

    uvm_analysis_imp_gpio #(gpio_transaction, axi4lite_scoreboard) gpio_imp;
    uvm_analysis_imp_irq #(irq_transaction, axi4lite_scoreboard) irq_imp;

    virtual axi4lite_if vif;

    
    gpio_shadow_t gpio_shadow;
    timer_shadow_t timer_shadow;
    fifo_shadow_t fifo_shadow;

    logic [31:0] fifo_ref_q[$];
    time timer_ctrl_write_time;
    bit timer_overflow_this_cycle;

    int unsigned error_count;
    int unsigned check_count;

    function new(string name = "axi4lite_scoreboard", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        gpio_imp = new("gpio_imp", this);
        irq_imp = new("irq_imp", this);
        if (!uvm_config_db#(virtual axi4lite_if)::get(this, "", "vif", vif))
            `uvm_fatal("SCOREBOARD", "Could not get virtual axi4lite_if from config db")
        error_count = 0;
        check_count = 0;
        timer_ctrl_write_time = 0;
        timer_overflow_this_cycle = 0;
        reset_all_shadows();
    endfunction

    function void reset_all_shadows();
        gpio_shadow.data_out = '0;
        gpio_shadow.direction = '0;
        gpio_shadow.int_en = '0;
        gpio_shadow.int_status = '0;
        gpio_shadow.int_type = '0;
        gpio_shadow.int_polarity = '0;

        timer_shadow.load = '0;
        timer_shadow.control = '0;
        timer_shadow.status = '0;
        timer_shadow.prescalar = '0;
        timer_shadow.count = '0;
        timer_shadow.pre_scalar_counter = '0;
        timer_shadow.state = TIMER_IDLE;

        fifo_shadow.thresh = FIFO_DEPTH;
        fifo_shadow.control = '0;
        fifo_shadow.fill = 0;
        fifo_ref_q.delete();
    endfunction

   
    task run_phase(uvm_phase phase);
        fork
            timer_fsm_process();
        join_none
    endtask

    task timer_fsm_process();
        forever begin
            @(posedge vif.ACLK);
            timer_overflow_this_cycle = 0;  // clear flag at start of each cycle
            if (!vif.ARESETn)
                reset_all_shadows();
            else
                tick_timer_model();
        end
    endtask

    function void tick_timer_model();
        logic enable = timer_shadow.control[0];

        if (enable) begin
            if (timer_shadow.state == TIMER_IDLE) begin
                timer_shadow.count = timer_shadow.load;
                timer_shadow.pre_scalar_counter = timer_shadow.prescalar;
                timer_shadow.state = TIMER_COUNT;
                return;
            end
        end else begin
            timer_shadow.state = TIMER_IDLE;
        end

        if (timer_shadow.state == TIMER_COUNT) begin
            if (timer_shadow.pre_scalar_counter == 0) begin
                tick_counter_model();
                timer_shadow.pre_scalar_counter = timer_shadow.prescalar;
            end else begin
                timer_shadow.pre_scalar_counter--;
            end
        end
    endfunction

    function void tick_counter_model();
        logic auto_reload = timer_shadow.control[1];

        if (timer_shadow.count == 0) begin
            timer_shadow.status[0] = 1'b1;
            timer_overflow_this_cycle = 1;     

            if (auto_reload) begin
                timer_shadow.count = timer_shadow.load;
            end else begin
                timer_shadow.state = TIMER_IDLE;
                timer_shadow.control[0] = 1'b0;
            end
        end else begin
            timer_shadow.count--;
        end
    endfunction


    function void write(axi4lite_seq_item t);
        if(t.addr >= GPIO_BASE  && t.addr < TIMER_BASE) handle_gpio(t);
        else if(t.addr >= TIMER_BASE && t.addr < FIFO_BASE) handle_timer(t);
        else if(t.addr >= FIFO_BASE  && t.addr < (FIFO_BASE + 32'h100)) handle_fifo(t);
        else
            `uvm_warning("SCOREBOARD",
                $sformatf("Transaction to unmapped addr 0x%0h ignored", t.addr))
    endfunction

    function void write_gpio(gpio_transaction t);
        check_count += 2;
        if (t.gpio_out !== gpio_shadow.data_out)
            flag_error("SCOREBOARD_GPIO",
                $sformatf("gpio_out mismatch: expected=0x%0h got=0x%0h @%0t",
                           gpio_shadow.data_out, t.gpio_out, t.timestamp));
        if (t.gpio_oe !== gpio_shadow.direction)
            flag_error("SCOREBOARD_GPIO",
                $sformatf("gpio_oe mismatch: expected=0x%0h got=0x%0h @%0t",
                           gpio_shadow.direction, t.gpio_oe, t.timestamp));
    endfunction

    function void write_irq(irq_transaction t);
        if (!t.irq_value) begin
            //$display("deasserted");
            `uvm_info("SCOREBOARD_IRQ",
                $sformatf("IRQ deasserted irq_status=0b%03b @%0t",
                           t.irq_status, t.timestamp), UVM_MEDIUM)
            return;
        end

        `uvm_info("SCOREBOARD_IRQ",
            $sformatf("IRQ asserted irq_status=0b%03b @%0t",
                       t.irq_status, t.timestamp), UVM_MEDIUM)

    
        if (t.irq_status[GPIO_IRQ_BIT]) begin
            check_count++;
            if (gpio_shadow.int_en == '0)
                flag_error("SCOREBOARD_GPIO_IRQ",
                    $sformatf("GPIO IRQ asserted but int_en=0 @%0t", t.timestamp));
            else
                `uvm_info("SCOREBOARD_GPIO_IRQ",
                    $sformatf("GPIO IRQ: int_en=0x%0h @%0t",
                               gpio_shadow.int_en, t.timestamp), UVM_MEDIUM)
        end

        
        if (t.irq_status[TIMER_IRQ_BIT]) begin
            check_count++;
            begin
                time actual_period;
                time expected_period;
                time diff;
                time window;

                actual_period = t.timestamp - timer_ctrl_write_time;
                expected_period = CLK_PERIOD *
                                  ((timer_shadow.load + 1) *
                                   (timer_shadow.prescalar + 1));
                diff = (actual_period > expected_period) ?
                         (actual_period - expected_period) :
                         (expected_period - actual_period);
                window = TIMER_IRQ_WINDOW_CYCLES * CLK_PERIOD;

                if (diff > window)
                    flag_error("SCOREBOARD_TIMER",
                        $sformatf(
                            "Timer IRQ timing FAIL: actual=%0t expected=%0t diff=%0t load=%0d prescalar=%0d @%0t",
                            actual_period, expected_period, diff,
                            timer_shadow.load, timer_shadow.prescalar,
                            t.timestamp));
                else begin
                    `uvm_info("SCOREBOARD_TIMER",
                        $sformatf(
                            "Timer IRQ timing PASS: actual=%0t expected=%0t diff=%0t @%0t",
                            actual_period, expected_period, diff, t.timestamp),
                        UVM_MEDIUM)
                    check_count++;
                end
                timer_ctrl_write_time = $time;
            end
        end

        if (t.irq_status[FIFO_IRQ_BIT]) begin
            check_count++;
            if (!((fifo_shadow.fill >= fifo_shadow.thresh) &&
                   fifo_shadow.control[0]))
                flag_error("SCOREBOARD_FIFO_IRQ",
                    $sformatf(
                        "FIFO IRQ asserted but fill=%0d thresh=%0d int_en=%0b @%0t",
                        fifo_shadow.fill, fifo_shadow.thresh,
                        fifo_shadow.control[0], t.timestamp));
            else
                `uvm_info("SCOREBOARD_FIFO_IRQ",
                    $sformatf("FIFO IRQ PASS: fill=%0d >= thresh=%0d int_en=%0b @%0t",
                               fifo_shadow.fill, fifo_shadow.thresh,
                               fifo_shadow.control[0], t.timestamp), UVM_MEDIUM)
        end
    endfunction

   
    function void handle_gpio(axi4lite_seq_item t);
        if (t.write) begin
            case (t.addr)
                GPIO_ADDR_DATA_OUT:
                    gpio_shadow.data_out = t.data;
                GPIO_ADDR_DIRECTION:
                    gpio_shadow.direction = t.data;
                GPIO_ADDR_INT_EN:
                    gpio_shadow.int_en = t.data;
                GPIO_ADDR_INT_TYPE:
                    gpio_shadow.int_type = t.data;
                GPIO_ADDR_INT_POLARITY:
                    gpio_shadow.int_polarity = t.data;
                GPIO_ADDR_INT_STATUS:
                    gpio_shadow.int_status = gpio_shadow.int_status & ~t.data;
                default:
                    `uvm_warning("SCOREBOARD_GPIO",
                        $sformatf("Write to unmapped GPIO addr 0x%0h", t.addr))
            endcase
        end else begin
            check_count++;
            case (t.addr)
                GPIO_ADDR_DATA_OUT:
                    check_field("GPIO_DATA_OUT", gpio_shadow.data_out, t.data);
                GPIO_ADDR_DIRECTION:
                    check_field("GPIO_DIRECTION", gpio_shadow.direction, t.data);
                GPIO_ADDR_INT_EN:
                    check_field("GPIO_INT_EN", gpio_shadow.int_en, t.data);
                GPIO_ADDR_INT_TYPE:
                    check_field("GPIO_INT_TYPE", gpio_shadow.int_type, t.data);
                GPIO_ADDR_INT_POLARITY:
                    check_field("GPIO_INT_POLARITY", gpio_shadow.int_polarity, t.data);
                GPIO_ADDR_DATA_IN:
                    ;  // physical pin state
                GPIO_ADDR_INT_STATUS:
                    ;  // needs gpio_in edge tracking
                default:
                    `uvm_warning("SCOREBOARD_GPIO",
                        $sformatf("Read from unmapped GPIO addr 0x%0h", t.addr))
            endcase
        end
    endfunction

    function void handle_timer(axi4lite_seq_item t);
        if (t.write) begin
            case (t.addr)
                TIMER_ADDR_LOAD:
                    timer_shadow.load = t.data;
                TIMER_ADDR_PRESCALAR:
                    timer_shadow.prescalar = t.data;
                TIMER_ADDR_CONTROL: begin
                    timer_shadow.control = t.data;
                    if (t.data[0])  // enable bit set
                        timer_ctrl_write_time = t.timestamp;
                end
                TIMER_ADDR_STATUS: begin
                    
                    if (timer_overflow_this_cycle)
                        timer_shadow.status = timer_shadow.status;
                    else
                        timer_shadow.status = timer_shadow.status & ~t.data;
                end
                default:
                    `uvm_warning("SCOREBOARD_TIMER",
                        $sformatf("Write to unmapped Timer addr 0x%0h", t.addr))
            endcase
        end else begin
            check_count++;
            case (t.addr)
                TIMER_ADDR_LOAD:
                    check_field("TIMER_LOAD", timer_shadow.load, t.data);
                TIMER_ADDR_PRESCALAR:
                    check_field("TIMER_PRESCALAR", timer_shadow.prescalar, t.data);
                TIMER_ADDR_COUNT:
                    check_field("TIMER_COUNT", timer_shadow.count, t.data);
                TIMER_ADDR_STATUS:
                    check_field("TIMER_STATUS", timer_shadow.status, t.data);
                TIMER_ADDR_CONTROL:
                    check_field("TIMER_CONTROL", timer_shadow.control, t.data);
                default:
                    `uvm_warning("SCOREBOARD_TIMER",
                        $sformatf("Read from unmapped Timer addr 0x%0h", t.addr))
            endcase
        end
    endfunction

    function void handle_fifo(axi4lite_seq_item t);
        if (t.write) begin
            case (t.addr)
                FIFO_ADDR_THRESH:
                    fifo_shadow.thresh = t.data;
                FIFO_ADDR_CONTROL:
                    fifo_shadow.control = t.data;
                FIFO_ADDR_WDATA: begin
                    if (fifo_shadow.fill < FIFO_DEPTH) begin
                        fifo_ref_q.push_back(t.data);
                        fifo_shadow.fill++;
                    end else begin
                        
                        flag_error("SCOREBOARD_FIFO",
                            $sformatf(
                                "WDATA pushed while shadow fill=%0d (DEPTH=%0d) data=0x%0h",
                                fifo_shadow.fill, FIFO_DEPTH, t.data));
                    end
                end
                default:
                    `uvm_warning("SCOREBOARD_FIFO",
                        $sformatf("Write to unmapped FIFO addr 0x%0h", t.addr))
            endcase
        end else begin
            check_count++;
            case (t.addr)
                FIFO_ADDR_RDATA: begin
                    if (fifo_ref_q.size() == 0) begin
                        if (t.data !== 32'h0)
                            flag_error("SCOREBOARD_FIFO",
                                $sformatf(
                                    "RDATA from empty FIFO: expected 0x0 got 0x%0h",
                                    t.data));
                    end else begin
                        logic [31:0] expected;
                        expected = fifo_ref_q.pop_front();
                        fifo_shadow.fill--;
                        if (t.data !== expected)
                            flag_error("SCOREBOARD_FIFO",
                                $sformatf(
                                    "FIFO order mismatch: expected=0x%0h got=0x%0h",
                                    expected, t.data));
                    end
                end
                FIFO_ADDR_STATUS: begin
                    logic [31:0] exp_status;
                    bit full_b = (fifo_shadow.fill == FIFO_DEPTH);
                    bit empty_b = (fifo_shadow.fill == 0);
                    bit thresh_b = (fifo_shadow.fill >= fifo_shadow.thresh);
                    exp_status = {29'h0, thresh_b, empty_b, full_b};
                    check_field("FIFO_STATUS", exp_status, t.data);
                end
                FIFO_ADDR_DEPTH:
                    check_field("FIFO_DEPTH", 32'(FIFO_DEPTH), t.data);
                FIFO_ADDR_THRESH:
                    check_field("FIFO_THRESH", fifo_shadow.thresh, t.data);
                FIFO_ADDR_CONTROL:
                    check_field("FIFO_CONTROL", fifo_shadow.control, t.data);
                default:
                    `uvm_warning("SCOREBOARD_FIFO",
                        $sformatf("Read from unmapped FIFO addr 0x%0h", t.addr))
            endcase
        end
    endfunction

    function void check_field(string id, logic [31:0] expected, logic [31:0] actual);
        if (expected !== actual)
            flag_error(id,
                $sformatf("Mismatch: expected=0x%08h actual=0x%08h",
                           expected, actual));
    endfunction

    function void flag_error(string id, string msg);
        error_count++;
        `uvm_error(id, msg)
    endfunction

    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (fifo_ref_q.size() != 0)
            flag_error("SCOREBOARD_FIFO",
                $sformatf(
                    "Test ended with %0d entries in FIFO ref queue not read back",
                    fifo_ref_q.size()));
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SCOREBOARD",
            $sformatf("Summary: %0d checks, %0d errors",
                       check_count, error_count), UVM_LOW)
        if (error_count == 0)
            `uvm_info("SCOREBOARD", "*** ALL CHECKS PASSED ***", UVM_LOW)
        else
            `uvm_error("SCOREBOARD",
                $sformatf("*** %0d CHECK(S) FAILED ***", error_count))
    endfunction

endclass

`endif