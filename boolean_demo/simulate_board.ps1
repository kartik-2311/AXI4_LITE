$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$output=Join-Path $PSScriptRoot 'build/xsim'
$bin='C:/AMDDesignTools/2025.2/Vivado/bin'
New-Item -ItemType Directory -Force $output | Out-Null
Push-Location $output
try {
    & "$bin/xvlog.bat" -sv "$root/async_fifo/rtl/async_fifo.sv" "$root/axi4lite_slave_top.sv" "$PSScriptRoot/rtl/endpoint.sv" "$PSScriptRoot/rtl/demo.sv" "$PSScriptRoot/rtl/board_top.sv" "$PSScriptRoot/tb_board.sv" 'C:/AMDDesignTools/2025.2/Vivado/data/verilog/src/glbl.v'
    if($LASTEXITCODE){throw 'xvlog failed'}
    & "$bin/xelab.bat" -debug typical -L unisims_ver tb_board glbl -s board_sim
    if($LASTEXITCODE){throw 'xelab failed'}
    & "$bin/xsim.bat" board_sim -runall
    if($LASTEXITCODE){throw 'xsim failed'}
} finally {Pop-Location}
