import hashlib
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parent
output = root / "build/vivado"
timing = (output / "timing.rpt").read_text()
section = timing.split("| Design Timing Summary", 1)[1].split("| Clock Summary", 1)[0]
rows = [line.split() for line in section.splitlines() if re.match(r"^\s*-?\d+\.\d+\s+-?\d+\.\d+\s+\d+", line)]
assert len(rows) == 1 and len(rows[0]) == 12, "Cannot parse timing summary"
numbers = list(map(float, rows[0]))
assert all(numbers[index] >= 0 for index in (0, 4, 8)), "Negative setup/hold/pulse-width slack"
assert all(numbers[index] == 0 for index in (2, 6, 10)), "Timing violation counts nonzero"
for check in ("no_clock", "unconstrained_internal_endpoints", "generated_clocks", "loops"):
    assert f"checking {check} (0)" in timing, f"Timing completeness check failed: {check}"
clocks = (output / "clocks.rpt").read_text()
assert re.search(r"^AXI_CLK\s+10\.000\s", clocks, re.M)
assert re.search(r"^CORE_CLK\s+13\.333\s", clocks, re.M)
assert "Checks found: 0" in (output / "drc.rpt").read_text(), "DRC not clean"
methodology = (output / "methodology.rpt").read_text()
assert "Critical Warning" not in methodology and "| Error " not in methodology
assert "multiple clocks" not in methodology, "Bus skew groups mix clock domains"
assert "not a valid startpoint" not in (output / "vivado.log").read_text()
skew = (output / "bus_skew.rpt").read_text()
assert "VIOLATED" not in skew and "Slack (MET)" in skew
reviews = []
for line in (output / "cdc.rpt").read_text().splitlines():
    columns = re.split(r"\s{2,}", line.strip())
    if len(columns) < 7 or not columns[0].isdigit():
        continue
    rule, severity = columns[1:3]
    source, destination = columns[-2:]
    assert rule in {"CDC-1", "CDC-3", "CDC-6", "CDC-9", "CDC-15"}, f"Unexpected CDC rule: {line}"
    if rule in {"CDC-1", "CDC-15"}:
        assert re.search(r"u_(write|read_req|read_resp)_fifo/u_mem/mem_reg.*?/CLK$", source), line
        assert re.search(r"(reg_file_reg\[.*\]/(D|CE|R|S)|rd_(data|resp)_core_reg.*?/(D|R|S)|received(_resp)?_reg.*?/D)$", destination), line
        assert "Max Delay Datapath Only" in line, line
        reason = "FWFT FIFO bundled data; local synchronized empty/pointer owns stable head; 10 ns bound"
    elif rule in {"CDC-3", "CDC-6"}:
        assert "/meta_ff_reg" in destination and "Max Delay Datapath Only" in line, line
        assert re.search(r"/(wr_gray_ptr_reg|rd_gray_ptr_reg|wr_bin_reg\[3\]|rd_bin_reg\[3\]|write_done_core_reg)", source), line
        reason = "Existing two-stage completion/Gray-pointer synchronizer; ASYNC_REG and bounded crossing"
    else:
        assert "release_reg" in destination and "/CLR" in destination, line
        reason = "Joint asynchronous reset assertion, three-stage synchronous release"
    reviews.append({"rule": rule, "severity": severity, "source": source, "destination": destination, "review": reason})
assert len(reviews) > 500, "CDC endpoint detail missing"
assert sum(row["rule"] == "CDC-6" for row in reviews) == 6, "Expected all six Gray synchronizer buses"
simulation = root / "build/simulation"
assert "PASS sweeps" in (simulation / "demo.log").read_text()
protocol_logs = [path for path in simulation.glob("*-*-*-*.log") if re.search(r"^\d+-\d+-\d+-\d+\.log$", path.name)]
assert len(protocol_logs) == 20 and all("\nPASS seed=" in path.read_text() for path in protocol_logs)
assert "PASS UNISIM" in (root / "build/xsim/launcher.log").read_text()
files = list((root / "rtl").glob("*.sv")) + [root / "board.xdc", root / "build.tcl", root.parent / "axi4lite_slave_top.sv", root.parent / "async_fifo/rtl/async_fifo.sv"]
files += [root / name for name in ("simulate.sh", "simulate_board.ps1", "tb_demo.sv", "tb_board.sv", "review.py", "release.py", "release.sh", "release.tcl")]
files += [root.parent / "tb/tb_axi4lite_hardening.sv", root.parent / "tb/axi4lite_reset_checker.sv"]
files += [output / name for name in ("routed.dcp", "timing.rpt", "cdc.rpt", "clocks.rpt", "methodology.rpt", "drc.rpt", "bus_skew.rpt", "exceptions.rpt", "reset_paths.rpt")]
hashes = {str(path.relative_to(root.parent)): hashlib.sha256(path.read_bytes()).hexdigest() for path in files}
report = {"status": "IMPLEMENTATION_VALIDATED_WITH_DOCUMENTED_CDC_FINDINGS", "physical_hardware_testing": "NOT RUN",
          "setup_slack_ns": numbers[0], "hold_slack_ns": numbers[4], "pulse_width_slack_ns": numbers[8],
          "cdc_review": reviews, "sha256": hashes}
(root / "build/review.json").write_text(json.dumps(report, indent=2) + "\n")
print(f"PASS implementation gates: setup {numbers[0]}, hold {numbers[4]}, pulse width {numbers[8]} ns")
print(f"Reviewed {len(reviews)} CDC endpoint records; raw classifications retained")
