set root [file normalize [file join [file dirname [info script]] ..]]
set output [file join $root boolean_demo build vivado]
file mkdir $output
cd $output
if {[llength $argv] && [lindex $argv 0] eq "implement"} {
    open_checkpoint [file join $output synthesized.dcp]
} else {
create_project axi_boolean [file join $output project] -part xc7s50csga324-1 -force
set rtl [list [file join $root async_fifo rtl async_fifo.sv] [file join $root axi4lite_slave_top.sv] [file join $root boolean_demo rtl endpoint.sv] [file join $root boolean_demo rtl demo.sv] [file join $root boolean_demo rtl board_top.sv]]
read_verilog -sv $rtl
set_property verilog_define {__ICARUS__} [current_fileset]
read_xdc [file join $root boolean_demo board.xdc]
synth_design -top axi_boolean_top -part xc7s50csga324-1
write_checkpoint -force [file join $output synthesized.dcp]
}
create_generated_clock -name AXI_CLK -source [get_pins clocks/CLKIN1] -multiply_by 1 [get_pins clocks/CLKOUT0]
create_generated_clock -name CORE_CLK -source [get_pins clocks/CLKIN1] -multiply_by 3 -divide_by 4 [get_pins clocks/CLKOUT1]
set syncs [get_cells -hier -regexp {.*(u_sync_.*|u_write_done_sync)/(meta_ff_reg.*|sync_ff_reg.*)}]
if {[llength $syncs] < 20} {error "Expected FIFO and completion synchronizers missing"}
set_property ASYNC_REG TRUE $syncs
set_property SHREG_EXTRACT NO $syncs
set meta [get_cells -hier -regexp {.*(u_sync_.*|u_write_done_sync)/meta_ff_reg.*}]
foreach target $meta {
    set pin [get_pins $target/D]
    set starts [all_fanin -flat -startpoints_only -to $pin]
    if {[llength $starts] == 0} {error "Synchronizer input has no source: $pin"}
    set_max_delay -datapath_only 10 -from $starts -to $pin
    set_false_path -hold -from $starts -to $pin
}
foreach pair {{u_write_fifo CORE_CLK} {u_read_req_fifo CORE_CLK} {u_read_resp_fifo AXI_CLK}} {
    lassign $pair fifo destination
    set memory [get_cells -hier -filter [format {NAME =~ "*%s*mem*" && REF_NAME =~ RAM*} $fifo]]
    if {[llength $memory] == 0} {error "FIFO storage not found: $fifo"}
    set target_clock [get_clocks $destination]
    if {[llength $target_clock] != 1} {error "Generated clock missing: $destination"}
    set memory_clocks [get_pins -of_objects $memory -filter {IS_CLOCK == 1 && REF_PIN_NAME == CLK}]
    if {[llength $memory_clocks] == 0} {error "FIFO write clock pins missing: $fifo"}
    set_max_delay -datapath_only 10 -from $memory_clocks -to $target_clock
    set_false_path -hold -from $memory_clocks -to $target_clock
}
set gray_targets [get_pins -of_objects [get_cells -hier -regexp {.*u_sync_.*meta_ff_reg.*}] -filter {REF_PIN_NAME == D}]
set buses [dict create]
foreach pin $gray_targets {
    regexp {(.*u_sync_[^/]+)/meta_ff_reg} $pin unused bus
    dict lappend buses $bus $pin
}
dict for {bus pins} $buses {
    set sources [all_fanin -flat -startpoints_only -to $pins]
    set_bus_skew 10 -from $sources -to $pins
}
set reset_targets [get_pins -of_objects [get_cells -hier -regexp {.*(axi_release_reg.*|core_release_reg.*)}] -filter {REF_PIN_NAME == CLR}]
set_false_path -from [get_ports reset_button] -to $reset_targets
set_false_path -to [get_ports {led[*]}]
opt_design
place_design
route_design
report_clocks -file [file join $output clocks.rpt]
report_timing_summary -report_unconstrained -file [file join $output timing.rpt]
report_cdc -details -all_checks_per_endpoint -file [file join $output cdc.rpt]
report_methodology -file [file join $output methodology.rpt]
report_drc -file [file join $output drc.rpt]
report_bus_skew -file [file join $output bus_skew.rpt]
report_exceptions -coverage -file [file join $output exceptions.rpt]
report_timing -from [get_cells -hier -regexp {.*(axi_release_reg.*|core_release_reg.*)}] -delay_type min_max -file [file join $output reset_paths.rpt]
report_utilization -file [file join $output utilization.rpt]
write_checkpoint -force [file join $output routed.dcp]
set failed 0
foreach kind {max min} {
    set worst [get_timing_paths -delay_type $kind -max_paths 1]
    if {[llength $worst] == 0 || [get_property SLACK $worst] < 0} {set failed 1}
}
if {[llength [get_drc_violations -filter {SEVERITY == Error || SEVERITY == {Critical Warning}}]]} {set failed 1}
if {$failed} {error "Implementation failed; reports retained, bitstream prohibited"}
puts "ROUTED_CHECKPOINT_READY 100MHz/75MHz; review reports before release"
