`ifndef AXI4LITE_SCOREBOARD_SV
`define AXI4LITE_SCOREBOARD_SV

// import and macros.svh MUST come before uvm_analysis_imp_decl —
// the macros expand to class definitions that use UVM base classes
import uvm_pkg::*;
`include "uvm_macros.svh"

// Each macro generates a new uvm_analysis_imp class with the given suffix
// and requires a matching write_<suffix>() function in the subscriber class.
`uvm_analysis_imp_decl(_gpio)
`uvm_analysis_imp_decl(_irq)

// =====================================================================
// Address map — mirrors axi4lite_sequence.sv and RTL localparams
// =====================================================================
localparam logic [31:0] GPIO_BASE  = 32'h000;
localparam logic [31:0] TIMER_BASE = 32'h100;
localparam logic [31:0] FIFO_BASE  = 32'h200;

localparam logic [31:0] GPIO_ADDR_DATA_OUT     = GPIO_BASE + 32'h00;
localparam logic [31:0] GPIO_ADDR_DATA_IN      = GPIO_BASE + 32'h04;
localparam logic [31:0] GPIO_ADDR_DIRECTION    = GPIO_BASE + 32'h08;
localparam logic [31:0] GPIO_ADDR_INT_EN       = GPIO_BASE + 32'h0C;
localparam logic [31:0] GPIO_ADDR_INT_STATUS   = GPIO_BASE + 32'h10;
localparam logic [31:0] GPIO_ADDR_INT_TYPE     = GPIO_BASE + 32'h14;
localparam logic [31:0] GPIO_ADDR_INT_POLARITY = GPIO_BASE + 32'h18;

localparam logic [31:0] TIMER_ADDR_LOAD      = TIMER_BASE + 32'h00;
localparam logic [31:0] TIMER_ADDR_COUNT     = TIMER_BASE + 32'h04;
localparam logic [31:0] TIMER_ADDR_CONTROL   = TIMER_BASE + 32'h08;
localparam logic [31:0] TIMER_ADDR_STATUS    = TIMER_BASE + 32'h0C;
localparam logic [31:0] TIMER_ADDR_PRESCALAR = TIMER_BASE + 32'h10;

localparam logic [31:0] FIFO_ADDR_WDATA   = FIFO_BASE + 32'h00;
localparam logic [31:0] FIFO_ADDR_RDATA   = FIFO_BASE + 32'h04;
localparam logic [31:0] FIFO_ADDR_STATUS  = FIFO_BASE + 32'h08;
localparam logic [31:0] FIFO_ADDR_DEPTH   = FIFO_BASE + 32'h0C;
localparam logic [31:0] FIFO_ADDR_THRESH  = FIFO_BASE + 32'h10;
localparam logic [31:0] FIFO_ADDR_CONTROL = FIFO_BASE + 32'h14;

localparam int FIFO_DEPTH = 16;   // must match fifo.sv DEPTH parameter

// irq_status bit assignments — must match irq_aggregator wiring
localparam int GPIO_IRQ_BIT  = 0;
localparam int TIMER_IRQ_BIT = 1;
localparam int FIFO_IRQ_BIT  = 2;

// Timer IRQ timing tolerance — absorbs the fixed ~1-2 cycle offset between
// "BVALID observed by monitor" and "timer peripheral received psel/pwrite".
// 3 cycles is intentionally tight: catches real bugs (wrong LOAD/PRESCALAR)
// while absorbing the pipeline offset. If you see false failures, increase
// to 4 but investigate first.
localparam int  TIMER_IRQ_WINDOW_CYCLES = 3;
localparam time CLK_PERIOD              = 10ns;  // must match TB clock

// =====================================================================
// Timer FSM state — mirrors timer.sv typedef exactly
// =====================================================================
typedef enum logic {
    TIMER_IDLE  = 1'b0,
    TIMER_COUNT = 1'b1
} timer_fsm_state_e;

// =====================================================================
// Shadow state structs — one per peripheral
// =====================================================================
typedef struct {
    logic [31:0] data_out;
    logic [31:0] direction;
    logic [31:0] int_en;
    logic [31:0] int_status;
    logic [31:0] int_type;
    logic [31:0] int_polarity;
} gpio_shadow_t;

typedef struct {
    logic [31:0]      load;
    logic [31:0]      control;
    logic [31:0]      status;
    logic [31:0]      prescalar;
    logic [31:0]      count;
    logic [31:0]      pre_scalar_counter;
    timer_fsm_state_e state;
} timer_shadow_t;

typedef struct {
    logic [31:0] thresh;
    logic [31:0] control;
    int unsigned fill;
} fifo_shadow_t;

// =====================================================================
// Scoreboard
// =====================================================================
class axi4lite_scoreboard extends uvm_subscriber #(axi4lite_seq_item);
    `uvm_component_utils(axi4lite_scoreboard)

    // GPIO and IRQ monitors connect to these ports
    uvm_analysis_imp_gpio #(gpio_transaction, axi4lite_scoreboard) gpio_imp;
    uvm_analysis_imp_irq  #(irq_transaction,  axi4lite_scoreboard) irq_imp;

    // Clock/reset access for the timer FSM model
    virtual axi4lite_if vif;

    // ----------------------------------------------------------------
    // Shadow state
    // ----------------------------------------------------------------
    gpio_shadow_t  gpio_shadow;
    timer_shadow_t timer_shadow;
    fifo_shadow_t  fifo_shadow;

    // FIFO order-check queue: pushed on WDATA writes, popped on RDATA reads
    logic [31:0] fifo_ref_q[$];

    // Timestamp of most recent CTRL write — used by write_irq() for timer
    // timing check. Reset to 0 on reset, updated every CTRL write observation.
    time timer_ctrl_write_time;

    // FIX: track whether the timer model overflowed this cycle so the w1c
    // handler can make the correct priority decision (set wins over clear,
    // matching RTL NBA behaviour). Set by tick_counter_model(), cleared after
    // each timer_fsm_process() tick.
    bit timer_overflow_this_cycle;

    // ----------------------------------------------------------------
    // Statistics
    // ----------------------------------------------------------------
    int unsigned error_count;
    int unsigned check_count;

    // ================================================================
    // Construction
    // ================================================================
    function new(string name = "axi4lite_scoreboard", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        gpio_imp = new("gpio_imp", this);
        irq_imp  = new("irq_imp",  this);
        if (!uvm_config_db#(virtual axi4lite_if)::get(this, "", "vif", vif))
            `uvm_fatal("SCOREBOARD", "Could not get virtual axi4lite_if from config db")
        error_count              = 0;
        check_count              = 0;
        timer_ctrl_write_time    = 0;
        timer_overflow_this_cycle = 0;
        reset_all_shadows();
    endfunction

    // ================================================================
    // reset_all_shadows — mirrors each peripheral's reset clause
    // ================================================================
    function void reset_all_shadows();
        gpio_shadow.data_out     = '0;
        gpio_shadow.direction    = '0;
        gpio_shadow.int_en       = '0;
        gpio_shadow.int_status   = '0;
        gpio_shadow.int_type     = '0;
        gpio_shadow.int_polarity = '0;

        // Timer: all zero, FSM in IDLE
        timer_shadow.load               = '0;
        timer_shadow.control            = '0;
        timer_shadow.status             = '0;
        timer_shadow.prescalar          = '0;
        timer_shadow.count              = '0;
        timer_shadow.pre_scalar_counter = '0;
        timer_shadow.state              = TIMER_IDLE;

        // FIFO: fill=0, thresh=DEPTH (matches fifo.sv reset: thresh<=DEPTH)
        fifo_shadow.thresh  = FIFO_DEPTH;
        fifo_shadow.control = '0;
        fifo_shadow.fill    = 0;
        fifo_ref_q.delete();
    endfunction

    // ================================================================
    // run_phase — spawns the timer FSM model as a background thread.
    // join_none is critical: without it run_phase would block forever
    // on the forever loop inside timer_fsm_process, preventing UVM
    // from ever advancing past the run phase.
    // ================================================================
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

    // ================================================================
    // Timer FSM model — structural mirror of timer.sv always_ff.
    // Called once per posedge ACLK by timer_fsm_process().
    // ================================================================
    function void tick_timer_model();
        logic enable = timer_shadow.control[0];

        if (enable) begin
            if (timer_shadow.state == TIMER_IDLE) begin
                timer_shadow.count              = timer_shadow.load;
                timer_shadow.pre_scalar_counter = timer_shadow.prescalar;
                timer_shadow.state              = TIMER_COUNT;
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

    // Mirrors timer.sv's tick_counter() task.
    // Sets timer_overflow_this_cycle flag so the w1c handler in
    // handle_timer() knows not to clear status[0] if the model set it
    // this same cycle — matches RTL's NBA "set wins over clear" priority.
    function void tick_counter_model();
        logic auto_reload = timer_shadow.control[1];

        if (timer_shadow.count == 0) begin
            timer_shadow.status[0]    = 1'b1;
            timer_overflow_this_cycle = 1;     // FIX: flag the overflow

            if (auto_reload) begin
                timer_shadow.count = timer_shadow.load;
                // FIX: reset the timing reference point for the next period.
                // Without this, write_irq() would measure from the original
                // CTRL write for ALL subsequent overflows in auto_reload mode,
                // making actual_period grow as 2x, 3x, 4x... the expected
                // period — all would fail the timing check.
                //timer_ctrl_write_time = $time;
            end else begin
                // One-shot: hardware auto-clears enable
                timer_shadow.state      = TIMER_IDLE;
                timer_shadow.control[0] = 1'b0;
            end
        end else begin
            timer_shadow.count--;
        end
    endfunction

    // ================================================================
    // write() — AXI analysis port entry point (uvm_subscriber override)
    // Called by axi4lite_monitor's ap.write() for every completed
    // AXI transaction. t.timestamp is set by the monitor at BVALID/RVALID.
    // ================================================================
    function void write(axi4lite_seq_item t);
        // Route by address range
        if      (t.addr >= GPIO_BASE  && t.addr < TIMER_BASE)              handle_gpio(t);
        else if (t.addr >= TIMER_BASE && t.addr < FIFO_BASE)               handle_timer(t);
        else if (t.addr >= FIFO_BASE  && t.addr < (FIFO_BASE + 32'h100))  handle_fifo(t);
        else
            `uvm_warning("SCOREBOARD",
                $sformatf("Transaction to unmapped addr 0x%0h ignored", t.addr))
    endfunction

    // ================================================================
    // write_gpio() — GPIO output monitor callback
    // Called by gpio_monitor whenever gpio_out or gpio_oe changes.
    // Every call is a real output change that must be verified.
    // ================================================================
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

    // ================================================================
    // write_irq() — IRQ monitor callback
    // Called on every edge of combined_irq.
    // Only rising edges (assertions) are actively checked.
    // ================================================================
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

        // ---- GPIO IRQ ----
        // We can't fully predict which pin triggered (gpio_in not monitored),
        // so we check the minimum necessary precondition: int_en must be
        // non-zero, otherwise no pin could legally fire an interrupt.
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

        // ---- Timer IRQ ----
        // Expected period = (load+1)*(prescalar+1) clock cycles from CTRL write.
        // timer_ctrl_write_time is updated:
        //   - when CTRL is written (first enable)
        //   - by tick_counter_model() on each auto_reload overflow (subsequent periods)
        // This ensures actual_period is always measured relative to the START of
        // the current period, not from the very first CTRL write.
        if (t.irq_status[TIMER_IRQ_BIT]) begin
            check_count++;
            begin
                time actual_period;
                time expected_period;
                time diff;
                time window;

                actual_period   = t.timestamp - timer_ctrl_write_time;
                expected_period = CLK_PERIOD *
                                  ((timer_shadow.load + 1) *
                                   (timer_shadow.prescalar + 1));
                // Absolute difference — avoids underflow since time is unsigned
                diff   = (actual_period > expected_period) ?
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

        // ---- FIFO IRQ ----
        // fill is tracked exactly by the scoreboard so this check is precise:
        // IRQ should fire iff fill >= thresh AND int_en is set.
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

    // ================================================================
    // GPIO AXI handler
    // ================================================================
    function void handle_gpio(axi4lite_seq_item t);
        if (t.write) begin
            case (t.addr)
                GPIO_ADDR_DATA_OUT:
                    gpio_shadow.data_out     = t.data;
                GPIO_ADDR_DIRECTION:
                    gpio_shadow.direction    = t.data;
                GPIO_ADDR_INT_EN:
                    gpio_shadow.int_en       = t.data;
                GPIO_ADDR_INT_TYPE:
                    gpio_shadow.int_type     = t.data;
                GPIO_ADDR_INT_POLARITY:
                    gpio_shadow.int_polarity = t.data;
                GPIO_ADDR_INT_STATUS:
                    // w1c: clear bits where software wrote 1.
                    // We don't model the gpio_in-triggered set side since
                    // gpio_in isn't tracked — int_status shadow is only
                    // meaningful for the "was it cleared" direction.
                    gpio_shadow.int_status = gpio_shadow.int_status & ~t.data;
                default:
                    `uvm_warning("SCOREBOARD_GPIO",
                        $sformatf("Write to unmapped GPIO addr 0x%0h", t.addr))
            endcase
        end else begin
            check_count++;
            case (t.addr)
                GPIO_ADDR_DATA_OUT:
                    check_field("GPIO_DATA_OUT",     gpio_shadow.data_out,     t.data);
                GPIO_ADDR_DIRECTION:
                    check_field("GPIO_DIRECTION",    gpio_shadow.direction,    t.data);
                GPIO_ADDR_INT_EN:
                    check_field("GPIO_INT_EN",       gpio_shadow.int_en,       t.data);
                GPIO_ADDR_INT_TYPE:
                    check_field("GPIO_INT_TYPE",     gpio_shadow.int_type,     t.data);
                GPIO_ADDR_INT_POLARITY:
                    check_field("GPIO_INT_POLARITY", gpio_shadow.int_polarity, t.data);
                GPIO_ADDR_DATA_IN:
                    ;  // physical pin state — not predictable from AXI, skip
                GPIO_ADDR_INT_STATUS:
                    ;  // needs gpio_in edge tracking to predict — skip
                default:
                    `uvm_warning("SCOREBOARD_GPIO",
                        $sformatf("Read from unmapped GPIO addr 0x%0h", t.addr))
            endcase
        end
    endfunction

    // ================================================================
    // Timer AXI handler
    // ================================================================
    function void handle_timer(axi4lite_seq_item t);
        if (t.write) begin
            case (t.addr)
                TIMER_ADDR_LOAD:
                    timer_shadow.load      = t.data;
                TIMER_ADDR_PRESCALAR:
                    timer_shadow.prescalar = t.data;
                TIMER_ADDR_CONTROL: begin
                    timer_shadow.control   = t.data;
                    // Record sim time of this CTRL write — the start-of-period
                    // reference point for timing checks. For auto_reload, this
                    // is also updated by tick_counter_model() on each overflow
                    // so subsequent period checks measure from the right origin.
                    if (t.data[0])  // enable bit set
                        timer_ctrl_write_time = t.timestamp;
                end
                TIMER_ADDR_STATUS: begin
                    // w1c — FIX: if the timer model set status[0] THIS SAME
                    // CYCLE (flagged by timer_overflow_this_cycle), the RTL's
                    // NBA semantics mean the set wins over the clear. So we
                    // only clear the bit if there was no overflow this cycle.
                    // This matches: in always_ff, "set overflow" appears after
                    // "w1c clear" so the set takes effect on the same edge.
                    if (timer_overflow_this_cycle)
                        // set wins — don't clear status[0]
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
                    check_field("TIMER_LOAD",      timer_shadow.load,      t.data);
                TIMER_ADDR_PRESCALAR:
                    check_field("TIMER_PRESCALAR", timer_shadow.prescalar, t.data);
                TIMER_ADDR_COUNT:
                    // FSM model tracks this cycle-accurately
                    check_field("TIMER_COUNT",     timer_shadow.count,     t.data);
                TIMER_ADDR_STATUS:
                    check_field("TIMER_STATUS",    timer_shadow.status,    t.data);
                TIMER_ADDR_CONTROL:
                    check_field("TIMER_CONTROL",   timer_shadow.control,   t.data);
                default:
                    `uvm_warning("SCOREBOARD_TIMER",
                        $sformatf("Read from unmapped Timer addr 0x%0h", t.addr))
            endcase
        end
    endfunction

    // ================================================================
    // FIFO AXI handler
    // ================================================================
    function void handle_fifo(axi4lite_seq_item t);
        if (t.write) begin
            case (t.addr)
                FIFO_ADDR_THRESH:
                    fifo_shadow.thresh  = t.data;
                FIFO_ADDR_CONTROL:
                    fifo_shadow.control = t.data;
                FIFO_ADDR_WDATA: begin
                    if (fifo_shadow.fill < FIFO_DEPTH) begin
                        fifo_ref_q.push_back(t.data);
                        fifo_shadow.fill++;
                    end else begin
                        // fifo_write_seq checks STATUS before every push so this
                        // should never fire in correct operation — if it does,
                        // either the sequence has a bug or the STATUS full bit
                        // returned a wrong value
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
                        // Read from empty — RTL returns 0, rptr does not advance
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
                    bit full_b   = (fifo_shadow.fill == FIFO_DEPTH);
                    bit empty_b  = (fifo_shadow.fill == 0);
                    bit thresh_b = (fifo_shadow.fill >= fifo_shadow.thresh);
                    exp_status   = {29'h0, thresh_b, empty_b, full_b};
                    check_field("FIFO_STATUS", exp_status, t.data);
                end
                FIFO_ADDR_DEPTH:
                    check_field("FIFO_DEPTH",   32'(FIFO_DEPTH),    t.data);
                FIFO_ADDR_THRESH:
                    check_field("FIFO_THRESH",  fifo_shadow.thresh,  t.data);
                FIFO_ADDR_CONTROL:
                    check_field("FIFO_CONTROL", fifo_shadow.control, t.data);
                default:
                    `uvm_warning("SCOREBOARD_FIFO",
                        $sformatf("Read from unmapped FIFO addr 0x%0h", t.addr))
            endcase
        end
    endfunction

    // ================================================================
    // check_field — central compare function
    // ================================================================
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

    // ================================================================
    // check_phase — end-of-test sanity
    // ================================================================
    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        // Any entries left in the ref queue were written but never read back —
        // either the test didn't drain the FIFO or fifo_read_seq stopped early
        if (fifo_ref_q.size() != 0)
            flag_error("SCOREBOARD_FIFO",
                $sformatf(
                    "Test ended with %0d entries in FIFO ref queue not read back",
                    fifo_ref_q.size()));
    endfunction

    // ================================================================
    // report_phase — final summary
    // ================================================================
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SCOREBOARD",
            $sformatf("Summary: %0d checks, %0d errors",
                       check_count, error_count), UVM_LOW)
        if (error_count == 0)
            `uvm_info("SCOREBOARD",  "*** ALL CHECKS PASSED ***", UVM_LOW)
        else
            `uvm_error("SCOREBOARD",
                $sformatf("*** %0d CHECK(S) FAILED ***", error_count))
    endfunction

endclass

`endif