# Boolean board AXI4-Lite demonstration

Target is xc7s50csga324-1 using Vivado 2025.2. This directory is independent
of the historical fpga/ demo, results/boolean/ outputs and ASIC LibreLane flow.
The canonical axi4lite_slave_top.sv and protected async_fifo/rtl/async_fifo.sv
are reused without edits. No physical hardware test or flash programming has
been performed: **physical hardware testing NOT RUN**.

## Board and behavior

The official Real Digital constraints were rechecked:
https://www.realdigital.org/downloads/8d5c167add28c014173edcf51db78bb9.txt

100 MHz oscillator F14 feeds an MMCM at 600 MHz VCO. BUFG outputs divide by
6 and 8 for **100 MHz ACLK and 75 MHz CORE_CLK**. Feedback is also buffered.
No frequency was lowered. Generated clocks are named explicitly and checked
against routed timing reports. Reset button 0 (J2) and lost MMCM lock jointly
assert reset asynchronously; each domain has a three-stage release pipeline.
Outstanding accepted or partly accepted transactions are discarded on joint
reset; registers, scoreboard and status restart at zero. Unilateral domain
reset is unsupported. Button bounce can cause multiple safe joint restarts.

- LED0 G1: sticky indication that a complete sweep passed.
- LED1 G2: sticky read-data mismatch, unexpected response or watchdog expiry.
- LED2 F1: heartbeat, full period approximately 1.34 seconds.
- Button 0 J2: restart and clear both sticky status bits.

Both PASS and FAIL may be on if failure occurs after a successful sweep.
LED1 must remain off. No UART, processor, external AXI wiring or slide-switch
input is needed. The internal master repeatedly exercises all 16 registers.
Each register gets a full write, partial-byte write (WSTRB=0101), zero-strobe
write, outside-window access and strict-misalignment access, with reads after
responses. A separate ACLK reference register model applies byte masks after
successful B handshakes. Read results are captured at handshake and compared
on the following cycle, reducing the old long response-to-watchdog path.
AW/W arrival order rotates across the sweep; B/R acceptance is delayed by 63
cycles. A 24-bit watchdog restarts on transaction progress and flags an operation
stuck for approximately 0.168 seconds while ACLK continues running.

The new endpoint has independent one-entry AW and W buffers because the
existing slave accepts them jointly. Each buffer captures only on its own
VALID/READY handshake. Once both are buffered, the unchanged slave receives
one pair; capacity is reserved until its B handshake. There is one outstanding
write and one outstanding read. B/R storage and completion reuse the existing
slave/FIFO mechanisms. No FIFO port, parameter or protected source is changed.

Map is 0x00..0x3f, 16 four-byte writable slots. Board endpoint uses OOR_RESP=2
(SLVERR), STRICT_ALIGN=1. Successful accesses return OKAY. Outside-window or
misaligned accesses return SLVERR, read zero and do not update the bank. The
underlying slave's original defaults remain unchanged for other consumers.

## Simulations

From WSL in C:/Users/karti/Projects/AXI4_LITE:

```bash
bash boolean_demo/simulate.sh
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\karti\Projects\AXI4_LITE\boolean_demo\simulate_board.ps1' > boolean_demo/build/xsim/launcher.log 2>&1
```

Create boolean_demo/build/xsim first on a fresh checkout. simulate.sh generates
an instrumented copy of the existing hardening testbench under build/; the
only mechanical changes select the new endpoint and route hierarchical core
checks through its slave instance. Existing tests/assertions are not edited
or weakened. Twenty fixed-seed cases test four clock ratios and five address
policies, independent AW/W acceptance, accepted payload capture, long B/R stalls,
response stability/accounting, actual core execution, partial/zero strobes,
mixed reads/writes, pointer wraps and reset with pending/stalled responses.

tb_demo tests the actual internal master/scoreboard at 100/75 MHz, repeated
sweeps, reset/restart, injected read corruption, sticky FAIL and a deliberately
blocked AW handshake to trigger the watchdog. Simulation shortens only the
watchdog parameter to 12 bits. Hardware retains 24 bits.

tb_board uses actual Vivado UNISIM MMCM/BUFG models and glbl, not a fake clock
generator. It tests button assertion between edges, loss of lock, synchronized
release, aborting traffic and successful sweeps afterward. Concurrent original
slave assertions are enabled in this simulation. Logs are retained under
build/simulation and build/xsim. Neither simulation is formal protocol signoff.

## Build and release

From Windows PowerShell at the repository root:

```powershell
New-Item -ItemType Directory -Force boolean_demo/build/vivado | Out-Null
& 'C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat' -mode batch -nojournal -log boolean_demo/build/vivado/vivado.log -source boolean_demo/build.tcl
```

The build produces synthesized.dcp, routed.dcp, clocks.rpt, timing.rpt,
cdc.rpt, methodology.rpt, drc.rpt, bus_skew.rpt, exceptions.rpt,
reset_paths.rpt and utilization.rpt under build/vivado. It does not create a
bitstream. build.tcl -tclargs implement is a diagnostic resume mode from the
unchanged synthesis checkpoint, not a substitute for synthesis after RTL edits.

After simulations and routed reports exist, from WSL:

```bash
bash boolean_demo/release.sh
```

review.py gates generated clock periods, setup/hold/pulse-width slack and
violation counts, internal timing completeness, DRC, bus skew, unexpected CDC
structures and the simulation evidence. It retains all CDC findings, including
critical classifications, and creates endpoint-by-endpoint review records.
release.py records source/report/checkpoint hashes. release.tcl checks the
approved checkpoint hash and timing again before generating axi_boolean_top.bit.
manifest.json and SHA256SUMS record source and bitstream identity. All generated
artifacts stay under build/ and are ignored by Git. No programming is automatic.

## CDC constraints and reviewed findings

There are no asynchronous clock-group exceptions. Both clocks are derived
from the same MMCM, so ordinary local paths remain timed. Exceptions identify
only existing FIFO memory write-clock startpoints to the opposite capture
clock and Gray/completion launch points to first-stage synchronizer D pins.
Each has a 10 ns datapath-only maximum delay (no greater than the faster clock
period), plus a hold-only exception on that crossing. Each independent Gray
bus has its own 10 ns bus-skew constraint. The first two synchronizer stages
are marked ASYNC_REG and SHREG_EXTRACT=NO in the netlist, without editing FIFO
RTL. Invalid or empty object matches abort the build.

The FWFT FIFO head is stable while not popped. Ownership/availability arrives
through the existing two-stage Gray synchronizers and registered empty flags
before the local consumer samples a valid head. The data-path bound prevents
unbounded physical delay on that bundled-data crossing; it is not permission
to constrain unrelated functional paths. The old 3.333 ns nearest-edge timing
requirement on a remote RAM write treated unavailable FIFO data as immediately
capturable. It is replaced only for these identified FIFO crossings, with the
stable-head protocol and all other synchronous paths retained. Read scoreboard
capture was also moved ahead of comparison in the new demo implementation.

Vivado cannot infer the custom FIFO ownership protocol. The raw routed report
contains CDC-1 critical findings on write-data/strobe/address-to-bank CE and
request-decode-to-response paths, CDC-15 warnings on FIFO bundled data and
CDC-6 warnings on Gray vectors. Every accepted record must match a known FIFO
RAM source and identified slave/scoreboard capture destination, or an existing
two-stage Gray/completion/reset synchronizer; unexpected structures block release.
The per-endpoint reasons are in build/review.json. No set_waiver, severity
override, report suppression or blanket clock cut is used. This is a scoped
structural review supported by simulation and delay bounds, not a formal CDC
proof; the report must not be described as zero-critical CDC signoff.

Two methodology warnings remain: TIMING-9 reflects those custom FIFO findings;
LUTAR-1 reports the OR of reset button and inverted lock feeding reset assertion.
This OR can only request a joint restart; release is synchronized and UNISIM
tests the assertion/release behavior. Physical minimum reset pulse width,
metastability/MTBF, button bounce and real board observation remain hardware
obligations. Inherited synthesis warnings about partially unreset core response
registers remain documented; neither protected source was changed to silence them.
LED output paths are asynchronous observation pins with no board receiver clock;
reset-button timing is excluded only to the release-pipeline CLR pins.

## Program the volatile FPGA

Connect a data-capable USB cable to PROG UART, set J15=USB, and turn power on.
Vivado Hardware Manager: Open Target / Auto Connect, select XC7S50, Program
Device, select boolean_demo/build/vivado/axi_boolean_top.bit. LED2 should blink,
LED0 should turn on and LED1 should remain off. Press button 0 to restart.
Do not program configuration flash for the initial test. A successful display
must be observed before changing physical hardware testing from NOT RUN.
