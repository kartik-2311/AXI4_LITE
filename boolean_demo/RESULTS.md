# Boolean demonstration verification record

Vivado 2025.2; xc7s50csga324-1. Implementation and simulations ran on
2026-10-30. Physical hardware testing: **NOT RUN**. No FPGA or flash was
programmed. The historical 50 MHz FPGA demo and ASIC GDS work are preserved.
All new files and outputs are in boolean_demo/.

## Source integrity and operating profile

- Protected FIFO SHA256 before/after:
  b54199597811fc3b12c500a66244013d7e02e8859d9b91218bbd17a8f9d4fa8e
- Canonical slave SHA256 before/after:
  4feba5ea3dad9e53355318ebc080d966adc6c98c20753cfea3da8d08325bb709
- Original RTL, ports, parameter defaults, tests and scripts were not edited.
- New endpoint buffers AW/W independently and forwards pairs to the original
  slave. No protected FIFO source was altered.
- MMCM feedback x6, output divides 6/8, BUFGs on both outputs and feedback.
  Routed clocks: AXI_CLK 10.000 ns, CORE_CLK 13.333 ns. No frequency reduction.
- Endpoint policy is strict alignment and SLVERR on outside-window/unsupported
  access; underlying slave defaults are preserved for other projects.

## Current-session tests

`bash boolean_demo/simulate.sh` exits zero. Summary log:

```
PASS board demo plus 20 endpoint protocol cases
```

`build/simulation/demo.log` ends:

```
PASS sweeps, partial writes, orderings, stalls, invalid access, reset, corruption, watchdog
boolean_demo/tb_demo.sv:28: $finish called at 267025000 (1ps)
```

Twenty additional logs under build/simulation contain seed 41584934 and PASS,
covering four clock ratios, five alignment/error policies and the existing
procedural assertions/transaction/core-register scoreboard. The adapter is
tested through genuinely separate AW and W handshakes; source testbenches are
unchanged. This is finite simulation coverage, not exhaustive AXI proof.

`simulate_board.ps1` compiles the original assertions and runs UNISIM MMCM/BUFG
models with glbl. Its build/xsim/launcher.log ends:

```
run -all
PASS UNISIM MMCM/BUFG, reset button, lost lock, synchronized releases, board sweeps
$finish called at time : 222975 ns
exit
```

This verifies actual clock primitive simulation and the board reset controller,
including reset during traffic and restart after clock-lock loss. The inherited
legacy top/FIFO regressions were not rerun: their known failures are recorded
in docs/AUDIT.md and librelane/NOTES.md; they are not represented as passes here.

## Implementation reports

All reports are under build/vivado; routed.dcp is the implemented checkpoint.

| Check | Result |
|---|---|
| Setup slack / failing endpoints | +2.496 ns / 0 |
| Hold slack / failing endpoints | +0.046 ns / 0 |
| Pulse-width slack / failing endpoints | +3.000 ns / 0 |
| Unclocked / unconstrained internal endpoints | 0 / 0 |
| Physical DRC errors | 0 |
| Gray bus skew | All six independently constrained buses pass |
| Methodology critical warnings/errors | 0 / 0 |
| Methodology warnings | LUTAR-1 and TIMING-9, retained and reviewed |

Two early constraint diagnostics stopped before implementation: an exact FIFO
name match missed flattened objects, then an incomplete bus-skew selector was
rejected. attempt01/02 logs are retained. Queries were corrected to infer the
actual RAM leaf clock pins, use complete Gray bus sources and group each bus
by its own synchronizer. Earlier incorrect parent WCLK selections and mixed
clock bus-skew warnings are absent from the final build. No violation was hidden
by clock groups or a whole-domain false path. The final Tcl build exits zero
with ROUTED_CHECKPOINT_READY and creates no bitstream before review.

`reset_paths.rpt` includes reset pipeline timing; global setup/hold reports also
cover the synchronous reset release paths. Asynchronous assertion has a scoped
button-to-CLR exception. LED pins are asynchronous observation outputs.

## CDC review and limitations

The raw CDC report is deliberately retained, including its severities:

| Rule | Raw severity | Endpoint records |
|---|---|---:|
| CDC-1 custom RAM/control structure | Critical | 513 |
| CDC-15 FIFO bundled data | Warning | 610 |
| CDC-6 Gray vectors | Warning | 6 |
| CDC-3 existing synchronized single-bit paths | Info | 6 |
| CDC-9 reset synchronizers | Info | 2 |

All 1,137 detailed records are classified in build/review.json. RAM findings
are restricted to actual FIFO memory clock sources and the identified local
register-bank D/CE, synchronous R/S, read-response or captured master-response
pins. No asynchronous CLR/PRE sink is accepted as bundled data. Gray MSBs can
be represented as binary-pointer MSBs after synthesis because those bits are
identical; all six Gray buses and the completion synchronizer retain two FF
stages and ASYNC_REG. A 10 ns datapath bound and per-bus skew bound are applied.
No generic CDC critical finding outside these reviewed structures is accepted.

This review relies on the protected FIFO's stable-head/ownership protocol and
the tested control conditions. It is not a zero-critical CDC tool result or a
formal metastability proof. TIMING-9 describes those same custom FIFO crossings.
LUTAR-1 describes the reset-button/lock OR gate; reset-pulse integrity on actual
hardware still requires observation/implementation judgment. Unused MMCM outputs
and inherited core response-register reset warnings remain visible in logs.

## Release and artifacts

`bash boolean_demo/release.sh` runs the report/simulation review and hashes all
RTL, test sources, scripts, constraints, reports and checkpoint. Vivado verifies
the approved routed-checkpoint hash and timing again before writing the bitstream.
Final release.log contains `Bitgen Completed Successfully` and `BITSTREAM_READY
100MHz/75MHz`. No hardware programming commands are present.

- Programming file: build/vivado/axi_boolean_top.bit.
- Full source/report/checkpoint/bitstream hashes: build/SHA256SUMS.
- JSON manifest with per-endpoint review and physical-testing status:
  build/manifest.json.
- Authoritative current bitstream hash: build/approval.log `BITSTREAM_HASH`.

Final bitstream: 2,192,139 bytes, SHA256
`f93b298c9317a30aacb4d52af7970e18e0f5be4613e391e2ff3651472a86bbc0`.
`sha256sum -c boolean_demo/build/SHA256SUMS` passes for every recorded source,
report, checkpoint and bitstream. Two additional in-memory negative controls
confirm that the release review rejects negative timing and an unreviewed raw
CDC source; original reports were not altered (build/release-negative-tests.log).

Build outputs are excluded from the source publication; regenerate them locally. The applicable parent AGENTS.md requested graphify update; the attempt
returned 127 because that CLI is unavailable, recorded in build/graphify-update.log.
No graph was created or changed. FPGA validation is independent of that index.
