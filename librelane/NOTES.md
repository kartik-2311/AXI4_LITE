# AXI4-Lite LibreLane execution notes

## Scope and environment

Branch: rtl2gds, based on axi-hardening at 1d66e6d. The existing uncommitted
FPGA files and line-ending-only changes are preserved. No RTL edit has been
made. All new ASIC project files are under librelane/, except the required
root .gitignore entries. Tools, virtualenv, PDK, logs and runs are ignored.

Environment is Ubuntu 26.04 in native WSL2, kernel
6.18.33.2-microsoft-standard-WSL2, x86_64 GNU/Linux. Docker and Nix commands
are absent. Noninteractive sudo is unavailable. No global packages or system
configuration were changed.

Python 3.14.4 initially lacked ensurepip and development headers. A local
virtualenv was created; system pip was used only to bootstrap installation
inside that environment. libpython3.14-dev was downloaded and extracted under
tools/python-dev, not installed system-wide. CPATH supplied the local headers.
The final pip command installed LibreLane 3.0.17 and Ciel 2.6.1 successfully;
logs/install-final.log and logs/venv-version.log preserve that evidence.

For a coherent EDA toolchain, execution uses the official LibreLane 3.0.17
Linux AppImage, which includes Python 3.13.9 and Ciel 2.4.0. Docker is not
needed for this native bundled environment. The AppImage SHA256 matches the
release asset digest:

```
c8ef5ae26b1fc53dd1dd30fe2f1a1da6ab0fdf471dd5a94c2b85d2b3db36833c
```

Source: https://github.com/librelane/librelane/releases/tag/3.0.17
Installation guide:
https://librelane.readthedocs.io/en/stable/installation/appimage_installation/installation_linux.html

WSL DNS was intermittent during downloads. curl --resolve used IP addresses
returned by Windows DNS for individual downloads; no hosts/resolver file was
changed. A first AppImage invocation with TMPDIR on the Windows mount failed
because FUSE cannot mount there. Using the normal Linux runtime temporary
directory works. Those runtime mount points are managed by AppImage; project
inputs, downloaded tools, PDK and persistent logs remain under librelane/.

## Baseline before any LibreLane flow

Command: bash librelane/regression.sh > librelane/logs/baseline.log 2>&1

Result: process exit 0 with comparison to the known baseline. This does not
classify failing legacy tests as passes. The summary log contains only three
lines:

```
Legacy top: TIMEOUT at Test 4 (known baseline)
Legacy FIFO: FAIL, 44 mismatches (known baseline)
Hardening regression: PASS 28 positive cases and 2 reset negative controls
```

Per-case commands and logs are produced by regression.sh under logs/regression.
No existing testbench or script was edited.

## Step 0 smoke-test gate

PDK root: /mnt/c/Users/karti/Projects/AXI4_LITE/librelane/pdk
PDK variant: sky130A. LibreLane requested revision
8afc8346a57fe1ab7934ba5a6056ea8b43078e71 through Ciel.

Command:

```
librelane/tools/librelane-devshell-x86_64.AppImage python3 -m librelane --pdk sky130A --pdk-root "$PWD/librelane/pdk" --smoke-test > librelane/logs/smoke.log 2>&1
```

The installed CLI source confirms --smoke-test copies the bundled spm example
and executes its config. It cleans its temporary example directory afterward;
the persistent launcher output is logs/smoke.log. No design config or design
implementation run is authorized past this gate until that test completes.

Result: PASS, completed 2026-10-29 14:08:47 UTC. logs/smoke.log ends with
`INFO Smoke test passed.` Magic and KLayout DRC, LVS and antenna checkers
completed. CLI warnings about LEF58 rules and unspecified IR-drop supply-source
locations remain; smoke-test success is an environment check, not AXI signoff.

## Inputs and constraints

Explicit ASIC design file list (no wildcards):

1. async_fifo/rtl/async_fifo.sv: FIFO, RAM, Gray pointers, 2FF synchronizers.
2. axi4lite_slave_top.sv: canonical top, ACLK/CORE_CLK clocks,
   ARESETn/CORE_RESETn active-low resets, register bank and AXI channels.

Excluded: all tb/ files, async_fifo/tb/async_fifo_tb.sv,
tb_axi4lite_slave_top.sv, test_sva.sv, test_icarus_assert.sv, alternative
axi4lite_slave_top_simple/fixed/final_check snapshots and the FPGA wrapper/demo.
The existing __ICARUS__ guard excludes the concurrent SVA block without editing
RTL; VERILOG_DEFINES supplies it for both lint and synthesis. No testbench,
bind checker or FPGA primitive enters the ASIC source list.

Baseline lint command (inside AppImage):
`verilator --lint-only -Wall -Wno-fatal -D__ICARUS__ --top-module axi4lite_slave_top async_fifo/rtl/async_fifo.sv axi4lite_slave_top.sv`.
Verilator 5.044: zero errors, seven warnings (one DECLFILENAME, four
WIDTHEXPAND in FIFO pointer arithmetic, two UNUSEDSIGNAL on decode fields).
No RTL changes. Full output: logs/lint.log. -Wno-fatal records warnings;
latch/multidriver checks and actual flow error checkers remain enabled.

Target clocks: 100 MHz ACLK / 50 MHz CORE_CLK, taken from the most recent
implemented Boolean profile (fpga/README.md). Historical documentation names
75 MHz CORE_CLK. ASIC clocks are treated as independent, not MMCM-related.
The SDC sets both real periods; Classic CLOCK_PERIOD=10 is its nominal target.
Reset assertion is joint and release synchronous to each domain, as required
by docs/ASSUMPTIONS.md. Reset recovery/removal paths are externally guaranteed
and excluded by the requested reset false path. All data I/O belongs to ACLK.
The example's lsearch expression does not correctly subtract a list of clock
and reset ports; the SDC instead explicitly lists the real AXI data inputs.

Every initial JSON variable was checked against installed Classic flow
get_all_config_variables(): logs/config-api.log reports Missing: set().
VERILOG_DEFINES is the current name (SYNTH_DEFINES is deprecated).
USE_SLANG is available if a parser error requires it. Default warning policy
ERROR_ON_LINTER_WARNINGS=False is retained; no error check is disabled.

OpenSTA 2.7.0 implements -ignore_clock_latency rather than -datapath_only.
Its set_clock_groups supports -allow_paths. The SDC uses asynchronous groups
with -allow_paths, explicit hold cuts and fixed latency-independent 10 ns max
delays in both directions. This bounds every clock-crossing datapath, including
Gray-pointer synchronizers and bundled FIFO storage, without relying on fragile
flattened instance names. Plain asynchronous groups would override max_delay
and silently remove the Gray bounds. Clock-relative synchronous setup/hold
relationships are not used between the domains. Signoff must confirm these
exceptions and actual path requirements; no max-delay claim is made yet.

## Flow iterations

Iteration 1: initial verified config, density 45%, utilization 35%, clocks 10/20 ns.
Command recorded in README.md; logs/axi-01.log holds the launcher output.

Iteration 1 final RCX timing: FAIL, worst setup slack -0.448305 ns
(max_ss_100C_1v60), 646 summed setup-violation counts across nine corners;
hold clear at all corners (minimum +0.105903 ns). The worst path runs from
write FIFO memory through decode/write-enable logic under the explicit 10 ns
CDC max delay, not a synchronous inter-clock phase relationship.

Iteration 2 changes exactly one variable: PL_RESIZER_SETUP_SLACK_MARGIN from
its installed default 0.05 ns to 1.0 ns. This asks the post-CTS resizer to leave
more margin for extracted RC. Clock periods, max-delay limits, utilization and
density are unchanged. Variable verified in the installed OpenROAD step/API.
axi-02 resumes at OpenROAD.ResizerTimingPostCTS from axi-01's CTS state, since
all inputs and settings before that step are identical. A fresh full run using
the final config is reproducible without that resume option.

Iteration 1 was aborted after recording its failed extracted timing; its
remaining Magic process was terminated and all run files were retained.
Iteration 2 meets timing at all nine corners: worst setup +0.328192 ns,
worst hold +0.104602 ns, zero setup/hold violations. Both DRC checkers pass.

Magic's default DEF/LEF-based extraction repeatedly searches PDK cell .ext
files on the Windows-mounted filesystem (observed pending open in the hvl
directory for an hd tap-cell .ext). Iteration 3 changes one documented variable,
MAGIC_EXT_USE_GDS=False to True (verified in installed Magic.SpiceExtraction).
MAGIC_EXT_ABSTRACT remains False; no checker or uniqueness setting is disabled.
This extracts actual GDS geometry directly instead of reconstructing from DEF/LEF.
axi-03 resumes Magic.SpiceExtraction from axi-02/31-checker-klayoutdrc/state_out.json.
Timing/DRC geometry is unchanged; report provenance is retained from axi-02.

Iteration 2 was aborted after recording clean timing/DRC; its default extraction
process was stopped. Iteration 3 confirmed the same missing .ext search issue
even with GDS: Magic searched sky130_fd_sc_ls/mag for sky130_fd_sc_hd__fill_1.ext.
It was stopped without treating pending LVS as PASS.

Iteration 4 changes only MAGICRC to dir::magicrc (installed PDK path variable).
The new rc file sources the unmodified sky130A technology rc and the normal
step environment. Only for GDS-based Magic.SpiceExtraction, it restricts cell
search to the current directory. The self-contained GDS already loads every
referenced cell; searching unrelated PDK libraries for missing extraction caches
is unnecessary. All extraction/uniqueness/LVS/DRC settings remain enabled and
unchanged. Other Magic steps retain the PDK's original search paths. axi-04
resumes from the same clean routed/DRC state as axi-03; no geometry is modified.

## Final result and stopping criteria

axi-04 completed successfully at 2026-10-29 14:47:57 UTC. Its state inherits
the unchanged routed GDS and extracted timing/DRC from axi-02, then performs
GDS transistor extraction and Netgen LVS. This is explicit continuation
provenance, not substitution of old results for unrun checks. Final metrics
and raw reports are copied into results/. There were **no RTL edits** and
no existing testbench/script edits.

| Check | Result |
|---|---|
| Magic DRC / KLayout DRC / detailed-route DRC | 0 / 0 / 0 |
| LVS device/net/property/pin differences | 0; circuits match uniquely |
| Antenna violating nets / pins | 0 / 0 |
| Setup / hold violations across nine corners | 0 / 0 |
| Worst setup / CDC-delay slack | +0.328192 ns |
| Worst hold slack | +0.104602 ns |
| ACLK worst setup / hold | +0.510509 / +0.108658 ns |
| CORE_CLK worst setup / hold | +8.449824 / +0.104602 ns |
| Magic/KLayout GDS XOR differences | 0 |
| Standard cells excluding filler | 9,467 |
| Total physical instances including filler | 38,768 |
| Standard-cell area excluding filler | 95,718.1 um^2 |
| Core / die area | 196,808 / 212,160 um^2 |
| Final utilization excluding filler | 48.6354% |

All nine corner-by-clock tables are in results/README.md; machine-readable
data and provenance are in results/signoff.json. The final GDS is 12,403,648
bytes and loads headlessly in KLayout with exactly one top cell named
axi4lite_slave_top and a nonempty bounding box. SHA256:

```
f3dd07cf580c75b692b62529908727f6fc61b8dbd0af5e9fa8d78682b312950f
```

The collector checks 5,409 actual inter-clock paths across nine corners. Every
reported crossing uses explicit max_delay, and no cross-clock hold paths appear.
Both asynchronous groups and applied constraints are preserved in
results/applied-constraints.sdc and described in the signoff summary.

Final JSON settings are config.json: two source files, the assertion-exclusion
define, both clock ports, nominal period 10, custom PNR/signoff SDC, relative
sizing, utilization 35, density 45, linter enabled, placement setup margin 1.0,
GDS extraction enabled, and the scoped Magic rc file. No clock period or delay
limit was relaxed. Every nondefault variable was checked against the installed
Classic schema; native OpenSTA option equivalents are recorded above.

## Regression and verification evidence

Final command: bash librelane/regression.sh > librelane/logs/final-regression.log 2>&1.
Exit 0, and cmp of baseline.log and final-regression.log confirms matching
summaries. Last available lines (the log contains only three):

```
Legacy top: TIMEOUT at Test 4 (known baseline)
Legacy FIFO: FAIL, 44 mismatches (known baseline)
Hardening regression: PASS 28 positive cases and 2 reset negative controls
```

Collection command and exit-0 evidence:

```
librelane/tools/librelane-devshell-x86_64.AppImage python3 librelane/collect_results.py librelane/runs/axi-04 librelane/runs/axi-02 > librelane/logs/collect.log 2>&1
```

collect.log contains two lines:

```
PASS: axi4lite_slave_top.gds, top=axi4lite_slave_top, nine corners, zero required error counts
{"magic__drc_error__count": 0, "klayout__drc_error__count": 0, "route__drc_errors": 0, "design__lvs_error__count": 0, "antenna__violating__nets": 0, "antenna__violating__pins": 0, "timing__setup_vio__count": 0, "timing__hold_vio__count": 0, "design__xor_difference__count": 0}
```

The collector's negative control rejected the unfinished/failed first run;
logs/collector-negative.log records the expected assertion failure. Source
comparison against HEAD ignoring only existing line-ending differences confirms
unchanged RTL; exact current RTL hashes are in results/signoff.json.

## Unresolved limitations

The explicit Step 3 stopping criteria are met. The flow also reports **372
max-slew and 12 max-capacitance violations** at the SS corners. These remain
electrical design-rule warnings; they were not waived, hidden or called PASS.
Do not classify this result as fully tapeout-ready. Further electrical closure
would be a subsequent task beyond the specified stopping point.

Gate-level simulation is NOT RUN: the new checker relies on RTL-only internal
hierarchy removed by synthesis, and the unchanged legacy bench already races
and hangs. It is not a directly usable gate-level signoff bench. RTL simulation
and GDS-to-synthesized-netlist LVS both run; neither is formal RTL/netlist
equivalence. Physical metastability/MTBF and reset recovery assumptions remain
external obligations. The macro has no pad ring, package or manufacturing
integration. IR-drop source locations were not supplied; the PDK flow's
IR-drop estimate is not package/power-grid signoff. No run output, PDK or
virtualenv is committed; only the final GDS and small reports are deliverables.
