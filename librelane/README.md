# AXI4-Lite RTL to GDSII with LibreLane

Run from the repository root in Linux/WSL2. The canonical slave and FIFO are
the only synthesis inputs; FPGA wrapper, testbenches and SVA are excluded.
config.json is for the Classic flow, sky130A, nominal 100 MHz ACLK / 50 MHz
CORE_CLK. See NOTES.md for assumptions, warnings and iteration history.

## Install and verify the environment

On a fresh Ubuntu installation, provision Python venv/pip/development headers,
Tk, git, curl, a compiler, FUSE and bubblewrap using the normal package manager.
This session instead extracted missing Python headers locally because sudo
required interactive authentication. The setup history is recorded in NOTES.md.

```bash
mkdir -p librelane/tools librelane/logs librelane/pdk
python3 -m venv librelane/.venv
librelane/.venv/bin/python -m pip install --upgrade librelane==3.0.17
curl -fL --retry 3 -o librelane/tools/librelane-devshell-x86_64.AppImage https://github.com/librelane/librelane/releases/download/3.0.17/librelane-devshell-x86_64.AppImage
echo 'c8ef5ae26b1fc53dd1dd30fe2f1a1da6ab0fdf471dd5a94c2b85d2b3db36833c  librelane/tools/librelane-devshell-x86_64.AppImage' | sha256sum -c -
chmod +x librelane/tools/librelane-devshell-x86_64.AppImage
librelane/tools/librelane-devshell-x86_64.AppImage python3 -m librelane --version
```

The AppImage provides the coherent native EDA environment and its bundled
Python/LibreLane. All invocations remain in WSL2; Docker is not used. Leave
AppImage's temporary runtime mounts on the native Linux filesystem rather
than setting TMPDIR to a Windows-mounted path.

## Baseline and mandatory SPM gate

```bash
bash librelane/regression.sh > librelane/logs/baseline.log 2>&1
librelane/tools/librelane-devshell-x86_64.AppImage python3 -m librelane --pdk sky130A --pdk-root "$PWD/librelane/pdk" --smoke-test > librelane/logs/smoke.log 2>&1
```

The installed --smoke-test command copies and runs the bundled spm example.
Ciel automatically fetches the matching PDK revision. **Do not proceed until
the smoke-test command exits zero and its log says Smoke test passed.**
The baseline script reports inherited legacy FAIL/TIMEOUT results explicitly.

## Lint and Classic implementation

```bash
librelane/tools/librelane-devshell-x86_64.AppImage verilator --lint-only -Wall -Wno-fatal -D__ICARUS__ --top-module axi4lite_slave_top async_fifo/rtl/async_fifo.sv axi4lite_slave_top.sv > librelane/logs/lint.log 2>&1
librelane/tools/librelane-devshell-x86_64.AppImage python3 -m librelane --flow Classic --pdk sky130A --pdk-root "$PWD/librelane/pdk" --run-tag axi-01 librelane/config.json > librelane/logs/axi-01.log 2>&1
```

Use a new run tag for each iteration to preserve evidence. SDC and config
changes must be recorded in NOTES.md before rerunning. Do not disable signoff
checkers or edit behavior to meet timing. Run outputs, PDK and environment
directories are ignored; only small final deliverables belong in results/.
Rerun regression.sh after any RTL edit and at final verification.

Iteration 2 in this session reuses the unchanged CTS checkpoint:

```bash
librelane/tools/librelane-devshell-x86_64.AppImage python3 -m librelane --flow Classic --pdk sky130A --pdk-root "$PWD/librelane/pdk" --run-tag axi-02 --from OpenROAD.ResizerTimingPostCTS --with-initial-state librelane/runs/axi-01/35-openroad-cts/state_out.json librelane/config.json > librelane/logs/axi-02.log 2>&1
```

To reproduce independently, use the normal full-flow command with the final
config and a fresh tag instead. After a successful flow:

```bash
librelane/tools/librelane-devshell-x86_64.AppImage python3 librelane/collect_results.py librelane/runs/axi-04 librelane/runs/axi-02 > librelane/logs/collect.log 2>&1
bash librelane/regression.sh > librelane/logs/final-regression.log 2>&1
```

The collector refuses unfinished/error-containing runs, verifies all nine
corners and per-clock reports, checks actual CDC paths use max delays with no
cross-clock hold checks, loads GDS with KLayout, and requires the expected top
cell before copying the final GDS and small reports into results/.

The final signoff continuation used the existing clean routed/DRC state, adding
GDS-based extraction and the scoped Magic search-path fix:

```bash
librelane/tools/librelane-devshell-x86_64.AppImage python3 -m librelane --flow Classic --pdk sky130A --pdk-root "$PWD/librelane/pdk" --run-tag axi-04 --from Magic.SpiceExtraction --with-initial-state librelane/runs/axi-02/31-checker-klayoutdrc/state_out.json librelane/config.json > librelane/logs/axi-04.log 2>&1
```

For a fresh full run, pass its one run directory to collect_results.py; the
second directory is needed only when timing/DRC came from a resumed parent.
All report provenance is recorded in results/signoff.json. No prior-run data
is substituted for missing signoff results: the continuation inherits the
unchanged routed GDS and its timing/DRC state, then performs actual GDS LVS.

**Result:** the specified DRC/LVS/antenna/setup/hold stopping criteria pass.
372 max-slew and 12 max-capacitance violations remain as reported electrical
warnings. This is not a fully tapeout-ready signoff. They were not waived or
hidden, and iteration stopped at the user's explicit criteria.

This is ASIC standard-cell GDS, not an FPGA programming file or a complete
pad-ring/package design. Reset sequencing and external I/O timing are interface
assumptions; inspect final signoff results before using the layout.
