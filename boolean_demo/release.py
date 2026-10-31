import hashlib
import json
from pathlib import Path
import runpy
import sys

root = Path(__file__).resolve().parent
runpy.run_path(str(root / "review.py"))
review = json.loads((root / "build/review.json").read_text())
for name, digest in review["sha256"].items():
    assert hashlib.sha256((root.parent / name).read_bytes()).hexdigest() == digest, f"Artifact changed: {name}"
checkpoint = review["sha256"]["boolean_demo/build/vivado/routed.dcp"]
(root / "build/release-approved.tcl").write_text(f'set expected_checkpoint_sha {checkpoint}\n')
if "--record-bit" in sys.argv:
    bit = root / "build/vivado/axi_boolean_top.bit"
    assert bit.is_file() and "BITSTREAM_READY" in (root / "build/vivado/release.log").read_text()
    review["bitstream"] = {"path": str(bit.relative_to(root)), "bytes": bit.stat().st_size,
                            "sha256": hashlib.sha256(bit.read_bytes()).hexdigest()}
    (root / "build/manifest.json").write_text(json.dumps(review, indent=2) + "\n")
    checksum_lines = [f"{digest}  {name}" for name, digest in sorted(review["sha256"].items())]
    checksum_lines.append(f'{review["bitstream"]["sha256"]}  boolean_demo/{review["bitstream"]["path"]}')
    (root / "build/SHA256SUMS").write_text("\n".join(checksum_lines) + "\n")
    print("BITSTREAM_HASH", review["bitstream"]["sha256"])
