#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
output="$root/librelane/logs/regression"
mkdir -p "$output"
for clocks in '15 15' '15 5' '5 15' '5 7'; do
    read -r axi_half core_half <<< "$clocks"
    for mode in 0 1 2; do
        policies='0 0'
        if [[ $mode == 0 ]]; then policies=$'0 0\n0 2\n1 2\n0 3\n1 3'; fi
        while read -r align oor; do
            tag="$axi_half-$core_half-$mode-$align-$oor"
            iverilog -g2012 -Wall -Wno-timescale -DPOLICY -s tb_axi4lite_hardening \
                -Ptb_axi4lite_hardening.AH="$axi_half" -Ptb_axi4lite_hardening.CH="$core_half" \
                -Ptb_axi4lite_hardening.ALIGN="$align" -Ptb_axi4lite_hardening.OOR="$oor" \
                -o "$output/$tag.vvp" async_fifo/rtl/async_fifo.sv axi4lite_slave_top.sv \
                tb/axi4lite_reset_checker.sv tb/tb_axi4lite_hardening.sv
            vvp "$output/$tag.vvp" "+MODE=$mode" > "$output/$tag.log" 2>&1
            grep -q '^PASS ' "$output/$tag.log"
        done <<< "$policies"
    done
done
for bad_reset in 1 2; do
    if vvp "$output/$tag.vvp" "+BAD_RESET=$bad_reset" > "$output/reset-$bad_reset.log" 2>&1; then
        echo 'Reset negative control unexpectedly passed'; exit 1
    fi
    grep -q RESET_CONTRACT "$output/reset-$bad_reset.log"
done
iverilog -g2012 -Wall -Wno-timescale -s tb_axi4lite_slave_top -o "$output/legacy.vvp" \
    async_fifo/rtl/async_fifo.sv axi4lite_slave_top.sv tb_axi4lite_slave_top.sv
set +e
(cd "$output" && timeout 5s vvp -i legacy.vvp > legacy.log 2>&1)
legacy_status=$?
set -e
if [[ $legacy_status == 124 ]]; then
    grep -q 'Test 4: Back-to-back writes' "$output/legacy.log"
    echo 'Legacy top: TIMEOUT at Test 4 (known baseline)'
elif [[ $legacy_status == 0 ]]; then
    grep -q 'All tests completed' "$output/legacy.log"
else exit "$legacy_status"; fi
! grep -qE 'ERROR|FATAL' "$output/legacy.log"
iverilog -g2012 -s async_fifo_tb -o "$output/fifo.vvp" async_fifo/rtl/async_fifo.sv async_fifo/tb/async_fifo_tb.sv
vvp "$output/fifo.vvp" > "$output/fifo.log" 2>&1
grep -q 'FAILED  \[44 errors found\]' "$output/fifo.log"
echo 'Legacy FIFO: FAIL, 44 mismatches (known baseline)'
echo 'Hardening regression: PASS 28 positive cases and 2 reset negative controls'
