"""Freeze the original 18 chapter terminals without changing old receipts.

Uses explicitly selected candidate and frozen runtime, never core-current.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, default=root / "godot/bin/runtime/195322d160a42d32/cas-sim.exe")
    parser.add_argument("--output", type=Path, default=root / "artifacts/story-modernization-v3/parity/original-18-terminal-freeze.json")
    args = parser.parse_args()
    snapshots = sorted((root / "artifacts/godot/story-longform").glob("*-terminal.json"))
    assert len(snapshots) == 18, len(snapshots)
    rows = []
    for snapshot in snapshots:
        commands = [{"op": "load", "serialized": snapshot.read_text("utf-8-sig")}, {"op": "observe"}, {"op": "save", "serialized": True}]
        request = ("\n".join(json.dumps(q, ensure_ascii=False) for q in commands) + "\n").encode("utf-8")
        replies = []
        for binary in (args.baseline, args.candidate):
            process = subprocess.run([str(binary.resolve())], input=request, capture_output=True, check=True, timeout=60)
            lines = process.stdout.splitlines()
            assert len(lines) == 3, (snapshot.name, len(lines))
            for line in lines:
                assert json.loads(line)["ok"], (snapshot.name, line[:250])
            replies.append(process.stdout)
        assert replies[0] == replies[1], snapshot.name
        rows.append({"stage": snapshot.stem.removesuffix("-terminal"), "requests": 3, "bytes": len(replies[0]), "sha256": sha(replies[0]), "exact": True})
    report = {"passed": True, "stages": len(rows), "requests": sum(r["requests"] for r in rows), "bytes": sum(r["bytes"] for r in rows), "baseline": str(args.baseline.resolve()), "baseline_sha256": sha(args.baseline.read_bytes()), "candidate": str(args.candidate.resolve()), "candidate_sha256": sha(args.candidate.read_bytes()), "rows": rows, "scope": "Original eighteen genuine chapter terminal snapshots; load/observe/serialized-save stdout bytes frozen against installed 195322 runtime. No old receipts or accounts changed."}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"passed": True, "stages": len(rows), "requests": report["requests"], "bytes": report["bytes"], "receipt": str(args.output)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
