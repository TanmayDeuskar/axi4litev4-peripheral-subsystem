quit -sim

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work


echo "--- Compiling interfaces ---"
vlog -sv ../tb/interface/axi4lite_if.sv
vlog -sv ../tb/interface/gpio_if.sv
vlog -sv ../tb/interface/timer_if.sv

echo "--- Compiling RTL ---"
vlog -sv ../rtl/gpio.sv
vlog -sv ../rtl/timer.sv
vlog -sv ../rtl/axi4lite_wrapper.sv
vlog -sv ../rtl/address_decoder.sv
vlog -sv ../rtl/top.sv

echo "--- Compiling testbench ---"
vlog -sv ../tb/tb_timer_directed.sv

echo "--- Starting simulation ---"
vsim -t 1ps \
     -voptargs=+acc \
     work.tb_timer_directed

add wave -divider "Clock and Reset"
add wave -radix bin  sim:/tb_timer_directed/clk
add wave -radix bin  sim:/tb_timer_directed/rst_n

add wave -divider "AXI Write Channel"
add wave -radix hex  sim:/tb_timer_directed/axiif/AWVALID
add wave -radix hex  sim:/tb_timer_directed/axiif/AWREADY
add wave -radix hex  sim:/tb_timer_directed/axiif/AWADDR
add wave -radix hex  sim:/tb_timer_directed/axiif/WVALID
add wave -radix hex  sim:/tb_timer_directed/axiif/WREADY
add wave -radix hex  sim:/tb_timer_directed/axiif/WDATA
add wave -radix hex  sim:/tb_timer_directed/axiif/WSTRB
add wave -radix hex  sim:/tb_timer_directed/axiif/BVALID
add wave -radix hex  sim:/tb_timer_directed/axiif/BREADY
add wave -radix hex  sim:/tb_timer_directed/axiif/BRESP

add wave -divider "AXI Read Channel"
add wave -radix hex  sim:/tb_timer_directed/axiif/ARVALID
add wave -radix hex  sim:/tb_timer_directed/axiif/ARREADY
add wave -radix hex  sim:/tb_timer_directed/axiif/ARADDR
add wave -radix hex  sim:/tb_timer_directed/axiif/RVALID
add wave -radix hex  sim:/tb_timer_directed/axiif/RREADY
add wave -radix hex  sim:/tb_timer_directed/axiif/RDATA
add wave -radix hex  sim:/tb_timer_directed/axiif/RRESP

add wave -divider "Peripheral Bus"
add wave -radix bin  sim:/tb_timer_directed/dut/psel
add wave -radix bin  sim:/tb_timer_directed/dut/pwrite
add wave -radix hex  sim:/tb_timer_directed/dut/paddr
add wave -radix hex  sim:/tb_timer_directed/dut/pwdata
add wave -radix hex  sim:/tb_timer_directed/dut/prdata
add wave -radix bin  sim:/tb_timer_directed/dut/prdata_valid

add wave -divider "Timer Peripheral Bus"
add wave -radix bin  sim:/tb_timer_directed/dut/timer_sel
add wave -radix bin  sim:/tb_timer_directed/dut/timer_write
add wave -radix hex  sim:/tb_timer_directed/dut/timer_addr
add wave -radix hex  sim:/tb_timer_directed/dut/timer_wdata
add wave -radix hex  sim:/tb_timer_directed/dut/timer_rdata
add wave -radix bin  sim:/tb_timer_directed/dut/timer_data_valid

add wave -divider "Timer Registers"
add wave -radix dec  sim:/tb_timer_directed/dut/timer1/reg_load
add wave -radix dec  sim:/tb_timer_directed/dut/timer1/reg_count
add wave -radix hex  sim:/tb_timer_directed/dut/timer1/reg_control
add wave -radix hex  sim:/tb_timer_directed/dut/timer1/reg_status
add wave -radix dec  sim:/tb_timer_directed/dut/timer1/reg_prescalar

add wave -divider "Timer Internals"
add wave -radix dec  sim:/tb_timer_directed/dut/timer1/pre_scalar_counter
add wave -radix ascii sim:/tb_timer_directed/dut/timer1/timer_state

add wave -divider "Interrupt"
add wave -radix bin  sim:/tb_timer_directed/irq

run -all

wave zoom full
