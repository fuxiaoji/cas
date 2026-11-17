"""Read-only release checks; writes only its audit receipt under artifacts.

Run with the bundled Python. Never loads or saves a player account in Godot.
"""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import zipfile
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/story-canon-v2/integration-receipt.json"
CORE = "195322d160a42d32ead2f78cdacbb86ac36e1718ec19cd82f1c9b3059c6c8782"
WORLD_SOURCE = "e03719c3e5793154e448fc31848ae21712f65a67f65c556c552e3df542bc05ce"


def read(path):
    return json.loads((ROOT / path).read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    receipt = {"date_utc": datetime.now(timezone.utc).isoformat(),
               "scope": "canon narrative, local presentation and pure visual appearances",
               "human_one_hour_per_chapter_measured": False,
               "historical_native_wasm_full_suite_rerun": False}
    manifest = read("godot/assets/story/canon-v2/manifest.json")
    assets = []
    for row in manifest["assets"]:
        path = ROOT / "godot" / row["path"].removeprefix("res://")
        assert path.is_file(), row["path"]
        assert sha(path) == row["sha256"], row["id"] + " checksum"
        image = Image.open(path)
        assert list(image.size) == row["dimensions"], row["id"] + " dimensions"
        assets.append({"id": row["id"], "sha256": row["sha256"], "size": list(image.size)})
    receipt["selected_raster_assets"] = assets
    registry = read("artifacts/canon-v2-art/registry-audit.json")
    assert registry["only_changed_card"] and registry["unchanged_combat_fields"]
    receipt["ship_registry_audit"] = {k: registry[k] for k in ["identity", "only_changed_card", "unchanged_other_cards", "unchanged_combat_fields"]}
    narrative = read("docs/story/canon-v2/narrative-integrity-receipt.json")
    for chapter in narrative["chapters"]:
        assert chapter["all_routes_complete"] and chapter["all_nodes_reachable"]
        path = ROOT / "godot/data/story-canon-v2" / (chapter["id"] + ".json")
        assert sha(path) == chapter["sha256"]
    receipt["narrative"] = narrative["chapters"]
    candidates = sorted((ROOT / "artifacts/story-canon-v2").glob("appearance-*/receipt.json"), key=lambda p: p.stat().st_mtime)
    appearances = {}
    for path in candidates:
        result = json.loads(path.read_text(encoding="utf-8"))
        appearances[result["display"]] = path.relative_to(ROOT).as_posix()
    assert "Windows" in appearances and "headless" in appearances
    suites = ["artifacts/story-canon-v2/runtime-65464/receipt.json",
              "artifacts/story-canon-v2/service-61180/receipt.json",
              "artifacts/story-canon-v2/menus-gpu-8656/receipt.json",
              appearances["Windows"], appearances["headless"],
              "artifacts/canon-v2-art/resource-review.json",
              "artifacts/canon-v2-art/appearance-consumption-review.json"]
    receipt["qa"] = []
    for path in suites:
        result = read(path)
        assert not result.get("failures", []), path
        assert result.get("checks", 0) > 0, path
        receipt["qa"].append({"path": path, "checks": result["checks"], "failures": result.get("failures", [])})
    core = read("godot/bin/core-current.json")
    assert core["sha256"] == CORE and sha(ROOT / "godot/bin" / core["executable"]) == CORE
    receipt["unchanged_native_core_sha256"] = CORE
    assert sha(Path("D:/downloads/CAS_世界观设定_v1.0.docx")) == WORLD_SOURCE
    receipt["original_worldview_unchanged_sha256"] = WORLD_SOURCE
    account_rows = []
    for baseline in read("artifacts/story-canon-v2/normal-account-readonly-baseline.json"):
        path = Path(baseline["path"])
        content = json.loads(path.read_text(encoding="utf-8"))
        account_rows.append({"path": str(path), "sha256": sha(path),
                             "unchanged_from_start": sha(path) == baseline["sha256"],
                             "valid_json": isinstance(content, dict),
                             "active_run_preserved": bool(content.get("active_run"))})
    receipt["normal_account_read_only"] = account_rows
    assert all(row["unchanged_from_start"] and row["valid_json"] for row in account_rows)
    rendered = sorted((ROOT / "artifacts/story-canon-v2/worldview-render-release").glob("page-*.png"))
    assert len(rendered) == 9
    doc = ROOT / "docs/product/CAS_世界观设定_v1.1_正史增补.docx"
    with zipfile.ZipFile(doc) as archive:
        document_xml = archive.read("word/document.xml").decode("utf-8")
        assert "短手套" in document_xml and "重拾军令" in document_xml
    receipt["worldview"] = {"docx_sha256": sha(doc), "rendered_and_viewed_pages": 9,
                             "visual_receipt": "artifacts/story-canon-v2/worldview-visual-receipt.json"}
    launcher = ROOT / "artifacts/story-canon-v2/launcher-check.log"
    assert "CAS Godot is ready. No game window was opened." in launcher.read_text(encoding="utf-8-sig")
    import_log = (ROOT / "artifacts/godot-launch-import.log").read_text(encoding="utf-8-sig")
    assert "SCRIPT ERROR:" not in import_log and not any(line.startswith("ERROR:") for line in import_log.splitlines())
    receipt["normal_launcher_check_only"] = {"exit": 0, "log_sha256": sha(launcher), "script_or_loading_errors": False}
    paths = set((ROOT / "godot/assets/story/canon-v2").rglob("*.tres"))
    paths.update((ROOT / "godot/scripts").glob("canon_*.gd"))
    paths.update(ROOT / "godot/scripts" / p for p in ["banner_design.gd", "editorial_card.gd", "modes_presentation.gd"])
    paths.update(ROOT / "godot" / p for p in ["scripts/main.gd", "scripts/character_art.gd", "scripts/combat_impact.gd", "scripts/battle_feedback.gd", "scripts/ship_appearance_service.gd", "scripts/ship_detail_presentation.gd", "scripts/port_presentation.gd", "scripts/page_preparation.gd", "scripts/recruit_presentation.gd", "scripts/recruit_banner.gd", "scripts/activity_hub.gd", "scripts/tactical_recruit.gd", "scripts/littoral_sea.gd", "scripts/tide_sea.gd", "scenes/ui/canon_story.tscn", "scenes/ui/recruit_banner.tscn", "scenes/ui/activity_hub.tscn", "scenes/ui/tactical_recruit.tscn", "scenes/ui/editorial_card.tscn"])
    receipt["source_hashes"] = {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted(paths)}
    receipt["limits"] = ["hour-long chapter duration remains a design budget", "new story battles reuse registered real templates", "four-heavy-cruiser wave and Missouri rescue are CG narrative", "existing exit-time ObjectDB cleanup warnings remain"]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"ok": True, "receipt": str(OUT), "assets": len(assets), "qa_suites": len(suites), "rendered_pages": len(rendered)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
