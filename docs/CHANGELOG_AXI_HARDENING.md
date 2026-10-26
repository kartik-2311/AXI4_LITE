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
