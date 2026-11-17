"""Register images already produced by built-in imagegen; never calls an API."""
import hashlib
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHARACTERS = ROOT / "godot/assets/characters"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    ids = {row["identity"] for row in json.loads((ROOT / "data/ships/cards.json").read_text(encoding="utf-8-sig"))["cards"]}
    for job in manifest["jobs"]:
        identity = job["identity"]
        if identity not in ids:
            raise ValueError("Identity not registered: " + identity)
        source = Path(job["source"])
        target = CHARACTERS / "chibis-generated" / (identity.lower() + ".png")
        portrait = CHARACTERS / "portraits" / (identity.lower() + ".webp")
        if target.exists() and sha(target) != sha(source):
            raise ValueError("Existing candidate must not be silently overwritten: " + identity)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        entry = {"identity":identity, "status":"generated_v2_candidate", "generator":"built-in imagegen",
                 "generation_version":2, "generation_date":manifest["date"],
                 "source_portrait":"res://assets/characters/portraits/"+portrait.name,
                 "source_portrait_sha256":sha(portrait), "source_generated_file":str(source),
                 "style_references":["res://assets/characters/chibis-generated/ibs-u-usn-fletcher.png",
                                     "res://assets/characters/chibis/ibs-u-ijn-kagero.png"],
                 "identity_features":job["identity_features"], "prompt":job["prompt"],
                 "appearance_review":"agent_visual_checked", "user_style_acceptance":"not_asserted",
                 "user_style_acceptance_required_for_integration":False,
                 "scope_completion":"static_projection_candidate_ready",
                 "animation_variants":"outside_current_static_batch",
                 "production_blockers":[],
                 "scope":"local_developer_and_test_builds", "sha256":sha(target)}
        target.with_suffix(".json").write_text(json.dumps(entry,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"registered_candidate_images":len(manifest["jobs"]),"generator":"built-in imagegen"}))


if __name__ == "__main__":
    main()
