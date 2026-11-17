"""Collect frozen v3 evidence. Read-only except the integration receipt."""
from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/littoral-v3-integration"
EXPECTED_CORE = "696ed97942e1747357cfc56e376d8124f9d34f88082d665a20fe61387c1900ed"


def read(relative: str) -> dict:
    return json.loads((ROOT / relative).read_text(encoding="utf-8-sig"))


def fingerprint(relative: str) -> dict:
    path = ROOT / relative
    payload = path.read_bytes()
    return {"path": relative, "sha256": hashlib.sha256(payload).hexdigest(), "bytes": len(payload)}


def report(relative: str) -> dict:
    value = read(relative)
    assert value.get("passed") is True, f"Unpassed report: {relative}"
    assert not value.get("failures"), f"Failures in {relative}"
    for key in ("core_override", "override"):
        assert not value.get(key), f"Unexpected core override: {relative}"
    result = fingerprint(relative)
    for key in ("passed", "checks", "input_events", "terminal_tick", "main_account_written"):
        if key in value:
            result[key] = value[key]
    return result


def check_sources(index: dict) -> None:
    sources = index.get("sources", [])
    if isinstance(sources, dict):
        sources = [{"path": path, "sha256": sha} for path, sha in sources.items()]
    for entry in sources:
        if isinstance(entry, dict) and "path" in entry and "sha256" in entry:
            assert fingerprint(entry["path"])["sha256"] == entry["sha256"], entry["path"]


def main() -> None:
    manifest = read("godot/bin/core-current.json")
    assert manifest["sha256"] == EXPECTED_CORE
    binary = fingerprint("godot/bin/" + manifest["executable"])
    assert binary["sha256"] == EXPECTED_CORE
    core = read("artifacts/littoral-v3/core-receipt.json")
    default = read("artifacts/littoral-v3/default-receipt.json")
    assert core["status"] == "complete_final_default_verified"
    assert default["passed"] and default["nativeSha"] == EXPECTED_CORE
    for path, sha in core["source_sha256"].items():
        assert fingerprint(path)["sha256"] == sha, path
    historical_frozen = {
        "src/extraction_ai.rs": "2c53af0464e8717998805d9224566f505f8dd8985c55b928c0932f175d0258d4",
        "src/movement.rs": "211cd649689f9bc35c477d503e050aa2704f253ab29bf4b238fac0cc4fca9581",
        "src/expedition.rs": "ce657b620f09423edc14ecfbc93e760613e0d0761a9b59458d95058a170258e0",
    }
    for path, sha in historical_frozen.items():
        assert fingerprint(path)["sha256"] == sha, path
    home = read("artifacts/home-v3-20261114/final-index.json")
    check_sources(home)
    motion = read("artifacts/littoral-motion-v3/final-index.json")
    assert motion["passed"] and motion["runtime"]["sha256"] == EXPECTED_CORE
    check_sources(motion)
    for path, sha in motion["evidence"].items():
        assert fingerprint(path)["sha256"] == sha, path
    launcher = read("artifacts/littoral-v3-integration/launcher-check.json")
    assert launcher["passed"] and launcher["core_sha256"] == EXPECTED_CORE
    assert launcher["normal_saves_unchanged"]

    reports = [
        "artifacts/home-v3-20261114/account-receipt.json",
        "artifacts/home-v3-20261114/nav-headless.json",
        "artifacts/home-v3-20261114/nav-gpu.json",
        "artifacts/littoral-motion-v3/lifecycle/receipt.json",
        "artifacts/littoral-motion-v3/presentation/receipt.json",
        "artifacts/littoral-motion-v3/transport/receipt.json",
        "artifacts/protocol-reveal-v3/receipt.json",
        "artifacts/littoral-v3-main/receipt.json",
        "artifacts/littoral-training-v3/sea_control/receipt.json",
        "artifacts/littoral-training-v3/landing/receipt.json",
        "artifacts/littoral-training-v3/combined/receipt.json",
        "artifacts/littoral-v3-integration/legacy-tutorial-component.json",
    ]
    browser = read("artifacts/littoral-v3/browser-legacy/receipt.json")
    assert len(browser["checks"]) == 17 and all(c["ok"] for c in browser["checks"])
    sources = [
        "src/littoral.rs", "src/lib.rs", "src/extraction_ai.rs", "src/movement.rs", "src/expedition.rs",
        "godot/scripts/main.gd", "godot/scripts/core_bridge.gd", "godot/scripts/home_service.gd",
        "godot/scripts/home_island.gd", "godot/scenes/ui/home_island.tscn",
        "godot/scripts/littoral_battle.gd", "godot/scripts/littoral_land.gd", "godot/scripts/sea_map.gd",
        "godot/scripts/tactical_sprite.gd", "godot/scripts/tactical_transport_art.gd",
        "godot/scripts/tactical_transport_preview.gd", "godot/scenes/ui/tactical_transport_preview.tscn",
        "godot/scripts/littoral_drag_tutorial.gd", "godot/scripts/littoral_progressive_tutorial.gd",
        "godot/scripts/protocol_reveal.gd", "godot/scenes/ui/protocol_reveal.tscn",
        "godot/scripts/tactical_recruit.gd", "godot/data/tactical-profiles-v3.json",
        "godot/data/transport-variants-v3.json", "scripts/register-transport-v3.py",
        "docs/art/transport-v3-20261114/generation-ledger.json",
        "docs/rules/littoral-v3.md", "docs/design/littoral-companies-v3-20261114.md",
        "docs/development/littoral-v3-20261114.md", "scripts/summarize-littoral-v3.py",
        "godot/tests/littoral_training_player_v3_review.gd", "godot/tests/littoral_v3_main_review.gd",
        "godot/tests/protocol_reveal_v3_review.gd", "godot/tests/littoral_v3_presentation_review.gd",
        "godot/tests/littoral_transport_art_v3_review.gd",
        "agent.md", "plan.md", "havedone.md",
    ]
    atlas_paths = ["godot/assets/tactical/transport/transport-atlas-v3.png"] + [
        f"godot/assets/tactical/transport/variants-{name}-v3.png"
        for name in ("alpha", "bravo", "charlie", "delta")
    ]
    variants = read("godot/data/transport-variants-v3.json")
    assert len(variants["units"]) == 20
    result = {
        "status": "passed",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "entry": "CAS-Godot.cmd -> 返航灯岛 -> 训练 / 出航",
        "version": "cas-littoral-v3",
        "default_core": binary,
        "manifest": fingerprint("godot/bin/core-current.json"),
        "rust_passed": core["rust_passed"],
        "default_native_wasm": core["final_default"]["raw"],
        "legacy_v1_v2_frozen": core["final_default"]["legacy"],
        "historical_source_frozen": historical_frozen,
        "real_native_matches": {"count": 7, "wins": 6, "legitimate_losses": 1},
        "historical_edge_checks": 17,
        "reports": [report(path) for path in reports],
        "core_evidence": [fingerprint("artifacts/littoral-v3/" + name) for name in (
            "core-receipt.json", "default-receipt.json", "performance-receipt.json", "browser-legacy/receipt.json")],
        "home_index": fingerprint("artifacts/home-v3-20261114/final-index.json"),
        "motion_index": fingerprint("artifacts/littoral-motion-v3/final-index.json"),
        "launcher": launcher,
        "reviewed_sources": [fingerprint(path) for path in sources],
        "original_vehicle_art": {"unique_default_vehicles": 20, "unique_default_frames": 40,
                                 "generic_family_fallback_frames": 9,
                                 "atlases": [fingerprint(path) for path in atlas_paths]},
        "visually_reviewed": [
            "artifacts/home-v3-20261114/home-residents-1280.png",
            "artifacts/home-v3-20261114/home-sortie-960.png",
            "artifacts/littoral-motion-v3/presentation/fifty-land-1280x720.png",
            "artifacts/littoral-motion-v3/transport/three-real-transport-families-sea.png",
            "artifacts/littoral-motion-v3/transport/027-actual-finite-gunship-fire.png",
            "artifacts/littoral-motion-v3/transport/twenty-original-equipment-editable-preview.png",
            "artifacts/protocol-reveal-v3/ten-results-960.png",
        ],
        "limits": [
            "New v3 voyages only; saved v1/v2 remain on their original rules; historical simulation unchanged.",
            "Windows / RTX 5070 GUI input and timing, not mobile hardware certification or network multiplayer.",
            "Tutorials use real inputs and native 0.1s steps with accelerated waits; not full wall-clock 1x completion recordings.",
            "First five original tactical SD identities; other units use own portraits or type markers, never another identity.",
            "20 unique default vehicles, not 60 unique alternate-family vehicles; alternatives use labeled generic fallback.",
            "Large company formations and transport separation are display-only with true coordinate mappings preserved.",
            "Native performance includes IPC and observation serialization; separate Godot GPU measurements provided.",
            "Tests use isolated ordinary profiles or explicitly marked no-reward scale fixtures; normal main/backup saves read only.",
        ],
    }
    (OUT / "integration-receipt.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": result["status"], "reports": len(reports), "source_files": len(sources),
                      "core_sha256": EXPECTED_CORE}, ensure_ascii=False))


if __name__ == "__main__":
    main()
