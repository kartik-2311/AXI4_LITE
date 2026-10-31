# AXI4-Lite slave and Boolean FPGA demonstration

AXI4-Lite slave with a CORE_CLK register bank, asynchronous FIFOs and a
standalone Real Digital Boolean-board demonstration.

- [Current RTL behavior and audit](docs/AUDIT.md), [assumptions](docs/ASSUMPTIONS.md)
  and [hardening changes](docs/CHANGELOG_AXI_HARDENING.md).
- [Boolean-board demo](boolean_demo/README.md): XC7S50-CSGA324,
  Vivado 2025.2, 100 MHz AXI / 75 MHz core, independent AW/W buffering,
  internal master, scoreboard, reset controller and LED status.
- [FPGA verification record](boolean_demo/RESULTS.md): simulations and routed
  timing passed; reviewed custom-FIFO CDC findings remain. Physical hardware
  testing **NOT RUN**.
- [LibreLane ASIC flow](librelane/README.md) and [historical results](librelane/results/README.md):
  physical checks passed, with 372 slew and 12 capacitance violations still open.
  RTL-to-netlist equivalence and complete CDC/reset signoff remain unproven.
- [Original project documentation](docs/README.md).

## Run the FPGA behavioral tests

Requires Bash, Icarus Verilog and Python 3. From the repository root:

```bash
bash boolean_demo/simulate.sh
```

Vivado primitive simulation, implementation, gated bitstream generation and
manual programming steps are documented in the demo README. Scripts currently
use the original Windows Vivado installation path; adjust installation and
checkout paths for your machine. Builds never program the board automatically.

## Published files

Source RTL, testbenches, constraints, reproducible scripts and concise results
are versioned. Bitstreams, checkpoints, GDS, simulator binaries/waveforms, raw
logs, tool installations, PDKs and local agent settings stay outside Git.
The older 100/50 MHz board experiment is preserved locally and superseded by
the 100/75 MHz demo. Existing protected FIFO RTL and historical tests are unchanged.

This is a demonstration and verification project, not complete AXI formal,
physical CDC/reset or tapeout signoff.
