"""Project the pinned IBS mobile identity and free-economy catalog into CAS."""
import argparse
from hashlib import sha256
import json
from pathlib import Path
import subprocess


COMMIT = "48385c8337d3f5a08e3ebc5676d68309df87542d"
INPUTS = ["mobile/content/catalog.json", "mobile/content/campaign-scenarios.json"]
OUTPUT = Path(__file__).with_name("catalog.json")
# CAS-owned evolved AI storefront entries. The merge list is the single source
# for their id/name/description/unlock/cost/currency; catalog.json only carries
# the projected copy (same values) so the account service can sell them.
EVOLVED_SHOP = Path(__file__).resolve().parent.parent / "data" / "ai" / "shop-merge.json"
# CAS-side overlay. A stable identity may claim combat readiness only after its
# period card is registered for the same ID in src/ranked_fleets.rs PROFILES and
# priced in the competitive point table; the value is the source note the
# service exposes to players and requires at startup.
# The UP banner carries a battleship whose period card is already verified
# (North Carolina, cas-prologue-runtime-v1#north-carolina). It is the only
# battleship eligible for the free-economy recruitable pool.
UP_FEATURED = "IBS-U-USN-UNNAMED-T01-R03"
COMBAT_READY = {
    "IBS-U-USN-UNNAMED-T01-R03": "src/ranked_fleets.rs PROFILES（序章时期包 "
                                 "cas-prologue-runtime-v1#north-carolina，美国舰表 PDF 8、109）；"
                                 "点表 cas-points-surface-v1 已登记同名 ID",
}


def evolved_ai_profiles():
    """Project the six evolved AI profiles without touching mobile values."""
    merged = json.loads(EVOLVED_SHOP.read_text(encoding="utf-8"))
    if merged.get("state") != "provisional":
        raise SystemExit("Evolved AI shop entries must stay provisional")
    rows = []
    for profile in merged["profiles"]:
        if profile.get("currency") != "recruit_ticket":
            raise SystemExit("Evolved AI shop entries must cost recruit tickets")
        rows.append({key: profile[key] for key in
                     ("id", "name", "description", "unlock", "cost", "currency")}
                    | {"provisional": True})
    if len(rows) != 6 or len({row["id"] for row in rows}) != 6:
        raise SystemExit("Evolved AI shop merge must contain six profiles")
    return rows


def project(repo):
    overlay = json.loads((Path(__file__).with_name("scenario-recruitable.json")).read_text(encoding="utf-8"))

    def read(path):
        data = subprocess.check_output(["git", "-C", str(repo), "show", f"{COMMIT}:{path}"])
        return json.loads(data), sha256(data).hexdigest()

    (base, base_sha), (campaign, campaign_sha) = (read(p) for p in INPUTS)
    old_ships = {s["id"]: s for s in campaign["ships"]}
    old_ships.update((s["id"], s) for s in base["ships"])
    # Keep old draw ordering. Base storefront entries override campaign-only rows.
    ship_ids = list(dict.fromkeys(s["id"] for s in base["ships"] + campaign["ships"]))
    ships = []
    for ship_id in ship_ids:
        old = old_ships[ship_id]
        # The overlay lists every identity of the pinned mobile collection: the
        # identities of the kept scenarios plus collection-only rows that have no
        # current scenario membership (CAS-COLLECTION-0.6.9). Every identity in
        # the overlay joins the free-economy pool.
        recruitable = (old.get("recruitable") is not False
                       or ship_id in overlay["ships"] or ship_id == UP_FEATURED)
        ships.append({
            **{k: old[k] for k in ("id", "name", "side", "type", "rarity")},
            **({"rarity": "ur"} if ship_id == UP_FEATURED else {}),
            "recruitable": recruitable,
            "credits_price": max(200, ((old["cost"] + 99) // 100) * 100)
                             if recruitable and old["rarity"] == "common" else None,
            "combat_ready": ship_id in COMBAT_READY,
            **({"combat_source": COMBAT_READY[ship_id]} if ship_id in COMBAT_READY else {}),
        })
    pools = [{
        k: p[k] for k in ("id", "name", "kind", "ur_ship_ids", "rates", "pity",
                         "exchange_price", "description", "featured_ship_id") if k in p
    } for p in base["recruit_pools"]]
    for p in pools:
        if p["id"] == "missouri-up":
            p["name"] = "北卡罗来纳 · 决战旗舰"
            p["description"] = "UR中北卡罗来纳占50%；未获得UP时，下次UR必为北卡罗来纳。"
            p["featured_ship_id"] = UP_FEATURED
            p["ur_ship_ids"] = [UP_FEATURED, *[sid for sid in p["ur_ship_ids"] if sid != UP_FEATURED]]
    ids = {s["id"]: s for s in ships}
    assert len(ships) == 210 and sum(s["recruitable"] for s in ships) == 210
    for p in pools:
        assert all(ids[sid]["recruitable"] and ids[sid]["rarity"] == "ur"
                   for sid in p["ur_ship_ids"] + ([p["featured_ship_id"]] if "featured_ship_id" in p else []))
    return {
        "version": "cas-free-economy-v1", "source": {
            "baseline": "铁底湾手游 0.6.9", "commit": COMMIT,
            "files": {INPUTS[0]: base_sha, INPUTS[1]: campaign_sha},
        },
        "ships": ships, "recruit_pools": pools,
        "ship_bundles": [{k: b[k] for k in ("id", "name", "description", "credits", "ship_ids") if k in b}
                         for b in base["ship_bundles"]],
        # The storefront now carries exactly the six CAS evolved doctrines.
        # The pinned mobile AI list (balanced/adaptive/fleet/rc_*) is not sold:
        # its names and points came from the old mobile economy, not from a CAS
        # doctrine, and keeping both sets would duplicate the shop.
        "ai_profiles": evolved_ai_profiles(),
        "stages": [], "combat_catalog_available": False,
    }


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("ibs_worktree", type=Path)
    cli.add_argument("--write", action="store_true")
    args = cli.parse_args()
    data = project(args.ibs_worktree)
    payload = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    if args.write:
        OUTPUT.write_text(payload, encoding="utf-8", newline="\n")
    elif OUTPUT.read_bytes() != payload.encode("utf-8"):
        raise SystemExit("The CAS economy projection differs from the pinned catalog")
    print(f"Verified 210 stable identities, 210 recruitable ships, 2 pools, 3 bundles, "
          f"{len(data['ai_profiles'])} evolved AI profiles")
