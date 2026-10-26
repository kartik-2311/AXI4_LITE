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

## Read storage and arbitration

The existing FWFT response FIFO is the P2 holding storage. RVALID is not-empty;
the head is popped only at RVALID && RREADY. The existing read FSM admits one
AR until its R handshake. AR enqueue happens on acceptance, reusing the FIFO.
Core read requests pop only when actually selected by arbitration. A read
requires response FIFO space and no previously registered response enqueue
pending; the existing rd_data_core/rd_resp_core pipeline is retained. This
conservatively reserves a response slot and avoids both discarded requests
under write priority and overflow from the one-cycle enqueue latency.

## Address policy

The slave sees local byte addresses. One shared decode_address function defines
sixteen four-byte register slots at 0x00..0x3f, all writable/readable, with the
legacy index [5:2]. There is no BASE_ADDR comparison, RO register or reserved
hole. WSTRB byte-lane behavior and the existing four-byte address stride remain
unchanged, including when AXI_DATA_WIDTH is overridden. Supported existing
configurations require address width >=6 and valid byte-lane/data widths.

OOR_RESP defaults to 2'b00 (legacy OKAY), because the original design always
returned OKAY. 2'b10 selects SLVERR and 2'b11 selects DECERR; select SLVERR for
new integrations that want errors. Outside-window accesses never touch the
register bank, even with compatibility OKAY selected; reads return zero.
This intentionally removes undocumented high-address aliases under Phase 4.
STRICT_ALIGN defaults to 0, ignoring low two address bits as before. When 1,
misalignment inside the window returns SLVERR without side effects. Outside
window selection takes precedence over alignment. Error completion still gets
exactly one B or R. Reset clears all registers; reset-aborted transactions are
excluded from response accounting in the new epoch.

P2/P6 needs two new ACLK response bits because the original constant BRESP has
no storage for a dynamic error. They capture the shared decode at acceptance
and remain unchanged until the next request, after the prior B handshake.
The core uses the same decode to suppress unsupported side effects, and only
the existing single-bit completion toggle crosses back to ACLK.
