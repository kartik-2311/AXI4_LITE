# Signoff results

Run: axi-04. GDS loaded headlessly; top cell axi4lite_slave_top.

| Corner | Clock or check | Setup/delay slack ns | Hold slack ns |
|---|---|---:|---:|
| max_ff_n40C_1v95 | ACLK | 3.276156 | 0.111760 |
| max_ff_n40C_1v95 | CORE_CLK | 16.290266 | 0.108979 |
| max_ff_n40C_1v95 | CDC max delay | 6.225202 | asynchronous hold cut |
| max_ss_100C_1v60 | ACLK | 0.510509 | 0.844762 |
| max_ss_100C_1v60 | CORE_CLK | 8.449824 | 0.895137 |
| max_ss_100C_1v60 | CDC max delay | 0.328192 | asynchronous hold cut |
| max_tt_025C_1v80 | ACLK | 3.017958 | 0.315733 |
| max_tt_025C_1v80 | CORE_CLK | 14.240071 | 0.324229 |
| max_tt_025C_1v80 | CDC max delay | 5.399052 | asynchronous hold cut |
| min_ff_n40C_1v95 | ACLK | 3.283036 | 0.108658 |
| min_ff_n40C_1v95 | CORE_CLK | 16.470657 | 0.104602 |
| min_ff_n40C_1v95 | CDC max delay | 6.237570 | asynchronous hold cut |
| min_ss_100C_1v60 | ACLK | 0.784058 | 0.837187 |
| min_ss_100C_1v60 | CORE_CLK | 8.908333 | 0.887338 |
| min_ss_100C_1v60 | CDC max delay | 0.554162 | asynchronous hold cut |
| min_tt_025C_1v80 | ACLK | 3.027967 | 0.311401 |
| min_tt_025C_1v80 | CORE_CLK | 14.494269 | 0.319835 |
| min_tt_025C_1v80 | CDC max delay | 5.523980 | asynchronous hold cut |
| nom_ff_n40C_1v95 | ACLK | 3.279295 | 0.110302 |
| nom_ff_n40C_1v95 | CORE_CLK | 16.384853 | 0.106387 |
| nom_ff_n40C_1v95 | CDC max delay | 6.231251 | asynchronous hold cut |
| nom_ss_100C_1v60 | ACLK | 0.671230 | 0.841502 |
| nom_ss_100C_1v60 | CORE_CLK | 8.682328 | 0.890714 |
| nom_ss_100C_1v60 | CDC max delay | 0.448609 | asynchronous hold cut |
| nom_tt_025C_1v80 | ACLK | 3.022453 | 0.313750 |
| nom_tt_025C_1v80 | CORE_CLK | 14.373731 | 0.321754 |
| nom_tt_025C_1v80 | CDC max delay | 5.468043 | asynchronous hold cut |

All required DRC/LVS/antenna/setup/hold/XOR error counts are zero.
Asynchronous clock groups use explicit clock-independent CDC max delays; see applied-constraints.sdc.
Full cell/area data and GDS hash are in signoff.json. Raw runs remain local and untracked.

Standard-cell count excluding filler: 9467.
Total physical instances including filler: 38768.
Standard-cell area excluding filler: 95718.1 um^2.
Core area: 196808 um^2.
Final utilization excluding filler: 48.6354%.

## Unresolved electrical warnings

Max-slew violations: 372.
Max-capacitance violations: 12.
The requested stopping criteria are met; these additional electrical warnings remain.
This result must not be described as fully tapeout-ready.

Generated GDS and detailed tool outputs are excluded from Git; regenerate them
with the documented flow. These summaries record historical results, not a
fresh ASIC implementation run.
