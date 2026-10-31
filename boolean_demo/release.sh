#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
python3 boolean_demo/release.py > boolean_demo/build/approval.log
powershell.exe -NoProfile -Command 'Set-Location "C:\Users\karti\Projects\AXI4_LITE\boolean_demo\build\vivado"; & "C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat" -mode batch -nojournal -log "C:\Users\karti\Projects\AXI4_LITE\boolean_demo\build\vivado\release-vivado.log" -source "C:\Users\karti\Projects\AXI4_LITE\boolean_demo\release.tcl"; exit $LASTEXITCODE' > boolean_demo/build/vivado/release.log 2>&1
grep -q '^BITSTREAM_READY' boolean_demo/build/vivado/release.log
python3 boolean_demo/release.py --record-bit >> boolean_demo/build/approval.log
