"""Verify the current demo receipt and freeze actual visual evidence separately."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
DEMO = ROOT / "demos/land-art-3d"
OUT = ROOT / "artifacts/coast-v2-20261116"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def main():
    checks = []

    def check(name, passed, detail=None):
        checks.append(dict(name=name, passed=bool(passed), detail=detail))

    geo = read(OUT / "geography-validation.json")
    check("real_geography_and_scene_checks", geo["passed"] and not geo["warnings"]
          and all(c["passed"] for c in geo["checks"]), len(geo["checks"]))
    for rel, expected in geo["source_sha256"].items():
        check("source_still_current:" + rel, sha(DEMO / rel) == expected)
    check("editable_scene_still_current", sha(DEMO / "scenes/editable_coast.scn")
          == geo["editable_snapshot"]["sha256"])
    for name in ("water", "land"):
        report = read(DEMO / f"assets/vehicles3d/vehicle-{name}-route-verification.json")
        check(name + "_routes_passed", report["passed"])
        check(name + "_routes_current_geography", report["geography_sha256"]
              == sha(DEMO / "scripts/coastal_geography.gd"))
        check(name + "_routes_current_vehicles", report["vehicles_module_sha256"]
              == sha(DEMO / "scripts/coastal_vehicles.gd"))
    runtime = (OUT / "runtime.log").read_text(encoding="utf-8")
    check("eleven_real_gpu_captures", runtime.count("COAST_V2_CAPTURE ") == 11)
    check("gpu_no_runtime_errors", not re.search(r"(?:SCRIPT ERROR|SHADER ERROR|^ERROR:)", runtime, re.M))
    loaded = (OUT / "editable-gpu-load.log").read_text(encoding="utf-8")
    check("editable_gpu_render_and_free", "nested_scenes=0" in loaded
          and "POST_FREE_ORPHANS" in loaded
          and not loaded.split("POST_FREE_ORPHANS", 1)[1].strip()
          and not re.search(r"(?:SCRIPT ERROR|SHADER ERROR|^ERROR:)", loaded, re.M))
    pack = read(ROOT / "output/coast-v2-20261116/review-validation.json")
    check("offline_review_paths_and_hashes", pack["passed"] and pack["wave_frames"] == 16)
    browser = read(OUT / "review-browser-qa/browser-verification.json")
    check("review_browser_controls_and_layout", browser["passed"])
    header = read(OUT / "geography-header.json")
    check("metric_visual_demo_scope", header["units"] == "metres"
          and header["authority_scope"] == "visual_demo")
    frames = sorted((OUT / "waves").glob("frame-*.png"))
    check("sixteen_real_wave_frames", len(frames) == 16
          and len({sha(p) for p in frames}) == 16)
    metrics = read(OUT / "desktop-render-samples.json")
    check("both_render_views_sampled", len(metrics["samples"]) == 2
          and all(s["frames"] == 180 for s in metrics["samples"]))
    model_manifest = read(DEMO / "assets/vehicles3d/vehicle-manifest.json")
    check("eight_model_manifest", len(model_manifest["models"]) == 8)
    for item in model_manifest["models"]:
        check("model_bytes:" + item["id"], sha(DEMO / "assets/vehicles3d" / (item["id"] + ".glb")) == item["sha256"])
    for rel in ["CAS-Land-Art-Demo.cmd", "CAS-Coast-Review.cmd", "plan.md", "havedone.md",
                "docs/development/coastal-wasteland-demo-20261116.md",
                "docs/design/coastal-wasteland-followup-20261116.md"]:
        check("delivery_file:" + rel, (ROOT / rel).is_file())
    failed = [c for c in checks if not c["passed"]]
    if failed:
        print(json.dumps(failed, ensure_ascii=False, indent=2))
        raise SystemExit(1)

    frozen = OUT / ("final-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
    frozen.mkdir()
    sources = sorted((OUT / "screenshots").glob("*.png")) + frames
    sources += [OUT / n for n in ["runtime.log", "editable-gpu-load.log", "geography-validation.json",
                "geography-header.json", "desktop-render-samples.json",
                "review-browser-qa/browser-verification.json"]]
    for path in sources:
        target = frozen / path.relative_to(OUT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    files = [{"path": str(p.relative_to(ROOT)), "sha256": sha(p)}
             for p in sorted(frozen.rglob("*")) if p.is_file()]
    report = dict(passed=True, generated_utc=datetime.now(timezone.utc).isoformat(),
                  scope="isolated desktop art demo only; production maps/core/account/Android not migrated",
                  checks=checks, geography_checks=len(geo["checks"]), render_samples=metrics,
                  frozen_evidence=str(frozen.relative_to(ROOT)), files=files,
                  limits=["No Android device or full combat performance acceptance",
                          "Local landing query is not production navigation/unloading authority",
                          "Earlier interaction log contains a WASAPI device invalidation; final rendering used Dummy audio",
                          "Historical campaign and production account/core remain unchanged"])
    text = json.dumps(report, ensure_ascii=False, indent=2)
    (frozen / "delivery-validation.json").write_text(text, encoding="utf-8")
    (OUT / "delivery-validation.json").write_text(text, encoding="utf-8")
    print(json.dumps(dict(passed=True, checks=len(checks), geography_checks=len(geo["checks"]),
                         frozen=str(frozen)), ensure_ascii=False))


if __name__ == "__main__":
    main()
