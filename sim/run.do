quit -sim

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work


echo "--- Compiling interfaces ---"
vlog -sv ../tb/interface/axi4lite_if.sv
vlog -sv ../tb/interface/gpio_if.sv

echo "--- Compiling RTL ---"
vlog -sv ../rtl/gpio.sv
vlog -sv ../rtl/axi4lite_wrapper.sv
vlog -sv ../rtl/address_decoder.sv
vlog -sv ../rtl/top.sv

echo "--- Compiling testbench ---"
vlog -sv ../tb/tb_gpio_directed.sv

echo "--- Starting simulation ---"
vsim -t 1ps \
     -voptargs=+acc \
     work.tb_gpio_directed

add wave -divider "Clock and Reset"
add wave -radix bin  sim:/tb_gpio_directed/clk
add wave -radix bin  sim:/tb_gpio_directed/rst_n

add wave -divider "AXI Write Channel"
add wave -radix hex  sim:/tb_gpio_directed/axiif/AWVALID
add wave -radix hex  sim:/tb_gpio_directed/axiif/AWREADY
add wave -radix hex  sim:/tb_gpio_directed/axiif/AWADDR
add wave -radix hex  sim:/tb_gpio_directed/axiif/WVALID
add wave -radix hex  sim:/tb_gpio_directed/axiif/WREADY
add wave -radix hex  sim:/tb_gpio_directed/axiif/WDATA
add wave -radix hex  sim:/tb_gpio_directed/axiif/WSTRB
add wave -radix hex  sim:/tb_gpio_directed/axiif/BVALID
add wave -radix hex  sim:/tb_gpio_directed/axiif/BREADY
add wave -radix hex  sim:/tb_gpio_directed/axiif/BRESP

add wave -divider "AXI Read Channel"
add wave -radix hex  sim:/tb_gpio_directed/axiif/ARVALID
add wave -radix hex  sim:/tb_gpio_directed/axiif/ARREADY
add wave -radix hex  sim:/tb_gpio_directed/axiif/ARADDR
add wave -radix hex  sim:/tb_gpio_directed/axiif/RVALID
add wave -radix hex  sim:/tb_gpio_directed/axiif/RREADY
add wave -radix hex  sim:/tb_gpio_directed/axiif/RDATA
add wave -radix hex  sim:/tb_gpio_directed/axiif/RRESP

add wave -divider "Peripheral Bus"
add wave -radix bin  sim:/tb_gpio_directed/dut/psel
add wave -radix bin  sim:/tb_gpio_directed/dut/pwrite
add wave -radix hex  sim:/tb_gpio_directed/dut/paddr
add wave -radix hex  sim:/tb_gpio_directed/dut/pwdata
add wave -radix hex  sim:/tb_gpio_directed/dut/prdata
add wave -radix bin  sim:/tb_gpio_directed/dut/prdata_valid

add wave -divider "GPIO Peripheral Bus"
add wave -radix bin  sim:/tb_gpio_directed/dut/gpio_sel
add wave -radix bin  sim:/tb_gpio_directed/dut/gpio_write
add wave -radix hex  sim:/tb_gpio_directed/dut/gpio_addr
add wave -radix hex  sim:/tb_gpio_directed/dut/gpio_wdata
add wave -radix hex  sim:/tb_gpio_directed/dut/gpio_rdata

add wave -divider "GPIO Registers"
add wave -radix hex  sim:/tb_gpio_directed/dut/gpio1/data_out_reg
add wave -radix hex  sim:/tb_gpio_directed/dut/gpio1/direction
add wave -radix hex  sim:/tb_gpio_directed/dut/gpio1/int_en_reg
add wave -radix hex  sim:/tb_gpio_directed/dut/gpio1/int_status_reg
add wave -radix hex  sim:/tb_gpio_directed/dut/gpio1/int_type_reg
add wave -radix hex  sim:/tb_gpio_directed/dut/gpio1/int_polarity_reg
add wave -radix hex  sim:/tb_gpio_directed/dut/gpio1/trig

add wave -divider "GPIO Pins"
add wave -radix hex  sim:/tb_gpio_directed/gpif/gpio_in
add wave -radix hex  sim:/tb_gpio_directed/gpif/gpio_out
add wave -radix hex  sim:/tb_gpio_directed/gpif/gpio_oe

add wave -divider "Interrupt"
add wave -radix bin  sim:/tb_gpio_directed/irq
add wave -radix hex  sim:/tb_gpio_directed/dut/gpio1/trig

run -all

wave zoom full
