param([int]$TimeoutMs=2000)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$run=Join-Path $env:TEMP 'axi-hardening-legacy'
New-Item -ItemType Directory -Force $run | Out-Null
foreach($top in @('tb_axi4lite_slave_top','async_fifo_tb')) {
    $sources=@(if($top -eq 'async_fifo_tb') { @("$repo/async_fifo/tb/async_fifo_tb.sv") } else { @("$repo/axi4lite_slave_top.sv","$repo/tb_axi4lite_slave_top.sv") })
    $exe=Join-Path $run "$top.vvp"
    & iverilog -g2012 -Wall -Wno-timescale -s $top -o $exe "$repo/async_fifo/rtl/async_fifo.sv" @sources
    if($LASTEXITCODE){ throw "$top compile failed" }
    $log=Join-Path $run "$top.log"
    $err=Join-Path $run "$top.err"
    $p=Start-Process vvp -ArgumentList '-i',$exe -WorkingDirectory $run -RedirectStandardOutput $log -RedirectStandardError $err -WindowStyle Hidden -PassThru
    if(!$p.WaitForExit($TimeoutMs)) {
        $p.Kill(); $p.WaitForExit(); Write-Output "$top TIMEOUT (baseline limitation)"
    } else { Write-Output "$top EXIT $($p.ExitCode)" }
    Get-Content $log
    Get-Content $err
}

