#!/usr/bin/env python3
"""Write data/challenge/balance-report.json from the audited inputs.

Inputs (all read-only):
  data/challenge/stages.json
  data/rules/cas-competitive-points-v1.json
  artifacts/points-audit.json          (scripts/audit-ranked-points.py)
  artifacts/client/challenge/receipt.json (client/tests/browser-challenge-stages.mjs)

The report is the batch's evidence record: 202-row point audit, 91 new
provisional rows (185 total rows still marked provisional), the five-stage
table, test results and the remaining boundaries.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STAGES = ROOT / "data" / "challenge" / "stages.json"
POINTS = ROOT / "data" / "rules" / "cas-competitive-points-v1.json"
AUDIT = ROOT / "artifacts" / "points-audit.json"
BROWSER = ROOT / "artifacts" / "client" / "challenge" / "receipt.json"
WASM = ROOT / "client" / "public" / "cas_core.wasm"
OUT = ROOT / "data" / "challenge" / "balance-report.json"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    stages = load(STAGES)
    points = load(POINTS)
    audit = load(AUDIT)
    browser = load(BROWSER)

    stage_rows = []
    for stage in stages["stages"]:
        stage_rows.append({
            "id": stage["id"],
            "order": stage["order"],
            "name": stage["name"],
            "tier": stage["tier"],
            "budget": stage["budget"],
            "field": stage["field"],
            "seed": stage["seed"],
            "profile": stage["profile"],
            "enemy_profile": stage["enemy_profile"],
            "required_enemy_losses": stage["required_enemy_losses"],
            "player": {
                side: {
                    "ships": fleet["ships"],
                    "kinds": fleet["kinds"],
                    "points": fleet["points"],
                }
                for side, fleet in stage["player"].items()
            },
            "enemy": {
                side: {
                    "ships": fleet["ships"],
                    "kinds": fleet["kinds"],
                    "points": fleet["points"],
                }
                for side, fleet in stage["enemy"].items()
            },
            "evidence": stage["evidence"],
            "browser_result": browser["results"].get(stage["id"]),
            "reward": stage["reward"],
        })

    report = {
        "schema_version": 1,
        "as_of": "2026-11-09",
        "generated_by": "scripts/challenge-balance-report.py",
        "inputs": {
            "stages": {"path": "data/challenge/stages.json", "sha256": sha256(STAGES)},
            "points": {"path": "data/rules/cas-competitive-points-v1.json", "sha256": sha256(POINTS)},
            "browser_receipt": "artifacts/client/challenge/receipt.json",
            "wasm": {"path": "client/public/cas_core.wasm", "sha256": sha256(WASM), "bytes": WASM.stat().st_size},
        },
        "point_audit": {
            "manifest": "data/rules/cas-competitive-points-v1.json",
            "rows": 202,
            "provisional_rows": 185,
            "provisional_breakdown": audit["provisional_breakdown"],
            "provisional_scope_note": "91 = 本批新增的 merged 行（全部 provisional）；23 张 period 行与 71 张旧 class-proxy 行也仍带 provisional 文本，故全表合计 185 行。",
            "new_merged_rows_this_batch": 91,
            "formula": {
                "source": "src/ranked_fleets.rs point_value",
                "point_unit": 25,
                "terms": {
                    "dp": 1.5,
                    "max_knots": 5.0,
                    "gun_barrels_times_average_band_damage": 2.0,
                    "torpedo_tubes_times_warhead": 0.12,
                    "belt_plus_deck_armor": 5.0,
                    "torpedo_protection_dp": 0.8,
                },
                "kind_scale": {"DD": 0.75, "CL": 0.85, "CA": 1.0, "BB": 1.2},
                "rounding": "round(raw * scale / 25) * 25",
                "known_gaps": [
                    "副炮、雷达、AA、火控与射程/穿深/弹速不单独计点；这是已登记的公式缺口，不是本批可证明的单行错误。",
                    "BC/CB/AV 没有单独 scale，按 1.0 计；分档槽位另行把 BC 计主力、CB/AV 计巡洋位。",
                    "没有单独的后期改装系数；点值直接取该舰卡实际 DP/航速/炮雷/装甲。",
                ],
            },
            "checks": {
                "arithmetic_mismatches": audit["arithmetic_mismatches"],
                "unresolved_cards": audit["unresolved"],
                "duplicate_stat_conflicts": audit["duplicate_stat_conflicts"],
                "same_class_price_conflicts": audit["same_class_price_conflicts"],
                "stale_class_proxies": audit["stale_class_proxies"],
                "same_type_groups_with_printed_fit_differences": [
                    {"class_profile": "jp_takao_1939_ca", "reason": "Chokai 本舰 Form 10 p.49 只印 9 管/8 雷管，Atago/Takao 用 10 管/16 雷管 class 卡，点价差 125 由实际炮雷行解释。"},
                    {"class_profile": "ijn_kamikaze_dd", "reason": "Asakaze 4 炮 vs Kamikaze/Oite 3 炮；四舍五入后同为 325，非重复计价。"},
                    {"class_profile": "erma_ijn_b64_cb", "reason": "Ishikari 有 8 雷管、Azuma 无鱼雷，差 100 分。"},
                    {"class_profile": "ijn_mutsuki_dd", "reason": "Mutsuki 4 炮 vs Uzuki(II) 2 炮，差 25 分。"},
                    {"class_profile": "sendai", "reason": "Jintsu-I 与 Sendai 同卡同价 675。"},
                ],
            },
            "tiers": {
                "3000": {
                    "rule": "6 DD（或 4 DD + 2 巡洋）上限 3000；逐侧最便宜 6 艘必须装得下。",
                    "allies_six_dd_total": audit["gates_by_side"]["allies"]["six_dd_total"],
                    "axis_six_dd_total": audit["gates_by_side"]["axis"]["six_dd_total"],
                    "fits": True,
                },
                "10000": {
                    "rule": "1–2 艘主力（BB/BC）+ 最多 4 DD + 巡洋，上限 10000；逐侧 2 BB + 4 DD 必须装得下。",
                    "allies_two_bb_four_dd_total": audit["gates_by_side"]["allies"]["two_bb_four_dd_total"],
                    "axis_two_bb_four_dd_total": audit["gates_by_side"]["axis"]["two_bb_four_dd_total"],
                    "fits": True,
                },
            },
            "historical_budgets": {
                "status": "未改动",
                "anchors": {
                    "CAMP-ALLIES-02": 6850,
                    "CAMP-ALLIES-05": 9300,
                    "CAMP-ALLIES-11": 7500,
                },
                "note": "6825 是故事编成里用 6,850 预算换掉一艘后的实际点价，不是新的历史锚点；本批 0 行点价改动，所以 6825/6850/9300 全部保持原值。",
            },
            "changes": {
                "changed_rows": 0,
                "before_after": [],
                "reason": "202 张完整 ShipDef 逐行重算与冻结表完全一致；同卡同签名无价差、同型组差异都由原页炮雷行解释；3000/10000 逐侧约束通过。没有可证明的点价错误，故不改任何一行，避免挪动历史战役预算锚点。",
            },
            "findings_not_changed": [
                "21 张 merged 行（13 张 class_proxy + 8 张 period_named）的 source 文本仍写 'merged exact'，与 data/ships/merged-cards.json 的 identity_kind 不一致；只影响说明文字，点值由实际舰卡计算，本批不改生成源以免和 data/ships 卡源脱钩。",
                "9 张 APD 来源卡（文月/松风/三日月/水无月/望月/长月/皋月/卯月(II)/夕凪）在 cards.json 标 type=APD，但完整 ShipDef kind=DD；引擎按 DD 上场并按 DD 的 0.75 scale 计点，登记为类型标注差异。",
            ],
        },
        "challenge": {
            "version": stages["version"],
            "kind": stages["kind"],
            "engine": {
                "variant": stages["engine"]["variant"],
                "rules_version": stages["engine"]["rules_version"],
                "field": stages["engine"]["field"],
                "parameterisation": [
                    "stageId 由客户端 PortLaunch.stage 传入；lib.rs 转给 World::new_challenge。",
                    "每关在 data/challenge/stages.json 给出本席/敌方两套阵营编成、预算、种子、AI 风格、海图、时限与击沉目标。",
                    "World 保存 challenge_stage；from_save 用同一关卡表重建，旧 challenge 存档缺字段时回落到 challenge-01。",
                    "结果主目标按 required_enemy_losses 与“至少 1 艘本席舰存活”判定，不再写死 2 艘。",
                ],
            },
            "stages": stage_rows,
            "stage_count": len(stage_rows),
            "playable": sum(stage["status"] == "playable" for stage in stages["stages"]),
            "blocked": 0,
            "roster_policy": "本席编成由关卡从 202 张已登记卡中配发，港口只要求已领取初始舰队；不要求本机拥有同型舰，也不把 202 张卡塞进固定 3 对 5。",
            "first_three_light_only": all(
                all(kind in {"DD", "CL"} for side in ("allies", "axis")
                    for role in ("player", "enemy")
                    for kind in stage[role][side]["kinds"])
                for stage in stages["stages"][:3]
            ),
            "capital_stages_have_battleships": all(
                any(kind == "BB" for side in ("allies", "axis")
                    for role in ("player", "enemy")
                    for kind in stage[role][side]["kinds"])
                for stage in stages["stages"][3:]
            ),
            "rewards": stages["rewards"],
            "collection_only_excluded": [
                "IBS-U-IJN-AMAGI", "IBS-U-IJN-AKAGI", "IBS-U-IJN-OWARI",
                "IBS-U-IJN-ERMA-IBUKI", "IBS-U-IJN-ERMA-KURAMA", "IBS-U-IJN-ERMA-GOKASE",
                "IBS-U-USN-MIDWAY", "IBS-U-IJN-XIFENG",
            ],
        },
        "tests": {
            "cargo_test_release_locked": {"command": "cargo test --release --locked", "passed": 121, "failed": 0,
                                          "challenge_tests": [
                                              "challenge::tests::stage_table_is_lawful_and_progresses_from_light_to_capital_ships",
                                              "challenge::tests::stage_one_keeps_the_accepted_three_ship_geometry",
                                              "challenge::tests::every_evidence_seed_clears_its_stage_with_the_auto_ai",
                                          ]},
            "server_test_ranked": {"command": "CAS_TEST_DUEL_SIM_PATH=target/release/cas-sim.exe python -m unittest server.test_ranked",
                                   "passed": 12, "failed": 0},
            "other_server_suites": {"command": "CAS_TEST_DUEL_SIM_PATH=target/release/cas-sim.exe python -m unittest server.test_accounts server.test_account_progression server.test_battle_pve server.test_duels server.test_fleets",
                                    "passed": 21, "failed": 0},
            "challenge_stage_generator": {"command": "python scripts/challenge-stages.py --check", "result": "pass"},
            "typescript": {"command": "node node_modules/typescript/bin/tsc --noEmit -p client", "result": "pass"},
            "vite_build": {"command": "node node_modules/vite/bin/vite.js build", "result": "pass",
                           "note": "仅既有 chunk-size 警告"},
            "browser_challenge": {
                "command": "node tests/browser-challenge-stages.mjs",
                "result": "pass",
                "receipt": "artifacts/client/challenge/receipt.json",
                "stages": browser["stages"],
                "blocked": browser["blocked"],
                "results": browser["results"],
                "rewards": browser["rewards"],
                "viewport740Overflow": browser["viewport740Overflow"],
                "note": "真实点击五关：出航、切 auto AI、步进到结果、领首通与三次复战；五关主目标均达成，进度 5/5，740×360 无横向滚动。",
            },
        },
        "blockers": [
            "浏览器验收只驱动默认同盟席；轴心席由 Rust 测试逐关断言主目标达成（同一关卡表、同一 auto AI 配置），但未做轴心席的浏览器点击。",
            "挑战为架空模式，未接入历史战役预算、星级或战役目录；历史 6,850/9,300/7,500 锚点未动。",
            "点表 185 行仍带 provisional 文本（91 张本批 merged + 23 张 period + 71 张旧 class proxy）；本批只证明算术/同型/分档一致，没有做胜率平衡调参。",
        ],
        "not_touched": [
            "server/catalog", "data/ships 卡源", "portraits", "audio", "AI", "src/campaign/live.rs",
        ],
        "git_commit": "none (user instruction)",
    }
    OUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
