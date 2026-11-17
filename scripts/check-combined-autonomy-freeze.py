"""Compare unopted-in v1-v4 native responses against a frozen runtime.

Run with --baseline <installed frozen exe> --current <candidate exe>.
Only subprocess-local battles are created; no account is read or written.
"""
import argparse
import hashlib
import json
import pathlib
import subprocess


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", required=True, type=pathlib.Path)
    parser.add_argument("--current", required=True, type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path, default=pathlib.Path("artifacts/combined-autonomy-v1/legacy-freeze.json"))
    args = parser.parse_args()
    cases = []
    for version in range(1, 5):
        for multi in ([False, True] if version == 4 else [False]):
            ships = [{"id": "IBS-U-USN-ERMA-IOWA", "hp": 100, "ammo": 100}, {"id":"IBS-U-USN-FLETCHER", "hp":100, "ammo":100}]
            roster = ["MCP-034", "MCP-009"] if version >= 3 else ["MCP-034"]
            request = {"op": "new_littoral", "version": f"cas-littoral-v{version}", "seed": 42, "mode": "tutorial", "ships": ships, "roster": roster, "transport_preset": "transport", "defense": [], "unit_condition": []}
            if version >= 3:
                request["lesson"] = "landing"
            if multi:
                request["company_layout"] = "multi-company-v1"
            deploy = {"op": "littoral_deploy", "unit_id": "MCP-034-C01" if multi else "MCP-034", "beach": 2, "insertion": "landing", "queue": True}
            queries = [request, {"op": "observe"}, {"op": "step", "seconds": 2}, deploy, {"op": "step", "seconds": 30}, {"op": "save"}]
            processes = [subprocess.Popen([str(exe.resolve())], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, encoding="utf-8") for exe in (args.baseline, args.current)]
            count = 0
            raw = []
            try:
                for query in queries:
                    replies = []
                    for proc in processes:
                        proc.stdin.write(json.dumps(query, ensure_ascii=False) + "\n")
                        proc.stdin.flush()
                        replies.append(proc.stdout.readline().rstrip("\n"))
                    if replies[0] != replies[1]:
                        raise AssertionError(f"v{version} multi={multi} raw mismatch for {query['op']}")
                    parsed = json.loads(replies[0])
                    if query["op"] == "new_littoral" and not parsed.get("ok"):
                        raise AssertionError(parsed)
                    raw.append(replies[0])
                    count += 1
                saved = json.loads(raw[-1])["data"]
                for operation in ("load", "replay"):
                    query = {"op": operation, "save": saved}
                    replies = []
                    for proc in processes:
                        proc.stdin.write(json.dumps(query, ensure_ascii=False) + "\n")
                        proc.stdin.flush()
                        replies.append(proc.stdout.readline().rstrip("\n"))
                    if replies[0] != replies[1]:
                        raise AssertionError(f"v{version} multi={multi} {operation} raw mismatch")
                    raw.append(replies[0])
                    count += 1
                cases.append({"version": version, "multi": multi, "raw_identical_responses": count, "responses_sha256": digest("\n".join(raw).encode("utf-8"))})
            finally:
                for proc in processes:
                    proc.stdin.close()
                    proc.wait(timeout=10)
    result = {"passed": True, "baseline": str(args.baseline.resolve()), "baseline_sha256": digest(args.baseline.read_bytes()), "current": str(args.current.resolve()), "current_sha256": digest(args.current.read_bytes()), "scope": "native raw no-opt-in legacy observations, stepping, commands, saves, load and replay; no account access", "cases": cases}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"passed": True, "cases": len(cases), "raw_identical_responses": sum(row["raw_identical_responses"] for row in cases), "receipt": str(args.output)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
