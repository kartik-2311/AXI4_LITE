set directory [file dirname [file normalize [info script]]]
set output [file join $directory build vivado]
cd $output
if {![file exists [file join $directory build release-approved.tcl]]} {error "Run verified release approval first"}
source [file join $directory build release-approved.tcl]
set digest_output [exec certutil -hashfile [file join $output routed.dcp] SHA256]
if {![regexp -nocase $expected_checkpoint_sha $digest_output]} {error "Routed checkpoint changed since review"}
open_checkpoint [file join $output routed.dcp]
foreach kind {max min} {
    set paths [get_timing_paths -delay_type $kind -max_paths 1]
    if {[llength $paths] == 0 || [get_property SLACK $paths] < 0} {error "Timing failed"}
}
write_bitstream -force [file join $output axi_boolean_top.bit]
puts "BITSTREAM_READY 100MHz/75MHz [file join $output axi_boolean_top.bit]"
