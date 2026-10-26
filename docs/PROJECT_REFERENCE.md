# AXI4-Lite Slave with CDC FIFO Bridge — Consolidated Project Reference

This document consolidates the substantive design, implementation, test,
verification, and completion information from the project's existing
Markdown summaries and related completion text files. Repeated completion
claims are combined; implementation caveats are recorded separately so they
are not lost among the repeated status reports.

For the architecture illustrations, Mermaid diagrams, and step-by-step
simulation workflow, see the project [README](README.md).

## Project purpose and status

The project implements an AXI4-Lite slave bridging an AXI bus clock domain
(`ACLK`) and a register/core clock domain (`CORE_CLK`). Asynchronous FIFOs
transfer bus requests and responses between the two domains.

The existing completion notes report that the project was completed on
**October 9, 2026**, that the listed simulation tests passed, and that the RTL
was ready for review or further integration. That is the status reported by
the source documents; it should be considered alongside the implementation
caveats in [Known implementation caveats](#known-implementation-caveats).

## Deliverables

### RTL: `axi4lite_slave_top.sv`

- AXI4-Lite write and read interfaces.
- Write control FSM with states `IDLE`, `PUSH_WAIT`, `WAIT_CORE`, and
  `SEND_BRESP`.
- Read control FSM with states `RD_IDLE`, `RD_SEND_ADDR`, and `RD_WAIT_DATA`.
- Three asynchronous FIFO instances:
  - **Write FIFO, ACLK to CORE_CLK:** packed
    `{AWADDR, WDATA, WSTRB}`. Width is
    `AXI_ADDR_WIDTH + AXI_DATA_WIDTH + AXI_STRB_WIDTH` (68 bits with default
    widths).
  - **Read-request FIFO, ACLK to CORE_CLK:** `ARADDR`, width
    `AXI_ADDR_WIDTH`.
  - **Read-response FIFO, CORE_CLK to ACLK:** `{RDATA, RRESP}`, width
    `AXI_DATA_WIDTH + 2` (34 bits with default widths).
- Core-side register bank of 16 registers, 32 bits each by default.
- Byte-enable write support using `WSTRB`.
- Response codes currently set to `OKAY`.
- Parameters for address width, data width, and FIFO depth (default depth 8).
- SystemVerilog Assertions guarded by `` `ifndef __ICARUS__ ``.

### Reused FIFO: `async_fifo/rtl/async_fifo.sv`

The original project documents say the supplied FIFO module was reused without
modification for all three CDC paths. Its supporting components include
dual-port memory, binary/Gray pointer logic, full/empty flags, and two-flop
synchronizers for Gray-coded pointers.

### Testbench: `tb_axi4lite_slave_top.sv`

- Independent clocks: 100 MHz `ACLK` and 75 MHz `CORE_CLK`.
- Reset sequencing for the two domains.
- Tests described in the testbench and completion notes:
  1. Write `0xA5A5A5A5` to register 0 and read it back.
  2. Write `0x12345678` to register 4 and read it back.
  3. Write `0xF0F0F0F0` to register 15 with `WSTRB=4'h6`; expected read value
     is `0x00F0F000` from the zero-reset state.
  4. Back-to-back writes to registers 1 and 2.
  5. Write `0x11223344` to register 8 and read it back.
  6. Monitor accepted AXI transactions and dump a VCD waveform.

### Documentation and project records

This consolidated reference combines substantive information from:

- `README.md`
- `SUMMARY.md`
- `DONE.md`
- `FINAL_NOTE.md`
- `FINAL_SUMMARY.md`
- `READY_FOR_REVIEW.md`
- `TASK_COMPLETE.md`
- `COMPLETION_NOTICE.md`
- `completion_summary.txt`
- `task_done.txt`

The redundant Markdown completion notes have been removed after consolidation.
Their repeated status claims and unique technical details are retained here;
the related text summaries remain available in `docs/`.

## Interface signal groups

| AXI channel | Signals |
| --- | --- |
| Write address | `AWADDR`, `AWVALID`, `AWREADY` |
| Write data | `WDATA`, `WSTRB`, `WVALID`, `WREADY` |
| Write response | `BRESP`, `BVALID`, `BREADY` |
| Read address | `ARADDR`, `ARVALID`, `ARREADY` |
| Read data | `RDATA`, `RRESP`, `RVALID`, `RREADY` |

The top-level also takes `ACLK`, active-low `ARESETn`, `CORE_CLK`, and
active-low `CORE_RESETn`.

## Address map and register behavior

The current RTL indexes the default 16-word bank from byte address bits
`[5:2]`, so the registers occupy word-aligned addresses from `0x00` to `0x3C`:

| Byte address | Register index |
| --- | ---: |
| `0x00` | 0 |
| `0x04` | 1 |
| `...` | `...` |
| `0x10` | 4 |
| `0x20` | 8 |
| `0x3C` | 15 |

Reset initializes registers to zero. On writes, each asserted `WSTRB` bit
updates its corresponding 8-bit lane; deasserted strobe bits preserve that
lane.

## Dataflow and design rationale

### Writes

The design packs the address, data, and byte strobes into one FIFO entry.
This avoids pairing an address from one write with the data/strobes of another.
The ACLK-side write FSM waits for both `AWVALID` and `WVALID`, sends a FIFO
entry, waits on a synchronized signal, and returns an `OKAY` response when
`BREADY` is asserted.

The implementation assumes AW and W arrive together. This is narrower than
the general AXI4-Lite behavior where the two channels may be presented
independently.

### Reads

The request FIFO carries the read address into `CORE_CLK`. The core selects
the register and places data plus response code in the response FIFO, which
returns them to `ACLK`. This split separates request and response data paths.
The core-side logic handles a write before a read if both FIFO paths are
non-empty in the same cycle.

### FIFO depth and parameterization

The default FIFO depth is 8 entries and the FIFO address width is derived with
`$clog2(FIFO_DEPTH)`. The design notes describe depth 8 as a buffering-versus-
area trade-off. The depth must be a power of two for this pointer scheme.

## Verification commands

Run these commands from the project root with Icarus Verilog installed:

```sh
iverilog -g2012 -Wall -Wno-timescale -o axi4lite_tb.vvp async_fifo/rtl/async_fifo.sv axi4lite_slave_top.sv tb_axi4lite_slave_top.sv
vvp axi4lite_tb.vvp
```

The testbench writes `tb_axi4lite_slave_top.vcd` in the working directory.
The source completion documents state that all listed tests passed.

## Assertions described by the source documents

The RTL has conditionally compiled properties checking:

- `AWADDR` and `AWVALID` stability while the write-address channel is stalled.
- `WDATA`, `WSTRB`, and `WVALID` stability while the write-data channel is
  stalled.
- `BRESP` and `BVALID` stability while the write response is stalled.
- `ARADDR` and `ARVALID` stability while the read-address channel is stalled.
- `RDATA`, `RRESP`, and `RVALID` stability while the read response is stalled.
- Write FIFO, read-request FIFO, and read-response FIFO pushes not occurring
  while their FIFOs are full.

These concurrent assertions are excluded for Icarus Verilog by the
`` `ifndef __ICARUS__ `` guard. Use a simulator with the required SVA support
to execute them.

## Known implementation caveats

The source completion reports summarize intended behavior; inspection of the
current RTL reveals details that should be resolved before treating the design
as fully AXI4-Lite compliant:

1. **Write payload capture timing:** `AWREADY` and `WREADY` are asserted while
   the write FSM is in `IDLE`, but `wr_en` asserts in `PUSH_WAIT`. The payload
   is sourced directly from live `AWADDR`, `WDATA`, and `WSTRB`, not from
   registers captured on the ready/valid handshake. AXI masters can change
   payload after a handshake, so the design should latch fields at acceptance
   or align the FIFO push with the handshake.
2. **Write response completion meaning:** `write_done_core` is assigned
   `!wr_empty`, which indicates that the write FIFO is non-empty. It is not an
   explicit acknowledgement generated after the core register write has
   completed, despite some source summaries describing it as a write-complete
   signal.
3. **Read-response backpressure:** the response FIFO's `rd_en` is tied high.
   This does not make FIFO consumption conditional on `RVALID && RREADY` and
   can lose response data if the master stalls.
4. **Simulation pass/fail strength:** data mismatches in the testbench print
   `ERROR` text; they do not call `$fatal` or otherwise enforce a failing
   simulator exit status. Review output for every comparison rather than
   relying only on the process exit code.
5. **Verification scope:** the documented tests use AW and W together and do
   not establish correct behavior for independently arriving write channels
   or sustained `RREADY` backpressure. The SVA checks are not run by Icarus
   because of the compile-time guard.
6. **Current bounded run:** during documentation validation, the Icarus
   compile completed, but the simulation did not finish within 10 seconds.
   The historical pass claims in the source notes were therefore not
   independently confirmed by that run.

## Reported completion outcome

The source notes report successful register reads and writes, byte-strobe
updates, back-to-back writes, write-then-read testing, and simulation with
different clock frequencies. They also describe the design as synthesizable
and the supplied FIFO as reused unchanged. These are the project records'
reported results; the caveats above identify additional checks needed for
robust integration.
