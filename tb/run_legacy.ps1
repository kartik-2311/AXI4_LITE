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
    $timedOut=!$p.WaitForExit($TimeoutMs)
    if($timedOut) {
        $p.Kill(); $p.WaitForExit(); Write-Output "$top TIMEOUT (baseline limitation)"
    } else { Write-Output "$top EXIT $($p.ExitCode)" }
    $stdout=Get-Content $log -Raw
    $stderr=Get-Content $err -Raw
    Write-Output $stdout
    Write-Output $stderr
    if($stderr -or ($stdout -match '\b(FATAL|ERROR)\b')) { throw "$top introduced an error" }
    if($top -eq 'tb_axi4lite_slave_top') {
        if($timedOut -and $stdout -notmatch 'Test 4: Back-to-back writes') { throw 'legacy top regressed before baseline stopping point' }
        if(!$timedOut -and ($p.ExitCode -ne 0 -or $stdout -notmatch 'All tests completed')) { throw 'legacy top did not finish successfully' }
    } else {
        $oldFailure=$stdout -match 'FAILED\s+\[44 errors found\]' -and $stdout -match 'Writes completed\s+: 44' -and $stdout -match 'Reads completed\s+: 0'
        $improved=$stdout -match 'RESULT:\s+PASSED' -and $stdout -notmatch '\[FAIL\]'
        if($timedOut -or $p.ExitCode -ne 0 -or !($oldFailure -or $improved)) { throw 'legacy FIFO regression differs from known baseline' }
    }
    Write-Output "$top BASELINE MATCH OR BETTER (known failures remain visible)"
}

