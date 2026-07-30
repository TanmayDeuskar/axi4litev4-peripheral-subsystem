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
vlog -sv ../tb/interface/fifo_if.sv

echo "--- Compiling RTL ---"
vlog -sv ../rtl/gpio.sv
vlog -sv ../rtl/timer.sv
vlog -sv ../rtl/fifo.sv
vlog -sv ../rtl/axi4lite_wrapper.sv
vlog -sv ../rtl/address_decoder.sv
vlog -sv ../rtl/top.sv

echo "--- Compiling testbench ---"
vlog -sv ../tb/tb_fifo_directed.sv

echo "--- Starting simulation ---"
vsim -t 1ps \
     -voptargs=+acc \
     work.tb_fifo_directed

add wave -divider "Clock and Reset"
add wave -radix bin  sim:/tb_fifo_directed/clk
add wave -radix bin  sim:/tb_fifo_directed/rst_n

add wave -divider "AXI Write Channel"
add wave -radix hex  sim:/tb_fifo_directed/axiif/AWVALID
add wave -radix hex  sim:/tb_fifo_directed/axiif/AWREADY
add wave -radix hex  sim:/tb_fifo_directed/axiif/AWADDR
add wave -radix hex  sim:/tb_fifo_directed/axiif/WVALID
add wave -radix hex  sim:/tb_fifo_directed/axiif/WREADY
add wave -radix hex  sim:/tb_fifo_directed/axiif/WDATA
add wave -radix hex  sim:/tb_fifo_directed/axiif/BVALID
add wave -radix hex  sim:/tb_fifo_directed/axiif/BREADY

add wave -divider "AXI Read Channel"
add wave -radix hex  sim:/tb_fifo_directed/axiif/ARVALID
add wave -radix hex  sim:/tb_fifo_directed/axiif/ARREADY
add wave -radix hex  sim:/tb_fifo_directed/axiif/ARADDR
add wave -radix hex  sim:/tb_fifo_directed/axiif/RVALID
add wave -radix hex  sim:/tb_fifo_directed/axiif/RREADY
add wave -radix hex  sim:/tb_fifo_directed/axiif/RDATA

add wave -divider "Peripheral Bus"
add wave -radix bin  sim:/tb_fifo_directed/dut/psel
add wave -radix bin  sim:/tb_fifo_directed/dut/pwrite
add wave -radix hex  sim:/tb_fifo_directed/dut/paddr
add wave -radix hex  sim:/tb_fifo_directed/dut/pwdata
add wave -radix hex  sim:/tb_fifo_directed/dut/prdata
add wave -radix bin  sim:/tb_fifo_directed/dut/prdata_valid

add wave -divider "FIFO Peripheral Bus"
add wave -radix bin  sim:/tb_fifo_directed/dut/fifo_sel
add wave -radix bin  sim:/tb_fifo_directed/dut/fifo_write
add wave -radix hex  sim:/tb_fifo_directed/dut/fifo_addr
add wave -radix hex  sim:/tb_fifo_directed/dut/fifo_wdata
add wave -radix hex  sim:/tb_fifo_directed/dut/fifo_rdata
add wave -radix bin  sim:/tb_fifo_directed/dut/fifo_data_valid

add wave -divider "FIFO Internals"
add wave -radix dec  sim:/tb_fifo_directed/dut/fifo1/fill
add wave -radix dec  sim:/tb_fifo_directed/dut/fifo1/wptr
add wave -radix dec  sim:/tb_fifo_directed/dut/fifo1/rptr
add wave -radix bin  sim:/tb_fifo_directed/dut/fifo1/full
add wave -radix bin  sim:/tb_fifo_directed/dut/fifo1/empty
add wave -radix dec  sim:/tb_fifo_directed/dut/fifo1/thresh
add wave -radix hex  sim:/tb_fifo_directed/dut/fifo1/control

add wave -divider "Interrupt"
add wave -radix bin  sim:/tb_fifo_directed/irq

run -all
wave zoom full
