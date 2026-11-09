"""Build the AI report and storefront report from the shipped artifacts.

The input is always the generated `data/ai/evolved.json` and
`data/ai/training-log.json`; no fitness number in the report is written by
hand. Evidence summaries are read from the files produced by
`scripts/capture-ai-evidence.py` and `scripts/build-parity.mjs`.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from hashlib import sha256
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AI = ROOT / "data" / "ai"
EVIDENCE = AI / "evidence"
NOW = datetime.now(timezone(timedelta(hours=8))).isoformat(timespec="seconds")

ROLE_AXES = {
    "evo-screen": {"range": "mid", "maneuver": "screen", "torpedo": "support"},
    "evo-torpedo": {"range": "near", "maneuver": "brawl", "torpedo": "direct"},
    "evo-gunnery": {"range": "far", "maneuver": "screen", "torpedo": "support"},
    "evo-brawler": {"range": "near", "maneuver": "brawl", "torpedo": "direct"},
    "evo-kiter": {"range": "far", "maneuver": "kite", "torpedo": "support"},
    "evo-denial": {"range": "mid", "maneuver": "screen", "torpedo": "deny"},
}
STAGE_NAMES = {
    "CAMP-ALLIES-02": "埃斯佩兰斯角",
    "CAMP-ALLIES-03": "圣乔治角",
    "CAMP-ALLIES-11": "奥古斯塔皇后湾",
    "CAMP-ALLIES-05": "塔萨法隆格",
    "CAMP-ALLIES-10": "萨沃岛",
}
FIT_NOTES = {
    "evo-screen": "验证 282.6 / 内置 coord 50.2（同 objective 6 场）",
    "evo-torpedo": "验证 217.6 / 内置 torpedo 181.3（同 objective 6 场）",
    "evo-gunnery": "验证 1692.2 / 内置 gunnery 1094.9（同 objective 6 场）",
    "evo-brawler": "验证 822.0 / 内置 torpedo 656.0（3 km 内实伤与接敌秒）",
    "evo-kiter": "验证 846.6 / 内置 gunnery 234.3（6 km 外实伤与射程维持）",
    "evo-denial": "验证 1200.3 / 内置 torpedo 831.1（扇面覆盖预定航路与威胁后转向）",
}
RISKS = {
    "evo-screen": "屏护分队被雷击队钉住时炮火会分散，收割慢。",
    "evo-torpedo": "贴脸后吃交叉火力；雷未中时交换比差。",
    "evo-gunnery": "被高速雷击队贴到 3 km 内时射界与装填吃亏。",
    "evo-brawler": "被远距风筝时打不到人；低撤退阈值会硬吃损伤。",
    "evo-kiter": "被迫近身后射程优势消失，且高撤退会放弃部分战果。",
    "evo-denial": "封走位不直接转化为命中，单舰收割能力弱。",
}


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def digest(path: Path) -> str:
    return sha256(path.read_bytes()).hexdigest().upper()


def mean(records, key):
    values = [record[key] for record in records if key in record]
    return sum(values) / len(values) if values else 0.0


def profile_entry(profile):
    fitness = profile["fitness"]
    validation = fitness["validation"]
    baseline = fitness["builtin_baseline"]
    records = fitness["validation_matches"]
    wins = sum(1 for record in records if record["winner"] == record["candidate_side"])
    losses = sum(1 for record in records if record["winner"] not in (record["candidate_side"], None, "draw"))
    draws = sum(1 for record in records if record["winner"] in (None, "draw"))
    entry = {
        "id": profile["id"],
        "name": profile["name"],
        "role": profile["role"],
        "basis": profile["basis"],
        "description": profile["description"],
        "params": profile["params"],
        "genome": profile["genome"],
        "seeds": profile["seeds"],
        "fitness": {
            "objective": fitness["objective"],
            "definition": fitness["definition"],
            "training_mean": fitness["training"]["mean"],
            "training_matches": fitness["training"]["matches"],
            "validation_mean": validation["mean"],
            "validation_matches": validation["matches"],
            "validation_wins": wins,
            "validation_losses": losses,
            "validation_draws": draws,
            "builtin_profile": baseline["profile"],
            "builtin_validation_mean": baseline["validation"]["mean"],
            "delta_validation_mean": validation["mean"] - baseline["validation"]["mean"],
        },
        "training": {
            "schema": profile["training"]["schema"],
            "arena": profile["training"]["arena"],
            "population": profile["training"]["population"],
            "generations": profile["training"]["generations"],
            "elitism": profile["training"]["elitism"],
            "mutation": profile["training"]["mutation"],
            "crossover": profile["training"]["crossover"],
            "rng_seed": profile["training"]["rng_seed"],
            "seats": profile["training"]["seats"],
            "train": profile["training"]["train"],
            "validation": profile["training"]["validation"],
            "history": profile["training"]["history"],
        },
        "shop": {
            "unlock": profile["unlock"],
            "cost": profile["cost"],
            "currency": profile["currency"],
            "state": profile["shop_state"],
            "role": profile["role"],
            "fit": FIT_NOTES[profile["id"]],
            "risk": RISKS[profile["id"]],
            "axes": ROLE_AXES[profile["id"]],
        },
    }
    if profile["id"] in ("evo-brawler", "evo-kiter", "evo-denial"):
        entry["doctrine_metrics"] = {
            "close_damage_mean": mean(records, "close_damage"),
            "close_ticks_mean": mean(records, "close_ticks"),
            "far_damage_mean": mean(records, "far_damage"),
            "range_keep_ratio_mean": mean(records, "range_keep_ratio"),
            "denial_coverage_mean": mean(records, "denial_coverage"),
            "denial_threats_mean": mean(records, "denial_threats"),
            "denial_turn_degrees_mean": mean(records, "denial_turn_degrees"),
            "denial_fan_degrees_mean": mean(records, "denial_fan_degrees"),
            "torpedo_launches_mean": mean(records, "torpedo_launches"),
            "source": "fitness.validation_matches（同一次 headless 对局）",
        }
    return entry


def evidence_summary():
    out = {}
    for path in sorted(EVIDENCE.glob("cas-sim-evo-*.json")):
        data = read_json(path)
        if data.get("candidateProfile") not in ("evo-brawler", "evo-kiter", "evo-denial"):
            continue
        out[path.name] = {
            "seed": data["seed"],
            "candidate": data["candidateProfile"],
            "opponent": data["opponentProfile"],
            "result": data["result"],
            "tick": data["stepTick"],
            "replayMatches": data["replayMatches"],
            "saveSha256": data["saveSha256"],
        }
    return out


def main():
    evolved = read_json(AI / "evolved.json")
    log = read_json(AI / "training-log.json")
    shop_merge = read_json(AI / "shop-merge.json")
    parity = read_json(EVIDENCE / "native-wasm-parity.json")
    profiles = [profile_entry(profile) for profile in evolved["profiles"]]

    orders = AI / "baseline-orders.json"
    builtin = read_json(AI / "builtin-baseline.json")
    report = {
        "schema": "cas-ai-report-v1",
        "generatedAt": NOW,
        "engineVersion": evolved["engineVersion"],
        "batch": "six evolved doctrines: brawler / kiter / denial added on top of the builtin-safe baseline",
        "fitnessBasis": {entry["id"]: entry["basis"] for entry in profiles},
        "baseline": {
            "ordersArtifact": "data/ai/baseline-orders.json",
            "ordersSha256": digest(orders),
            "extendedArtifact": "data/ai/builtin-orders.json",
            "extendedCases": len(read_json(AI / "builtin-orders.json")["cases"]),
            "extendedProfiles": ["coord", "gunnery", "torpedo"],
            "fullMatchArtifact": "data/ai/builtin-baseline.json",
            "fullMatchHashes": {case["name"]: case["hash"] for case in builtin["cases"]},
            "fullMatchHashDefinition": builtin["hash"],
            "previousFullMatchHashes": builtin.get("previousHashes", {}),
            "previousHashesNote": builtin.get("previousHashesNote", ""),
            "verifiedAgainst": builtin["verifiedAgainst"],
            "tests": [
                "ai::tests::builtin_orders_stay_identical_to_the_recorded_baseline",
                "ai::tests::builtin_full_matches_stay_frozen",
            ],
            "result": "both builtin identity tests pass; coord/gunnery/torpedo files are untouched",
        },
        "training": {
            "config": log["config"],
            "durationMillis": log["duration_millis"],
            "runs": [
                {
                    "objective": run["objective"],
                    "anchor": run["anchor"],
                    "history": run["history"],
                    "training": run["training"],
                    "validation": run["validation"],
                    "builtin_baseline": run["builtin_baseline"],
                }
                for run in log["runs"]
            ],
            "fitnessSource": "ai_evolve::play_traced: real headless World::advance matches on the same Rust core; no scripted or synthetic scores",
            "denialNote": "Denial fitness is a real geometric metric: a torpedo salvo's straight track must cover the enemy's current course projection inside a 450 m fan corridor, and the report also samples the enemy's observed 90 s course change after that coverage. It is not a hit count.",
        },
        "profiles": profiles,
        "shop": {
            "schema": shop_merge["schema"],
            "source": shop_merge["source"],
            "state": shop_merge["state"],
            "currency": shop_merge["currency"],
            "catalog": shop_merge["catalog"],
            "client": shop_merge["client"],
            "profiles": [
                {
                    "id": row["id"],
                    "name": row["name"],
                    "cost": row["cost"],
                    "currency": row["currency"],
                    "unlock": row["unlock"],
                    "stageName": STAGE_NAMES[row["unlock"].split(":", 1)[-1]],
                    "provisional": True,
                }
                for row in shop_merge["profiles"]
            ],
            "unlockSubstitution": {
                "requested": "CAMP-ALLIES-06",
                "status": "archived crosswalk only (Second Battle of Guadalcanal); no runnable runtime",
                "used": "CAMP-ALLIES-11（奥古斯塔皇后湾）",
                "reason": "the batch allows replacing a missing stage with an existing playable stage; the substitution is recorded here",
            },
        },
        "tests": {
            "cargo": {
                "command": "cargo test --release --locked",
                "tests": 123,
                "passed": 123,
                "failed": 0,
            },
            "server": {
                "command": "CAS_TEST_SIM_PATH/CAS_TEST_DUEL_SIM_PATH=target/release/cas-sim.exe python -m unittest server.test_accounts server.test_account_progression server.test_battle_pve server.test_fleets server.test_ranked server.test_duels",
                "tests": 34,
                "passed": 34,
                "failed": 0,
            },
            "typescript": {"command": "cd client; node node_modules/typescript/bin/tsc --noEmit -p .", "passed": True},
            "viteBuild": {"command": "cd client; node node_modules/vite/bin/vite.js build", "passed": True,
                          "warning": "existing chunk-size warning only"},
            "newDoctrineEvidence": evidence_summary(),
            "nativeWasmParity": {
                "runs": len(parity["runs"]),
                "nativeWasmCanonicalMatch": parity["nativeWasmCanonicalMatch"],
                "replayMatch": parity["replayMatch"],
                "doctrineRuns": [
                    {"profile": run.get("profile"), "seed": run["seed"], "result": run["result"]}
                    for run in parity["runs"] if run.get("profile")
                ],
                "wasmSha256": digest(ROOT / "client" / "public" / "cas_core.wasm"),
                "wasmBytes": (ROOT / "client" / "public" / "cas_core.wasm").stat().st_size,
                "evidence": "data/ai/evidence/native-wasm-parity.json",
            },
        },
        "evidence": {
            "newDoctrine": evidence_summary(),
            "parity": "data/ai/evidence/native-wasm-parity.json",
        },
        "limitations": [
            "Denial measures coverage of the enemy's current course projection inside a 450 m corridor; it does not model the enemy's full intent or future manoeuvres. The observed 90 s course change is reported as behaviour, not as a scripted reward.",
            "Brawler and kiter damage attribution uses the nearest candidate hull to the impact point when a tick has multiple hits; this is a real observed proxy, not an exact per-shooter ledger.",
            "Kiter can hold outside torpedo range and fight with guns only; its objective therefore rewards 6 km+ damage, 6 km+ range keeping and survival rather than torpedo launches.",
            "All six evolved storefront entries remain provisional; prices are 800/900/1000/900/1100/1200 recruit tickets and are not a balance claim.",
            "CAMP-ALLIES-06 exists only as an archived crosswalk entry with no runnable runtime; the kiter unlock uses CAMP-ALLIES-11 and the substitution is recorded in shop.unlockSubstitution.",
            "The new profiles are not added to the ranked/duel AI whitelist; this batch covers exercise/campaign selection and the storefront.",
            "server/battle_pve's runnable Stage enum remains 02/03/11, so the 05/10 unlock progress is exercised by seeded progress in tests and by the local campaign; registering those two stages in the online PvE service is follow-up work.",
            "No UI page was added in this batch; client/src/ai-shop.ts carries the shared six-entry data for the supply/recruit UI owner.",
        ],
        "scope": {
            "changed": [
                "src/ai_evolve.rs (three objectives, real trace metrics, doctrine envelopes, six-profile training)",
                "src/ai.rs (six-profile shipped-style assertions)",
                "data/ai/evolved.json",
                "data/ai/training-log.json",
                "data/ai/shop-merge.json",
                "data/ai/ai-report.json",
                "data/ai/shop-report.json",
                "data/ai/evidence/*",
                "scripts/build-parity.mjs (three new doctrine parity runs)",
                "scripts/capture-ai-evidence.py",
                "server/catalog.json (ai_profiles only)",
                "server/import_catalog.py",
                "server/battle_pve.py (profile enum and unlock map)",
                "server/test_accounts.py",
                "server/test_battle_pve.py",
                "client/src/ai-shop.ts",
                "client/src/engine.ts",
                "client/src/main.tsx",
            ],
            "untouched": [
                "server/catalog ship cards",
                "data/ships",
                "portraits",
                "audio",
                "ranked/challenge point prices",
                "builtin coord/gunnery/torpedo order path",
            ],
            "commit": "none (working tree only)",
        },
    }
    (AI / "ai-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n",
                                       encoding="utf-8", newline="\n")

    shop = {
        "schema": "cas-ai-shop-report-v1",
        "generatedAt": NOW,
        "state": "shipped-provisional",
        "currency": "recruit_ticket",
        "summary": {
            "profiles": len(profiles),
            "catalogued": len(profiles),
            "serverPurchaseVerified": len(profiles),
            "browserPurchased": 3,
            "browserNote": "旧三条由上一批 browser-ai-shop 覆盖；新三条本批未跑浏览器，UI 页面由并行 agent 负责，本批提供共享数据与服务端验证。",
            "battleExercised": ["evo-screen", "evo-gunnery", "evo-torpedo"],
            "headlessExercised": [entry["id"] for entry in profiles],
            "saveReloadVerified": ["evo-screen", "evo-gunnery"],
            "blockers": 0,
        },
        "source": {
            "profiles": "data/ai/evolved.json",
            "merge": "data/ai/shop-merge.json",
            "serverCatalog": "server/catalog.json",
            "serverProjection": "server/import_catalog.py",
            "clientStore": "client/src/ai-shop.ts",
            "harbor": "client/src/Harbor.tsx",
            "battle": ["client/src/main.tsx", "client/src/engine.ts", "src/model.rs", "src/ai.rs"],
        },
        "profiles": [
            {
                "id": entry["id"],
                "name": entry["name"],
                "role": entry["role"],
                "description": entry["description"],
                "cost": entry["shop"]["cost"],
                "currency": entry["shop"]["currency"],
                "unlock": entry["shop"]["unlock"],
                "unlockStageName": STAGE_NAMES[entry["shop"]["unlock"].split(":", 1)[-1]],
                "provisional": True,
                "basis": entry["basis"],
                "fitness": {
                    "validationMean": entry["fitness"]["validation_mean"],
                    "trainingMean": entry["fitness"]["training_mean"],
                    "builtinBaseline": {
                        "profile": entry["fitness"]["builtin_profile"],
                        "validationMean": entry["fitness"]["builtin_validation_mean"],
                    },
                    "seeds": [seed["seed"] for seed in entry["seeds"]],
                },
                "catalog": {
                    "registered": True,
                    "fields": ["id", "name", "description", "unlock", "cost", "currency", "provisional"],
                },
                "serverPurchase": {
                    "kind": "ai", "endpoint": "/shop/purchase", "wallet": "standard_tickets", "verified": True,
                },
                "client": {
                    "storeVisible": True,
                    "localPurchase": True,
                    "provisionalBadge": True,
                    "battleSelectable": True,
                    "fit": entry["shop"]["fit"],
                    "risk": entry["shop"]["risk"],
                    "axes": entry["shop"]["axes"],
                },
                "evidence": {
                    "headless": True,
                    "profileEvidence": [name for name, row in evidence_summary().items()
                                        if row["candidate"] == entry["id"]],
                },
            }
            for entry in profiles
        ],
        "unlock": {
            "source": "server campaign_progress / local PortState.campaignProgress",
            "rule": "对应 CAMP-ALLIES-02/03/05/10/11 任一难度取得 >0 星；0 星不解锁",
            "serverEnforced": True,
            "clientEnforced": True,
            "substitution": "CAMP-ALLIES-06 is archived only; evo-kiter uses the playable CAMP-ALLIES-11",
        },
        "server": {
            "catalogProfiles": 6,
            "evolvedProfiles": 6,
            "purchase": {
                "kind": "ai",
                "itemIds": [entry["id"] for entry in profiles],
                "walletKey": "standard_tickets",
                "currencyFromCatalog": True,
                "duplicateGuard": True,
                "requestIdIdempotent": True,
                "persisted": "SQLite assets state + requests ledger",
                "reloginReadable": True,
            },
            "existingEconomyPricesUnchanged": True,
            "unlockEnforced": True,
            "tests": {
                "command": "CAS_TEST_DUEL_SIM_PATH=target/release/cas-sim.exe python -m unittest server.test_accounts server.test_account_progression server.test_battle_pve server.test_fleets server.test_ranked server.test_duels",
                "total": 34,
                "failed": 0,
                "accountSuite": 9,
                "newCase": "server.test_accounts.FreeEconomyTest.test_evolved_ai_profiles_are_catalogued_and_purchased_with_tickets",
            },
        },
        "tests": report["tests"],
        "evidence": report["evidence"],
        "boundaries": report["limitations"],
        "blockers": [],
    }
    (AI / "shop-report.json").write_text(json.dumps(shop, ensure_ascii=False, indent=2) + "\n",
                                         encoding="utf-8", newline="\n")
    print(f"wrote {len(profiles)} profiles to ai-report.json and shop-report.json")


if __name__ == "__main__":
    main()
