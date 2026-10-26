# AXI hardening audit

Phase 0 references below refer to the preserved baseline commit `e8ac44d`.
No RTL changed during this audit. The supplied directory had no Git metadata;
a baseline repository was initialized before creating `axi-hardening`.

## Toolchain and baseline

Icarus Verilog 12.0 (devel) and vvp are installed at C:/iverilog/bin.
No Makefile, regression scripts, formal/SymbiYosys configuration, dedicated
lint tool or CDC tool was found. Compile the canonical design explicitly:

```
iverilog -g2012 -Wall -Wno-timescale -s tb_axi4lite_slave_top -o baseline.vvp async_fifo/rtl/async_fifo.sv axi4lite_slave_top.sv tb_axi4lite_slave_top.sv
vvp -i baseline.vvp
```

Baseline compilation succeeds. A bounded 5-second run times out; a second
unbuffered 2-second run reaches Test 4 and hangs. Last output:

```
Test 4: Back-to-back writes to registers 1 and 2
Write transaction: addr=00000008 data=cafebabe strb=f
```

The legacy test changes inputs at posedges, and waits for B responses after
they can already have handshaken (tb_axi4lite_slave_top.sv:170-203). It is
preserved unchanged; timeout is baseline behavior, not a passing regression.
The standalone FIFO testbench also compiles with Icarus. Its result is recorded
with subsequent regression results. Alternative top files define the same
module name and must not be compiled together. test_sva.sv is a simulator
capability probe; the canonical DUT excludes concurrent SVA under Icarus.

## FIFO contract

async_fifo/rtl/async_fifo.sv:23-29: synchronous writes, combinational read
of mem[rd_addr], hence FWFT. Read data is meaningful only when !rd_empty.
rd_addr stays fixed without a legal pop, so a valid head stays stable.
:131-147: pop is rd_en && !rd_empty at a read-clock edge; pointer and empty
update on that edge, and the next head is combinationally available afterward.
:87-105: writes are gated by !full; full is computed from the next local
pointer and synchronized remote Gray pointer. :50-60 and :227-247:
two-flop remote pointer synchronization, followed by registered local flags.
Empty/full deassertion can therefore lag remote progress by several local
edges; conservatism does not imply data loss. :93-101 and :135-143 reset
pointers and flags, not RAM. Joint reset flushes ownership; one-sided reset
can invalidate pointer ownership and is unsupported. No concrete FIFO defect
has been demonstrated. Do not modify async_fifo.

## P1 through P7 before fixes

- **P1 FAIL**: axi4lite_slave_top.sv:267 uses !wr_empty as completion;
  :153-160 synchronizes this possibly one-core-cycle pulse; :185 enters
  SEND_BRESP on that level. It can be missed or refer to stale work. One
  write at most is accepted until B handshake (:175-193).
- **P2 FAIL overall; B stability PASS**: BVALID is SEND_BRESP and remains
  there until BREADY, with constant BRESP (:143-144, :189-193). Preserve
  this storage/state structure. R response FIFO rd_en is tied high (:123),
  while RVALID/payload use its head (:210-211): stalls consume the response.
- **P3 FAIL**: lost read responses as above; read request rd_en tied high
  (:96) also consumes requests while the core gives writes priority
  (:277-292). Response full is not checked before executing a read (:292-298).
  Missing completion pulses can strand writes. There is no B response FIFO.
- **P4 UNPROVEN for pairing; joint acceptance is legal by inspection**:
  :139-140 coordinates readiness, so neither channel handshakes alone.
  With a legal master keeping VALID until acceptance, all orders can meet.
  **Payload capture FAIL**: :135 pushes a cycle after acceptance while :136
  still uses live AWADDR/WDATA/WSTRB, which may change after handshake.
  No separate AW/W buffers are necessary if enqueue occurs at acceptance.
- **P5 FAIL**: :204-207 similarly delay AR enqueue using live ARADDR;
  response drain and request arbitration defects additionally break accounting.
- **P6 UNPROVEN policy, duplicated decode confirmed**: :282-285 and :294
  separately index [5:2]. Actual map has 16 writable words, no holes or RO
  entries; high bits alias, low two bits ignored. All responses are OKAY.
  :287-289 correctly update only WSTRB-selected byte lanes (**PASS**).
- **P7 UNPROVEN**: resets independently clear each domain but no interface
  contract/check enforces joint assertion; unilateral reset loses ownership.
  Gray pointers use existing 2FF synchronizers; physical CDC constraints and
  reset recovery/removal timing have not been checked.

## Scope and phase dependencies

Only canonical top RTL, added tb/checker/runner and the requested documents
need change. Existing ports, parameters, alternate snapshots, FIFO, and legacy
tests remain intact. P2 B-state retention and WSTRB behavior already pass and
must be preserved. P4 acceptance-cycle enqueue is necessary for P1 payload
integrity and is scheduled with Phase 2; AR enqueue accompanies Phase 3/P5.
No register or state is required for payload capture: FIFO storage is reused.

## Phase 1 failing traces on unchanged RTL

Added procedural checker and transaction/register reference scoreboard because
Icarus excludes the DUT SVA. Seed is fixed and printed: 0x41584934.
`tb/run_hardening.ps1` runs 1:1, 1:3, 3:1 and 7:5 clock ratios (frequency).

- MODE=1, changing payload immediately after acceptance: all four ratios fail
  P4 capture. At 1:1, t=525000 ps: AW=1 EXEC=0 B=0, payload mismatch.
- MODE=1 -HoldInputs isolates completion: 1:3 fails watchdog at t=599985000 ps,
  AW=1 EXEC=1 B=0. Other three ratios pass this isolated write test. This
  confirms the completion pulse can disappear at faster core clock rates.
- MODE=2 -HoldInputs isolates read stalls: all four ratios fail P2. At 1:1,
  t=705000 ps: AR=1 RE=1 R=0; RVALID disappears while RREADY remains low.
- Legacy FIFO test compiles and exits zero but reports 44 mismatches, writes=44,
  reads=0. Its read task samples after advancing the FWFT pointer, rather than
  sampling the head at the pop edge. This does not prove a FIFO RTL defect;
  the legacy test and FIFO remain unchanged.

The new checks intentionally fail on the baseline. Later phase gates run
the relevant new tests plus the unchanged legacy regression; already failing
baseline tests are compared by their failures rather than treated as passes.

## Phase 2 gate

MODE=1 without HOLD passes 4/4 ratios, including the previously lost
completion at 1:3. The unchanged legacy top still times out at Test 4 and
the standalone FIFO still reports exactly 44 mismatches. No baseline result
became worse. Read failures remain scheduled for Phase 3.

## Phase 3 gate

Full mixed-traffic MODE=0 and isolated read MODE=2 pass all four ratios.
Long R stalls, changed AR payloads, concurrent write/read arbitration and
post-reset accounting pass. The unchanged legacy results remain identical:
top timeout at Test 4; FIFO 44 mismatches. No new storage was needed.

## Phase 4 storage necessity and map decision

The existing B response is a constant, and no ACLK storage retains the accepted
address after its FIFO request is consumed. Supporting selectable per-access
errors while maintaining P2 therefore needs two bits of B response storage.
Capture the shared decode result at acceptance in ACLK, avoiding any new CDC
bus. This is the only added response holding register and exists for P2/P6.
The documented register window is 16 four-byte slots (0x00 through 0x3f).
Treat the unbounded high-address aliases as unsupported outside-window access
under the explicit Phase 4 policy. Default response code remains OKAY; outside
accesses no longer touch the aliased register. All 16 slots remain read/write;
there are no invented read-only registers or reserved holes.

## Phase 4 gate

Policy regression covers default OKAY, selectable SLVERR/DECERR, strict and
permissive alignment, out-of-window and misaligned reads/writes, including
error responses held under long stalls. Shared decode suppresses side effects.
Joint acceptance passes simultaneous, AW-first, W-first and fixed-seed random
skews, including 20 cycles. No independent AW/W buffers are needed.

## Phase 5 final results and reproducible commands

Run from the project root with PowerShell and Icarus/vvp on PATH:

```
pwsh -NoProfile -File tb/run_hardening.ps1 -Policy -CheckResetContract
pwsh -NoProfile -File tb/run_hardening.ps1 -Mode 1
pwsh -NoProfile -File tb/run_hardening.ps1 -Mode 2
pwsh -NoProfile -File tb/run_legacy.ps1
iverilog -g2012 -Wall -Wno-timescale -tnull -s axi4lite_slave_top async_fifo/rtl/async_fifo.sv axi4lite_slave_top.sv
```

Final results: 20 mixed/policy cases PASS (four ratios times five policies),
four write cases PASS, four read cases PASS. Both reset negative controls
PASS by rejecting the deliberate contract violation. Seed 0x41584934 is printed
on start and on every failure. Stalls last 80 ACLK cycles (>2*FIFO_DEPTH);
random skew spans -20..20, plus directed AW/W orders and full/partial/zero
strobes. Reset occurs in flight and with stalled responses, followed by fresh
transaction checks. All core register values are checked against an independent
byte-lane model after core execution, including suppressed error side effects.

Baseline versus final: canonical elaboration passes in both; legacy top times
out at Test 4 in both; standalone FIFO reports 44 errors in both. The runner
explicitly rejects worse legacy outcomes. No existing passing result regressed.
The old test_icarus_assert.sv and test_sva.sv are unchanged capability probes;
they compile but vvp rejects undefined $past (exit 1) and $past/$stable (exit 2),
respectively. They are not functional AXI regression passes.

Canonical Icarus -Wall elaboration exits 0 with no warnings. Existing concurrent
SVA block was compared against e8ac44d and is unchanged; it cannot run in Icarus.
No dedicated lint/CDC tools, constraints or formal/SymbiYosys configuration
exist in this project/toolchain. Per Phase 5, creating a formal setup is skipped.

### Invariant status after hardening

PASS below means source-level argument plus passing procedural simulation under
ASSUMPTIONS.md, not unbounded formal verification.

- **P1 PASS**: axi4lite_slave_top.sv:139 captures at acceptance; :303 toggles
  only on core execution; :196 waits for synchronized toggle mismatch. Checker
  compares accepted payload, actual register effects, execution and B counts.
- **P2 PASS**: :147-178 retains local BRESP; SEND_BRESP persists until READY.
  :126 pops read head only at handshake; :222 uses not-empty for RVALID.
  tb/tb_axi4lite_hardening.sv:60-63 checks both stalls, including errors.
- **P3 PASS**: one outstanding write reserves the toggle/B-state slot; no next
  request before B acknowledgment. One outstanding read plus :114 capacity
  reservation (including the registered pending enqueue) prevents overflow.
  Checker covers response uniqueness, counts, full writes and held responses.
- **P4 PASS**: :143-144 retains joint acceptance. Master VALIDs are held until
  handshake, in either order, while :139 captures both at that edge. No buffer
  or liveness dependency on a master waiting for READY is introduced.
- **P5 PASS**: :215 captures AR at handshake, :99/:313 share actual core
  selection with FIFO consumption; existing FIFO preserves ordering and stall
  stability. Scoreboard checks accepted AR versus core request and returned data.
- **P6 PASS**: :263 is the shared decode for core reads/writes and local B code.
  Default and selectable response policies and side-effect suppression pass.
- **P7 UNPROVEN for physical CDC/reset signoff**: environment contract and
  negative controls PASS in simulation. Structural inspection finds only
  existing Gray FIFO crossings and the existing one-bit 2FF completion crossing.
  Metastability, implementation timing and reset recovery/removal are not proven.

### Capacity and retention argument for unbounded stalls

After a write handshake the FSM cannot accept another until its B handshake.
Exactly one request FIFO pop executes that request and changes the completion
toggle once. Its value persists until a subsequent execution, which requires a
later accepted request, so it cannot be missed regardless of clock ratio.
WAIT_CORE can enter SEND_BRESP once; that state cannot leave without handshake.
BRESP changes only on a new acceptance, impossible while the prior B is stalled.

The read FSM similarly admits one request until the response handshake. Core
request consumption and response creation are paired. The one registered
response is enqueued on the next core edge; no second execution is admitted
while it is pending. The FIFO output is retained without a pop, and only an R
handshake pops it. Thus a stall does not change ownership or allow another
response to overwrite the current one. These arguments assume the audited FIFO
contract, correctly implemented synchronizers, joint reset and progressing clocks.
Finite tests exercise the argument but do not constitute a machine-checked proof.
