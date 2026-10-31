import hashlib
import json
from pathlib import Path
import re
import shutil
import sys

import klayout.db as layout_db

run = Path(sys.argv[1]).resolve()
assert "Flow complete." in (run / "flow.log").read_text(), "Flow did not complete cleanly"
states = sorted(run.glob("[0-9]*-*/state_out.json"), key=lambda path: int(path.parent.name.split("-")[0]))
state = json.loads(states[-1].read_text())
metrics = state["metrics"]
required_zero = [
    "magic__drc_error__count", "klayout__drc_error__count", "route__drc_errors",
    "design__lvs_error__count", "antenna__violating__nets", "antenna__violating__pins",
    "timing__setup_vio__count", "timing__hold_vio__count", "design__xor_difference__count",
]
for metric in required_zero:
    assert metric in metrics and metrics[metric] == 0, f"Signoff not clean: {metric}={metrics.get(metric)}"
sta_run = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else run
sta = next(sta_run.glob("*-openroad-stapostpnr"))
timing = []
crossing_paths = 0
for corner in sorted(path for path in sta.iterdir() if path.is_dir()):
    groups = {}
    for mode in ("max", "min"):
        text = (corner / f"{mode}.rpt").read_text()
        for block in re.split(r"(?=^Startpoint:)", text, flags=re.M):
            group = re.search(r"^Path Group: (.+)$", block, re.M)
            slack = re.search(r"^\s*(-?\d+\.\d+)\s+slack \((?:MET|VIOLATED)\)", block, re.M)
            if not group or not slack:
                continue
            value = float(slack[1])
            key = (group[1], mode)
            groups[key] = min(value, groups.get(key, value))
            clocks = re.findall(r"clocked by (ACLK|CORE_CLK)", block)
            if len(clocks) == 2 and clocks[0] != clocks[1]:
                assert mode == "max" and "max_delay" in block, "Crossing timed synchronously"
                crossing_paths += 1
    for clock in ("ACLK", "CORE_CLK"):
        assert (clock, "max") in groups and (clock, "min") in groups, f"Missing {corner.name}/{clock} timing"
        timing.append({"corner": corner.name, "clock": clock,
                       "setup_ns": groups[clock, "max"], "hold_ns": groups[clock, "min"]})
    assert ("path delay", "max") in groups, "Missing CDC delay checks"
    timing.append({"corner": corner.name, "clock": "CDC max delay",
                   "setup_ns": groups["path delay", "max"], "hold_ns": None})
assert len(timing) == 27 and crossing_paths > 0, "Expected nine signoff corners and actual crossing paths"
assert all(row["setup_ns"] >= 0 and (row["hold_ns"] is None or row["hold_ns"] >= 0) for row in timing)
gds = Path(state["gds"])
layout = layout_db.Layout()
layout.read(str(gds))
assert [cell.name for cell in layout.top_cells()] == ["axi4lite_slave_top"], "Unexpected GDS top cell"
assert not layout.top_cell().bbox().empty(), "Empty GDS layout"
output = Path(__file__).resolve().parent / "results"
output.mkdir(exist_ok=True)
shutil.copy2(gds, output / "axi4lite_slave_top.gds")
shutil.copy2(sta / "summary.rpt", output / "sta-summary.rpt")
shutil.copy2(Path(__file__).parent / "constraints.sdc", output / "applied-constraints.sdc")
for pattern in ("*-netgen-lvs/reports/lvs.netgen.rpt", "*-netgen-lvs/reports/lvs.netgen.json",
                "*-magic-drc/reports/*drc*.rpt", "*-klayout-drc/reports/drc.klayout.json",
                "*-openroad-checkantennas*/**/*antenna*.rpt"):
    for report in list(run.glob(pattern)) + ([] if sta_run == run else list(sta_run.glob(pattern))):
        if report.stat().st_size < 1_000_000:
            shutil.copy2(report, output / f"{report.parent.name}-{report.name}")
area = {key: value for key, value in metrics.items()
        if any(token in key for token in ("design__instance__", "design__core__area", "design__die__area"))}
summary = {"run": run.name, "sta_source_run": sta_run.name, "state": str(states[-1].relative_to(run)),
           "zero_error_metrics": {key: metrics[key] for key in required_zero},
           "remaining_electrical_warnings": {key: metrics[key] for key in (
               "design__max_slew_violation__count", "design__max_cap_violation__count")},
           "timing": timing, "area_and_cells": area, "crossing_paths_checked": crossing_paths,
           "gds_top": layout.top_cell().name, "gds_bytes": gds.stat().st_size,
           "gds_sha256": hashlib.sha256(gds.read_bytes()).hexdigest()}
root = Path(__file__).resolve().parent.parent
summary["rtl_sha256"] = {name: hashlib.sha256((root / name).read_bytes()).hexdigest()
                         for name in ("axi4lite_slave_top.sv", "async_fifo/rtl/async_fifo.sv")}
(output / "signoff.json").write_text(json.dumps(summary, indent=2) + "\n")
lines = ["# Signoff results", "", f"Run: {run.name}. GDS loaded headlessly; top cell axi4lite_slave_top.", "",
         "| Corner | Clock or check | Setup/delay slack ns | Hold slack ns |", "|---|---|---:|---:|"]
for row in timing:
    hold = "asynchronous hold cut" if row["hold_ns"] is None else f'{row["hold_ns"]:.6f}'
    lines.append(f'| {row["corner"]} | {row["clock"]} | {row["setup_ns"]:.6f} | {hold} |')
lines += ["", "All required DRC/LVS/antenna/setup/hold/XOR error counts are zero.",
          "Asynchronous clock groups use explicit clock-independent CDC max delays; see applied-constraints.sdc.",
          "Full cell/area data and GDS hash are in signoff.json. Raw runs remain local and untracked."]
lines += ["", f'Standard-cell count excluding filler: {metrics["design__instance__count__stdcell"]}.',
          f'Total physical instances including filler: {metrics["design__instance__count"]}.',
          f'Standard-cell area excluding filler: {metrics["design__instance__area__stdcell"]} um^2.',
          f'Core area: {metrics["design__core__area"]} um^2.',
          f'Final utilization excluding filler: {100 * metrics["design__instance__utilization"]:.4f}%.']
lines += ["", "## Unresolved electrical warnings", "",
          f'Max-slew violations: {metrics["design__max_slew_violation__count"]}.',
          f'Max-capacitance violations: {metrics["design__max_cap_violation__count"]}.',
          "The requested stopping criteria are met; these additional electrical warnings remain.",
          "This result must not be described as fully tapeout-ready."]
(output / "README.md").write_text("\n".join(lines) + "\n")
print(f"PASS: {gds.name}, top=axi4lite_slave_top, nine corners, zero required error counts")
print(json.dumps({key: metrics[key] for key in required_zero}))
