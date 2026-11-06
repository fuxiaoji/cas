"""Read and verify named campaign art from the pinned mobile portrait manifest."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REVISION = "48385c8337d3f5a08e3ebc5676d68309df87542d"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_checkout", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    def source(path):
        return subprocess.check_output(
            ["git", "-C", str(args.source_checkout), "show", f"{REVISION}:{path}"]
        )

    manifest_path = "mobile/content/fleet-portrait-manifest.json"
    manifest = {row["ship_id"]: row for row in json.loads(source(manifest_path))["ships"]}
    crosswalk = ROOT / "data/campaign/roster-crosswalk.json"
    rows = json.loads(crosswalk.read_text(encoding="utf-8"))["ships"]
    folder = ROOT / "client/src/assets/portraits"
    ledger = folder / "ledger.json"
    data = json.loads(ledger.read_text(encoding="utf-8"))
    entries = []
    channel_path = ROOT / "data/campaign/period/channel-runtime.json"
    channel_ids = {row["id"] for row in json.loads(channel_path.read_text(encoding="utf-8"))["ships"]}
    for row in rows:
        instance = row.get("cas_source_instance", {})
        if instance.get("scenario_id") == "cas-rs-cape-st-george":
            class_id = instance["ship_id"]
            filename = "cape-" + class_id + ".png"
        elif row["ibs_ship_id"] in channel_ids:
            class_id = row["ibs_ship_id"]
            filename = "channel-" + class_id.lower().removeprefix("ibs-u-") + ".png"
        else:
            continue
        item = manifest[row["ibs_ship_id"]]
        assert item["status"] == "ready" and item["character_id"] == row["ibs_character_id"]
        path = "mobile/public" + item["path"]
        blob = (args.source_checkout / path).read_bytes()
        digest = hashlib.sha256(blob).hexdigest()
        pointer = re.search(rb"^oid sha256:([0-9a-f]{64})$", source(path), re.M)
        assert pointer and pointer[1].decode() == digest == item["sha256"], path
        local = folder / filename
        if local.exists() or args.check:
            assert local.read_bytes() == blob, local
        else:
            local.write_bytes(blob)
        entries.append(dict(cas_class_id=class_id, ibs_character_id=item["character_id"],
                            character_name=item["name"], source_path=path, source_commit=REVISION,
                            path=local.name, sha256=digest, mapping="named_identity"))
    assert len(entries) == len({row["ibs_character_id"] for row in entries}) == 10 + len(channel_ids)
    if args.check:
        assert [row for row in data["assets"] if row["mapping"] == "named_identity"] == entries
    else:
        data["assets"] = [row for row in data["assets"] if row["mapping"] != "named_identity"] + entries
        ledger.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"Verified {len(entries)} named campaign portraits against the pinned manifest and LFS object IDs.")


if __name__ == "__main__":
    main()
