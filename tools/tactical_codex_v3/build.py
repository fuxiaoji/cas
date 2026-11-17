"""Package the native v3 catalogue and existing art as a completely offline codex."""
from pathlib import Path
import hashlib
import json
import shutil
import argparse

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "output/tactical-codex-v3-20261115"
DATA = ROOT / "godot/data"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", choices=["3", "4"], default="3")
    parser.add_argument("--catalogue", type=Path, help="Explicit native-export source; v4 defaults to the isolated published binding, never the shared draft")
    args = parser.parse_args()
    global DEST
    version = args.version
    DEST = ROOT / f"output/tactical-codex-v{version}-20261115"
    DEST.mkdir(parents=True, exist_ok=True)
    source_path = args.catalogue.resolve() if args.catalogue else DATA / ("island-war-v4-published.json" if version == "4" else "island-war-v3.json")
    source = source_path.read_bytes()
    baseline = json.loads(source)
    if baseline.get("version") != f"cas-island-war-v{version}":
        raise ValueError("Catalogue version does not match requested package")
    native_ids = {row["id"] for row in baseline["cards"]}
    art = json.loads((DATA / "tactical-art-v2.json").read_text(encoding="utf-8"))
    vehicles = json.loads((DATA / "tactical-vehicles-v3.json").read_text(encoding="utf-8"))
    if version == "4":
        by_id = {row["id"]: row for row in art["units"]}
        daily = json.loads((DATA / "home-daily-art-v1.json").read_text(encoding="utf-8"))
        for identity, row in daily["units"].items():
            if identity.startswith("MCP-") and row.get("approved") and row.get("portrait"):
                by_id[identity] = row
        art["units"] = list(by_id.values())
        extra_vehicle = DATA / "tactical-vehicles-v4.json"
        if extra_vehicle.is_file():
            vehicles["vehicles"].update(json.loads(extra_vehicle.read_text(encoding="utf-8"))["vehicles"])
    copied = {}

    def asset(uri):
        if uri in copied:
            return copied[uri]
        local = ROOT / "godot" / uri.removeprefix("res://")
        if not local.is_file():
            raise FileNotFoundError(local)
        relative = Path("assets") / uri.removeprefix("res://assets/")
        target = DEST / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(local, target)
        copied[uri] = relative.as_posix()
        return copied[uri]

    illustrations = {}
    for unit in art["units"]:
        if unit["id"] not in native_ids:
            continue
        idle = unit["frames"][unit.get("animations", {}).get("idle", [0])[0]]
        illustrations[unit["id"]] = {
            "portrait": asset(unit["portrait"]),
            "sprite": {"source": asset(idle["source"]), "rect": idle["rect"]},
        }
    vehicle_art = {}
    for kind, row in vehicles["vehicles"].items():
        frame = row["frames"]["N"]
        vehicle_art[kind] = {"source": asset(row["atlas"]), "rect": frame["region"]}
    weapon_art = {}
    weapon_manifest = DATA / "tactical-weapons-art-v3.json"
    if weapon_manifest.is_file():
        families = json.loads(weapon_manifest.read_text(encoding="utf-8"))["weapons"]
        for weapon in baseline["weapons"]:
            family_id = weapon.get("family_id", weapon["id"])
            row = families[family_id]
            weapon_art[weapon["id"]] = {"source": asset(row["source"]), "rect": row["region"], "representation": row.get("representation", "weapon"), "family_id": family_id, "shared_class_art": True}
    for font in ["NotoSansSC.ttf", "NotoSerifSC.ttf"]:
        asset("res://assets/fonts/" + font)
    bundle = {
        "baseline": baseline,
        "art": illustrations,
        "vehicleArt": vehicle_art,
        "weaponArt": weapon_art,
        "source_sha256": hashlib.sha256(source).hexdigest(),
        "source": source_path.relative_to(ROOT).as_posix() if source_path.is_relative_to(ROOT) else str(source_path),
    }
    (DEST / "data.js").write_text("window.CODEX_DATA=" + json.dumps(bundle, ensure_ascii=False, separators=(",", ":")) + ";\n", encoding="utf-8")
    (DEST / "baseline-native.json").write_bytes(source)
    for name in ["index.html", "style.css", "app.js", "accuracy.js", "cadence.js"]:
        shutil.copy2(Path(__file__).with_name(name), DEST / name)
    if version == "4":
        for name in ["index.html", "app.js"]:
            page = DEST / name
            page.write_text(page.read_text(encoding="utf-8").replace("cas-island-war-v3", "cas-island-war-v4").replace("tactical-codex-v3", "tactical-codex-v4").replace("方案-v3", "方案-v4").replace("PERSONNEL / 22", f"PERSONNEL / {len(baseline['cards'])}"), encoding="utf-8")
    (DEST / "README.txt").write_text("双击 index.html 离线使用。所有图片、字体和数据均位于此文件夹，无需网络。\n滑块仅调整浏览器内方案副本；导出 JSON/CSV 不会修改游戏或账号。\n原核基线：" + bundle["source_sha256"] + "\n", encoding="utf-8")
    print(json.dumps({"units": len(baseline["cards"]), "weapons": len(baseline["weapons"]), "local_assets": len(copied), "sha256": bundle["source_sha256"], "output": str(DEST)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
