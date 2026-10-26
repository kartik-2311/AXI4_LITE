# AXI hardening change log

## Phase 0

Read-only RTL audit; baseline recorded. Initialized Git because the supplied
folder had no repository, preserved its source, then created axi-hardening.

## Phase 1

Added self-checking simulation, procedural protocol/core-register scoreboard,
fixed seed, four clock ratios and bounded legacy runner. No RTL edits.

## Phase 2 P1 P3 and payload integrity

- Request FIFO enqueue now coincides with AW/W acceptance, so live payload
  changes after handshake cannot corrupt a write. Existing FIFO storage reused.
- Core completion is a persistent execution toggle through the existing 2FF
  synchronizer. One new ACLK acknowledgment bit records the last B handshake;
  a mismatch causes the existing FSM to send B. No state or FIFO added.
- One outstanding write reserves response capacity until B handshake. Existing
  constant BRESP and SEND_BRESP retention are preserved.
- Behavior change: completion reliably means execution, including fast-core
  clocks. Correctly accepted data is used even if the bus changes afterward.
- Validation: MODE=1 passes all four ratios; unchanged legacy top still times
  out at Test 4; unchanged FIFO test still reports 44 errors. No regression.

## Phase 3 P2 P3 P5

- FWFT response pop is now RVALID && RREADY; RVALID is FIFO not-empty.
- AR address is enqueued at acceptance using existing FIFO storage.
- Core request pop and execution now share arbitration/capacity gating.
  Existing registered response stage is included in the capacity reservation.
- Behavior change: read responses survive stalls, accepted AR data cannot be
  replaced by later bus values, and concurrent writes cannot discard reads.
- No FIFO, holding register, port or FSM state added.

## Phase 4 P4 P6

- Retained joint AW/W acceptance, proven by skewed-arrival tests. No AW/W
  holding storage added. Acceptance-cycle capture was fixed in Phase 2.
- Shared local decode used for write/read execution and ACLK response capture.
- Added OOR_RESP default 2'b00, preserving the original response code; SLVERR
  and DECERR are selectable. Added STRICT_ALIGN default 0, preserving low-bit
  ignoring. STRICT_ALIGN=1 returns SLVERR for misalignment inside the window.
- Behavior change required by Phase 4: high addresses no longer alias low
  registers; unsupported accesses have no side effect and read as zero.
  Outside-window response selection precedes alignment. No RO slots invented.
- Two new BRESP holding bits are necessary for dynamic per-access responses
  under P2/P6; no existing response storage existed. Decode occurs locally,
  so no new multibit CDC is introduced. WSTRB semantics are preserved.
