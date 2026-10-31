#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
output=boolean_demo/build/simulation
mkdir -p "$output"
iverilog -g2012 -s tb_demo -o "$output/demo.vvp" async_fifo/rtl/async_fifo.sv axi4lite_slave_top.sv boolean_demo/rtl/endpoint.sv boolean_demo/rtl/demo.sv boolean_demo/tb_demo.sv
vvp "$output/demo.vvp" > "$output/demo.log"
sed -e 's/axi4lite_slave_top #(/axi_demo_endpoint #(/' -e 's/dut\./dut.slave./g' tb/tb_axi4lite_hardening.sv > "$output/tb_endpoint.sv"
for clocks in '15 15' '15 5' '5 15' '5 7'; do
    read -r axi_half core_half <<< "$clocks"
    for policy in '0 0' '0 2' '1 2' '0 3' '1 3'; do
        read -r align oor <<< "$policy"
        tag="$axi_half-$core_half-$align-$oor"
        iverilog -g2012 -DPOLICY -s tb_axi4lite_hardening -Ptb_axi4lite_hardening.AH="$axi_half" -Ptb_axi4lite_hardening.CH="$core_half" -Ptb_axi4lite_hardening.ALIGN="$align" -Ptb_axi4lite_hardening.OOR="$oor" -o "$output/$tag.vvp" async_fifo/rtl/async_fifo.sv axi4lite_slave_top.sv boolean_demo/rtl/endpoint.sv tb/axi4lite_reset_checker.sv "$output/tb_endpoint.sv"
        vvp "$output/$tag.vvp" > "$output/$tag.log"
    done
done
echo 'PASS board demo plus 20 endpoint protocol cases'
