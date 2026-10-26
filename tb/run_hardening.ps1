param([int]$Mode=0, [switch]$Policy, [switch]$HoldInputs)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$run=Join-Path $env:TEMP 'axi-hardening-tests'
New-Item -ItemType Directory -Force $run | Out-Null
$failures=0
foreach ($clock in @(@(15,15),@(15,5),@(5,15),@(5,7))) {
    $argsList=@('-g2012','-Wall','-Wno-timescale','-s','tb_axi4lite_hardening',"-Ptb_axi4lite_hardening.AH=$($clock[0])","-Ptb_axi4lite_hardening.CH=$($clock[1])")
    $policies=if($Policy){ @('0,0','1,2','0,2') } else { @('0,0') }
    foreach($policyText in $policies) {
        $policyCase=$policyText.Split(',')
        $exe=Join-Path $run "test-$($clock[0])-$($clock[1])-$($policyCase[0])-$($policyCase[1]).vvp"
        $compile=$argsList + @("-Ptb_axi4lite_hardening.ALIGN=$($policyCase[0])","-Ptb_axi4lite_hardening.OOR=$($policyCase[1])")
        if($Policy){ $compile+= '-DPOLICY' }
        & iverilog @compile -o $exe "$repo/async_fifo/rtl/async_fifo.sv" "$repo/axi4lite_slave_top.sv" "$PSScriptRoot/tb_axi4lite_hardening.sv"
        if($LASTEXITCODE){ throw 'compile failed' }
        & vvp -i $exe "+MODE=$Mode" "+HOLD=$([int][bool]$HoldInputs)"
        if($LASTEXITCODE){ $failures++ }
    }
}
if($failures){ throw "$failures hardening cases failed" }

