# AXI hardening assumptions and design choices

## Clocks and reset

ACLK and CORE_CLK run continuously with arbitrary positive periods. Liveness
requires both clocks to progress and the receiver eventually to assert READY;
response safety must hold for an unbounded stall. Joint reset aborts all
in-flight transactions and clears the register bank. Both resets must assert
together, remain active long enough for both domains, and deassert synchronously
in their own domains. Unilateral reset is unsupported. Verification checker
enforcement and physical CDC limitations are recorded in Phase 5.

## Write completion capacity

There is no existing B response FIFO. A new FIFO is unnecessary: the existing
write FSM admits one write until its B handshake. The core toggles the existing
completion signal only on actual execution. The existing single-bit two-flop
synchronizer carries that persistent toggle. One new ACLK bit remembers the
acknowledged toggle; only a changed toggle allows SEND_BRESP. The B handshake
acknowledges it, and a subsequent request through the existing request FIFO
implicitly acknowledges reuse to the core. The core cannot execute a second
write before that acknowledgment. Thus response capacity is reserved before
acceptance, cannot overflow, and completion cannot be missed by a slower ACLK.
No raw multibit completion bus crosses domains.

P1/P4 requires enqueueing payload on the joint AW/W handshake itself. The
existing request FIFO supplies the storage; no address/data holding register
is needed. Existing SEND_BRESP already provides P2 BVALID retention.
