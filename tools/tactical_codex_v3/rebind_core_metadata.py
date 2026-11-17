"""Verify a metadata-only runtime replacement without relabelling prior UI runs."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "artifacts/island-war-v3"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compare(before, after, path=()):
    if type(before) is not type(after):
        raise AssertionError((path, before, after))
    if isinstance(before, dict):
        assert before.keys() == after.keys(), path
        return sum((compare(before[k], after[k], path + (k,)) for k in before), [])
    if isinstance(before, list):
        assert len(before) == len(after), path
        return sum((compare(a, b, path + (i,)) for i, (a, b) in enumerate(zip(before, after))), [])
    if before == after:
        return []
    # The only approved difference is a vehicle-impact presentation child class.
    assert path[-1] == "armor_class" and "affected_bodies" in path, (path, before, after)
    assert before == "light_armor" and after in ("heavy_armor", "helicopter"), (path, before, after)
    return [{"path": list(path), "before": before, "after": after}]


class Runtime:
    def __init__(self, path):
        self.process = subprocess.Popen([str(path)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, text=True, encoding="utf-8")

    def request(self, request):
        self.process.stdin.write(json.dumps(request, ensure_ascii=False) + "\n")
        self.process.stdin.flush()
        response = json.loads(self.process.stdout.readline())
        assert response.get("ok"), response
        return response

    def close(self):
        self.process.stdin.close()
        self.process.wait(timeout=10)
        assert self.process.returncode == 0


def main():
    previous, final = map(Path, sys.argv[1:3])
    catalogue = json.loads((ROOT / "godot/data/island-war-v3.json").read_text(encoding="utf-8"))
    lessons = json.loads((ROOT / "godot/data/tactical-training-v3.json").read_text(encoding="utf-8"))["lessons"]
    cases = [("lesson-" + name, row["request"]) for name, row in lessons.items()]
    for name in ("actual-tank-rear-cover", "actual-ifv-rear-cover"):
        saved = json.loads((ART / "core" / (name + ".json")).read_text(encoding="utf-8"))
        cases.append((name, {"op": "load", "serialized": saved["serialized"]}))
    a, b = Runtime(previous), Runtime(final)
    report = {"previous_core_sha256": sha(previous), "final_core_sha256": sha(final),
              "catalogue_sha256": sha(ROOT / "godot/data/island-war-v3.json"),
              "scope": "Targeted native construction/load/observe/step/save equivalence; not a rerun of the597 UI or224 account suite.",
              "responses": 0, "cases": [], "allowed_metadata_differences": []}
    request = {"op": "island_war_catalogue", "version": "cas-island-war-v3"}
    av, bv = a.request(request), b.request(request)
    assert av["data"] == bv["data"] == catalogue
    report["responses"] += 1
    for name, initial in cases:
        digest_a, digest_b = hashlib.sha256(), hashlib.sha256()
        requests = [initial, {"op": "observe"}, {"op": "step", "seconds": 1},
                    {"op": "step", "seconds": 1}, {"op": "save", "serialized": True}]
        differences = []
        for request in requests:
            av, bv = a.request(request), b.request(request)
            digest_a.update(json.dumps(av, sort_keys=True, ensure_ascii=False).encode())
            digest_b.update(json.dumps(bv, sort_keys=True, ensure_ascii=False).encode())
            differences += compare(av, bv)
            report["responses"] += 1
        report["allowed_metadata_differences"] += [{"case": name, **d} for d in differences]
        report["cases"].append({"name": name, "responses": len(requests),
                                "previous_response_sha256": digest_a.hexdigest(),
                                "final_response_sha256": digest_b.hexdigest(),
                                "allowed_metadata_differences": len(differences)})
    a.close()
    b.close()
    report["passed"] = True
    target = ART / "home/final-metadata-rebind.json"
    target.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": True, "responses": report["responses"],
                      "cases": len(cases), "metadata_differences": len(report["allowed_metadata_differences"]),
                      "final_core_sha256": report["final_core_sha256"]}))


if __name__ == "__main__":
    main()
