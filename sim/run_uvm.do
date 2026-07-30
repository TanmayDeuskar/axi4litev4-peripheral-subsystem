# =================================================================
# run_uvm.do — AXI4-Lite Peripheral Subsystem UVM Testbench
# Location: sim/run_uvm.do
# All paths relative to sim/
#
# Usage from Questa transcript:
#   do run_uvm.do                     <- compile + run default test
#   run_test test_timer_basic         <- single test, random seed
#   run_test test_fifo_basic 42       <- single test, fixed seed
#   run_regression 20                 <- all tests, 20 seeds each
# =================================================================

# =================================================================
# 1. Library
# =================================================================
if {![file exists work]} {
    vlib work
    vmap work work
}

# =================================================================
# 2. Compile
#
# Interfaces and RTL are compiled as plain -sv files.
# All UVM TB classes are compiled through axi4lite_pkg.sv in one
# shot — the package handles the uvm_pkg import and uvm_macros.svh
# include internally, so no +incdir+ path hunting is needed here.
# =================================================================

# Interfaces — no UVM dependency, compile as plain SV
vlog -sv ../tb/interface/axi4lite_if.sv
vlog -sv ../tb/interface/gpio_if.sv
vlog -sv ../tb/interface/timer_if.sv
vlog -sv ../tb/interface/fifo_if.sv
vlog -sv ../tb/interface/irq_if.sv

# RTL — no UVM dependency
vlog -sv ../rtl/gpio.sv
vlog -sv ../rtl/timer.sv
vlog -sv ../rtl/fifo.sv
vlog -sv ../rtl/irq_aggregator.sv
vlog -sv ../rtl/axi4lite_wrapper.sv
vlog -sv ../rtl/address_decoder.sv
vlog -sv ../rtl/top.sv

# UVM package — compiles all TB classes in dependency order.
# Questa resolves uvm_pkg through modelsim.ini automatically.
vlog -sv ../tb/axi4lite_pkg.sv

# tb_top — compiled last; imports axi4lite_pkg for test class
# visibility and instantiates DUT + interfaces
vlog -sv ../tb/tb_top.sv

vlog -sv +cover=bcefsx ../rtl/gpio.sv
vlog -sv +cover=bcefsx ../rtl/timer.sv
vlog -sv +cover=bcefsx ../rtl/fifo.sv
vlog -sv +cover=bcefsx ../rtl/irq_aggregator.sv
vlog -sv +cover=bcefsx ../rtl/axi4lite_wrapper.sv
vlog -sv +cover=bcefsx ../rtl/address_decoder.sv
vlog -sv +cover=bcefsx ../rtl/top.sv

puts "=== Compilation complete ==="

# =================================================================
# 3. Simulation procs
# =================================================================
proc run_test {testname {seed random}} {
    puts "=== Running $testname (seed=$seed) ==="
    vsim -sv_seed $seed            \
         -coverage                 \
         work.tb_top               \
         +UVM_TESTNAME=$testname   \
         +UVM_VERBOSITY=UVM_MEDIUM \
         -do "run -all; coverage save -onexit ${testname}.ucdb"
}

proc run_test_gui {testname {seed random}} {
    puts "=== Running $testname (seed=$seed) [GUI] ==="
    vsim -sv_seed $seed           \
         work.tb_top               \
         +UVM_TESTNAME=$testname   \
         +UVM_VERBOSITY=UVM_MEDIUM
    # call "run -all" manually from transcript when ready
}

proc run_regression {{n_seeds 10}} {
    set tests {
        test_gpio_basic
        test_timer_basic
        test_fifo_basic
        test_all_peripherals
    }
    foreach test $tests {
        for {set seed 1} {$seed <= $n_seeds} {incr seed} {
            puts "=== $test seed=$seed ==="
            vsim -sv_seed $seed        \
                 work.tb_top            \
                 +UVM_TESTNAME=$test    \
                 +UVM_VERBOSITY=UVM_LOW \
                 -do "run -all"
        }
    }
}

# =================================================================
# 4. Default run
# =================================================================
#run_test test_all_peripherals

#run_regression
