"""Register completed built-in image generation files without altering image pixels."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]
GODOT = ROOT / "godot"
TARGET = GODOT / "assets/characters/chibis-generated"

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    jobs = json.loads(args.manifest.read_text(encoding="utf-8"))
    registered = []
    for job in jobs:
        identity = job["identity"]
        if not identity.startswith("IBS-U-") or any(c not in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-" for c in identity):
            raise ValueError("Invalid stable identity")
        source = Path(job["generated_file"]).resolve(strict=True)
        portrait = GODOT / "assets/characters/portraits" / (identity.lower() + ".webp")
        target = TARGET / (identity.lower() + ".png")
        TARGET.mkdir(parents=True, exist_ok=True)
        if target.exists() and sha(target) != sha(source):
            raise ValueError(f"Refusing to replace a different candidate: {identity}")
        shutil.copy2(source, target) if source != target else None
        provenance = {"identity": identity, "status": "generated_v2_candidate", "generator": "built-in imagegen", "generation_version": 2,
            "source_portrait": "res://" + portrait.relative_to(GODOT).as_posix(), "source_portrait_sha256": sha(portrait),
            "source_generated_file": str(source), "sha256": sha(target), "prompt": job["prompt"], "identity_features": job.get("features", []),
            "style_references": ["res://assets/characters/chibis-generated/ibs-u-usn-fletcher.png", "https://ww-rm.top/azurlane_char/"],
            "appearance_review": "agent_visual_checked", "user_acceptance": "not_claimed", "scope": "local_developer_and_test_builds",
            "production_state": "static_default_projection", "directional_animation": "not_part_of_static_projection"}
        target.with_suffix(".json").write_text(json.dumps(provenance, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
        registered.append(identity)
    print(json.dumps({"registered": registered, "count": len(registered)}, ensure_ascii=False))

if __name__ == "__main__":
    main()
