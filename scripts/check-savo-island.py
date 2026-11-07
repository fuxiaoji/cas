"""Validate the Savo Island (IBS-S-10) source transcription and period data.

Checks the registered Rising Sun page numbers, the transcribed order of battle on
both sides, the Chinese ship vocabulary, the setup numbers, the historical victory
conditions, and the internal consistency of profiles / weapon shell rows. This is a
source-evidence check: it does not validate any engine wiring.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PERIOD = ROOT / "data" / "campaign" / "period" / "savo-island-1942.json"
RECORD = ROOT / "data" / "campaign" / "savo-island.json"
LABELS = ROOT / "data" / "campaign" / "locale" / "zh-labels.json"

# --- Registered pages (source-crosswalk.md row 10; verified visually 2026-11-07) ---
SCENARIO_PDF_PAGES = [52, 53, 54]
SCENARIO_PRINTED_PAGES = [51, 52, 53]
CHART_PDF_PAGE = 53
CHART_PRINTED_PAGE = 52

# --- Rosters as printed on the scenario pages (PDF 52, printed 51) ---
ALLIED_GROUPS = {
    "TG 62.6 雷达哨舰": ["Blue", "Ralph Talbot"],
    "TG 62.6 南队": ["Australia", "Canberra", "Chicago", "Bagley", "Patterson"],
    "TG 62.6 北队": ["Vincennes", "Quincy", "Astoria", "Helm", "Wilson"],
    "TG 62.4 东屏护": ["San Juan", "Hobart", "Monssen", "Buchanan", "Jarvis"],
    "TG 62.1 X-Ray 屏护": ["Hopkins", "Trever", "Zane", "Southard", "Hovey", "Dewey", "Selfridge", "Mugford"],
    "TG 61.2 Yoke 屏护与分遣": ["Henley", "Ellet", "Hull"],
}
ALLIED_TRANSPORT_DIVISIONS = {
    "TG 62.1 X-Ray 运输": [
        ["Fuller", "American Legion", "Bellatrix"],
        ["McCawley", "Barnett", "George F. Elliott", "Libra"],
        ["Hunter Liggett", "Alchiba", "Betelgeuse", "Formalhaut"],
        ["Crescent City", "President Hayes", "President Adams", "Alhena"],
    ],
    "TG 61.2 Yoke 运输": [
        ["Heywood", "Neville", "Zellin", "President Jackson"],
        ["Colhoun", "Little", "Gregory", "McKean"],
    ],
}
AXIS_GROUPS = {
    "Crudiv 4": ["Chokai"],
    "Crudiv 6": ["Aoba", "Kinugasa", "Furutaka", "Kako"],
    "Crudiv 18": ["Tenryu", "Yubari"],
    "Desdiv 29": ["Yunagi"],
}
AXIS_COLUMN_ORDER = ["Chokai", "Aoba", "Kako", "Kinugasa", "Furutaka", "Tenryu", "Yubari", "Yunagi"]
AXIS_OPTIONAL = ["Tatsuta", "Yuzuki", "Uzuki"]

# --- Setup numbers (PDF 54, printed 53) ---
SETUP_EXPECTATIONS = {
    "allied_patrol_speed_knots": 12,
    "axis_course_deg": 135,
    "axis_speed_knots_start": 28,
    "axis_column_spacing_yd_cruisers": 1300,
    "blue_patrol_course_deg": 235,
}
CHOKAI_BEARING_DEG = 345
CHOKAI_RANGE_KYD = 12

# --- Victory conditions, verbatim from the scenario pages ---
OBJECTIVE_KEYS = [
    ("allies", "orders_verbatim"),
    ("allies", "decisive_verbatim"),
    ("allies", "tactical_verbatim"),
    ("axis", "orders_verbatim"),
    ("axis", "decisive_verbatim"),
    ("axis", "tactical_verbatim"),
]
OBJECTIVE_MIN_LENGTH = 40

# --- Environment (PDF 52, printed 51) ---
ENVIRONMENT_EXPECTATIONS = {
    "light": "night",
    "visibility_pct": 10,
    "overcast_pct": 100,
    "cloud_ceiling_m": 2000,
    "sea_state": 3,
    "civil_twilight_local": "06:11",
    "dawn_local": "06:33",
    "civil_twilight_visibility_pct": 20,
    "dawn_visibility_pct": 50,
}
STORM_RADIUS_NMI = 3

SHELL_ROW_KEYS = {"belt", "deck", "damage_dp"}
SHELL_ROW_LENGTH = 4
DAMAGE_ROW_LENGTH = 6
RANGE_BAND_LENGTH = 4

PROFILES_EXPECTED = {
    "us_new_orleans_ca", "us_northampton_ca", "gb_kent_1939_ca",
    "jp_takao_1939_ca", "jp_aoba_1938_ca", "jp_furutaka_1937_ca",
    "us_atlanta_cl", "gb_perth_cl", "jp_tenryu_cl", "jp_yubari_cl",
    "jp_kamikaze_1941_dd", "us_bagley_dd", "us_gridley_dd", "us_benham_dd",
    "us_benson_dd", "us_bristol_dd", "us_farragut_dd", "us_porter_dd",
    "us_clemson_dms", "us_wickes_apd",
}
# Ships whose profile is deliberately null (optional ships, unfitted conversions).
PROFILES_ALLOWED_NULL = set()


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def strip_legacy_marker(name):
    """zh-labels marks same-name generations with a trailing (I); ignore it."""
    return name.split("(")[0].strip()


def check_registered_pages(period, record):
    assert period["source"]["pdf_pages"] == SCENARIO_PDF_PAGES, "Rising Sun PDF 页码登记不符"
    assert period["source"]["printed_pages"] == SCENARIO_PRINTED_PAGES, "印刷页码登记不符"
    assert record["source"]["pdf_pages"] == SCENARIO_PDF_PAGES, "v1 档案 PDF 页码与登记不一致"
    assert record["source"]["printed_pages"] == SCENARIO_PRINTED_PAGES, "v1 档案印刷页码与登记不一致"
    assert period["start"]["chart_pdf_page"] == CHART_PDF_PAGE
    assert period["start"]["chart_printed_page"] == CHART_PRINTED_PAGE
    assert period["scenario_id"] == record["scenario_id"] == "cas-rs-savo-island"
    assert period["ibs_id"] == record["ibs_id"] == "IBS-S-10"
    assert period["status"] == "source_only_not_runtime_ready"
    assert record["playable"] is False


def check_start(period):
    start = period["start"]
    assert start["local_date"] == "1942-08-09"
    assert start["local_time"] == "00:52"
    assert start["location"] == "Iron Bottom Sound"


def check_environment(period):
    env = period["environment"]
    for key, value in ENVIRONMENT_EXPECTATIONS.items():
        assert env[key] == value, f"environment.{key} 与原页不符"
    assert env["storm"]["radius_nmi_around_savo"] == STORM_RADIUS_NMI
    assert env["storm"]["lightning"] is True
    assert env["moon"] is None, "月光原页未登记，必须保持 null 并挂待裁决"
    assert "月光" in env["moon_note"]
    assert "照明" in env["illumination_orders"]


def check_forces(period):
    groups = {g["unit"]: g for g in period["forces"]["allies"]["groups"]}
    for unit, ships in ALLIED_GROUPS.items():
        assert unit in groups, f"缺少同盟编组 {unit}"
        assert groups[unit]["ships"] == ships, f"{unit} 舰名不符"
    for unit, divisions in ALLIED_TRANSPORT_DIVISIONS.items():
        assert unit in groups, f"缺少运输编组 {unit}"
        got = [d["ships"] for d in groups[unit]["divisions"]]
        assert got == divisions, f"{unit} 运输分队名单不符"
    axis_groups = {g["unit"]: g for g in period["forces"]["axis"]["groups"]}
    for unit, ships in AXIS_GROUPS.items():
        assert unit in axis_groups, f"缺少日军编组 {unit}"
        assert axis_groups[unit]["ships"] == ships, f"{unit} 舰名不符"
    assert period["forces"]["axis"]["column_order_setup"] == AXIS_COLUMN_ORDER
    optional = period["forces"]["axis"]["optional_not_in_base"][0]["ships"]
    assert optional == AXIS_OPTIONAL

    # George F. Elliott must appear exactly once as a fighting unit even though the
    # source prints it in two places (X-Ray TransDiv B and the Yoke detachment note).
    named = []
    for group in period["forces"]["allies"]["groups"]:
        named.extend(group.get("ships", []))
        for division in group.get("divisions", []):
            named.extend(division["ships"])
    assert named.count("George F. Elliott") == 1
    # 2 pickets + 5 southern + 5 northern + 5 eastern + 8 X-Ray screen + 3 Yoke screen
    # + 4 APDs of TransDiv 12 = 32 combat/auxiliary hulls, plus 19 transports.
    apds = ALLIED_TRANSPORT_DIVISIONS["TG 61.2 Yoke 运输"][1]
    assert len(apds) == 4
    expected_hulls = sum(len(ships) for ships in ALLIED_GROUPS.values()) + len(apds)
    expected_transports = len(named) - expected_hulls
    assert len(named) == 51, f"同盟具名舰应为 51 艘（32 舰体 + 19 运输），实得 {len(named)}"
    assert expected_hulls == 32 and expected_transports == 19
    transports = period["auxiliary_transports"]
    assert len(transports["x_ray"]) == 15 and len(transports["yoke"]) == 8
    assert transports["yoke"][4:] == ["Colhoun", "Little", "Gregory", "McKean"]


def check_setup(period):
    setup = period["setup"]
    for key, value in SETUP_EXPECTATIONS.items():
        assert setup[key] == value, f"setup.{key} 与原页不符"
    assert setup["chokai_from_blue"]["bearing_deg"] == CHOKAI_BEARING_DEG
    assert setup["chokai_from_blue"]["range_kyd"] == CHOKAI_RANGE_KYD
    assert setup["axis_speed_history_knots"]["at_0133_all_ships_attack"] == 30
    assert "D6/3" in setup["special_rules_verbatim"]
    assert "Northern and Southern Force and Transport Group Yoke" in setup["special_rules_verbatim"]
    patrol_names = {line["name"] for line in setup["chart_deployment"]["patrol_lines"]}
    assert {"Blue Patrol Line", "Ralph Talbot Patrol Line", "Northern Force Patrol Box",
            "Southern Force Patrol Line", "Australia Patrol Line",
            "Eastern Force Patrol Line"} <= patrol_names
    areas = {area["name"] for area in setup["chart_deployment"]["transport_areas"]}
    assert any("X-Ray" in name for name in areas) and any("Yoke" in name for name in areas)
    assert "DIW" in " ".join(setup["chart_deployment"]["misc_markers"])
    assert setup["chart_deployment"]["silhouette_heading_note"], "剪影航向待裁决说明缺失"


def check_objectives(period):
    objectives = period["objectives"]
    for side, key in OBJECTIVE_KEYS:
        text = objectives[side][key]
        assert isinstance(text, str) and len(text) >= OBJECTIVE_MIN_LENGTH, f"{side}.{key} 非原文照录"
    assert objectives["allies"]["decisive_verbatim"].startswith("The Allied force inflicts damage at a 3:1")
    assert objectives["allies"]["tactical_verbatim"].startswith("The Allied force inflicts 1:1")
    assert objectives["axis"]["decisive_verbatim"].startswith("The Japanese sink or damage more than 75%")
    assert "five transports" in objectives["axis"]["decisive_verbatim"]
    assert objectives["axis"]["tactical_verbatim"].startswith("Japanese inflict a 2:1")
    assert "0600" in objectives["axis"]["orders_verbatim"] and "120 nmi northwest" in objectives["axis"]["orders_verbatim"]


def check_weapon_models(period):
    models = period["weapon_models"]
    assert {"us_8in55_mk9_10_11_13_14", "gb_8in50_mkviii", "jp_3rd_yr_type_no2_20cm50"} <= set(models)
    for name, model in models.items():
        source = model["source"]
        assert source["pdf_page"] and source["printed_page"], f"{name} 缺出处页码"
        if "shells" in model:
            bands = model["range_bands_kyd"]
            assert len(bands) == RANGE_BAND_LENGTH, f"{name} 射距段数应为 4"
            for shell, row in model["shells"].items():
                assert SHELL_ROW_KEYS <= set(row), f"{name}.{shell} 应含 belt/deck/damage_dp"
                for key in SHELL_ROW_KEYS:
                    assert len(row[key]) == SHELL_ROW_LENGTH, f"{name}.{shell}.{key} 行长应为 4"
                assert row["deck"][0] is None and row["deck"][1] is None, f"{name}.{shell} 短/中段甲穿应为 null"
                if "range_bands_kyd" in row:
                    assert len(row["range_bands_kyd"]) == RANGE_BAND_LENGTH
        if "torpedo" in model:
            pairs = model["torpedo"]["range_speed_pairs_yd_knots"]
            assert pairs and all(len(pair) == 2 for pair in pairs)
    # Roadmap cross-check: the 8-inch shell rows must match the verified numbers.
    jp = models["jp_3rd_yr_type_no2_20cm50"]["shells"]["APC"]
    assert jp["belt"] == [34, 23, 16, 12] and jp["damage_dp"] == [26, 20, 17, 15]
    us = models["us_8in55_mk9_10_11_13_14"]["shells"]["APC"]
    assert us["belt"] == [33, 22, 15, 12] and us["damage_dp"] == [23, 18, 15, 13]
    gb = models["gb_8in50_mkviii"]["shells"]["APC"]
    assert gb["belt"] == [33, 22, 15, 12] and gb["damage_dp"] == [26, 20, 17, 15]
    he = models["us_5in38_mk12_mk38"]["shells"]["HE"]
    assert he["damage_dp"][:2] == [18, 15], "5in/38 HE 近/中档伤害应为 18/15（圣乔治角 v2 口径）"
    lance = models["jp_type93_model1_mod1_2_torpedo"]["torpedo"]
    assert lance["range_speed_pairs_yd_knots"] == [[22000, 49], [35000, 41], [43800, 37]]
    assert lance["warhead_kg"] == 490 and lance["damage_dp"] == 95


def check_profiles(period):
    profiles = period["profiles"]
    assert set(profiles) == PROFILES_EXPECTED
    models = period["weapon_models"]
    for name, profile in profiles.items():
        main = profile.get("main_gun")
        assert main is None or main in models, f"{name} 主炮型号未登记弹种行"
        torpedo_model = profile.get("torpedo_model")
        assert torpedo_model is None or torpedo_model in models, f"{name} 雷装型号未登记"
        if profile.get("fit_status") is None and "damage_points" in profile:
            damage = profile["damage_points"]
            speed = profile["speed_knots"]
            assert len(damage) == len(speed) == DAMAGE_ROW_LENGTH, f"{name} 损伤/航速行应为 6 档"
            assert damage[0] == 0 and speed[0] > 0 and speed[-1] == 0
            assert damage == sorted(damage), f"{name} 损伤点应递增"
            assert speed == sorted(speed, reverse=True), f"{name} 航速档应递减"
        if "gb_perth_cl" == name:
            assert len(profile["damage_points_perth"]) == 6
            assert len(profile["damage_points_hobart"]) == 6
    kent = profiles["gb_kent_1939_ca"]
    assert kent["damage_points"] == [0, 83, 167, 250, 300, 333]
    assert "9 Aug 42: Sunk in Battle of Savo Island" in kent["dated_remarks"]["Canberra"][2]
    takao = profiles["jp_takao_1939_ca"]
    assert takao["damage_points"] == [0, 100, 201, 301, 361, 401]
    assert takao["torpedo_model"] == "jp_type93_model1_mod1_2_torpedo"
    assert "Forward 20cm turret damaged" in takao["chokai_dated_remarks"][1]
    assert profiles["jp_kamikaze_1941_dd"]["torpedo_model"] is None
    assert "Type 96" in profiles["jp_kamikaze_1941_dd"]["torpedo_conflict"]
    assert profiles["us_clemson_dms"]["fit_status"] == "未核"
    assert profiles["us_wickes_apd"]["fit_status"] == "未核"


def check_instances(period, labels):
    instances = period["instances"]
    ships = labels["ships"]
    side_of = {}
    for side, table in ships.items():
        for key in table:
            side_of[strip_legacy_marker(key)] = (side, table[key])
    seen = set()
    for ship_id, ship in instances.items():
        assert ship_id.startswith("savo-"), f"实例 ID 应以 savo- 开头：{ship_id}"
        assert ship_id not in seen, f"实例 ID 重复：{ship_id}"
        seen.add(ship_id)
        profile = ship["profile"]
        if profile is None:
            assert ship_id in PROFILES_ALLOWED_NULL, f"{ship_id} 无 profile 且未列入允许名单"
        else:
            assert profile in period["profiles"], f"{ship_id} 引用了不存在的 profile {profile}"
        en = ship["name_en"]
        if en in AXIS_OPTIONAL:
            continue
        assert en in side_of, f"{en} 不在 zh-labels 词表内"
        side, zh = side_of[en]
        assert ship["side"] == side, f"{en} 阵营与词表不符"
        expected = strip_legacy_marker(zh)
        assert ship["name_zh"] == expected, f"{en} 中文名 {ship['name_zh']} 应为 {expected}"
        form10 = ship.get("form10")
        if form10 is None:
            assert ship.get("fit_status") == "未核", f"{en} 既无 Form 10 引用也未标未核"
        else:
            assert "document" in form10, f"{en} 缺 Form 10 引用字段"
            if form10.get("status") != "未核" or form10.get("pdf_page") is not None:
                assert form10.get("document") == "rising_sun_form10"
    assert {"savo-chokai", "savo-blue", "savo-ralph-talbot", "savo-canberra",
            "savo-henley", "savo-yunagi"} <= set(instances)
    assert instances["savo-canberra"]["radar_confirmed"] == []
    assert instances["savo-vincennes"]["radar_confirmed"] == ["us_sc", "us_mk3"]
    assert instances["savo-henley"]["profile_conflict"], "Henley 级属冲突必须显式登记"
    flag_chokai = instances["savo-chokai"]["flag"] is True
    flag_sanjuan = instances["savo-san-juan"]["flag"] is True
    assert flag_chokai and flag_sanjuan, "双方旗舰标记缺失"


def check_conflicts_and_pending(period):
    conflicts = period["conflicts"]
    ids = {c["id"] for c in conflicts}
    assert {"henley-class-label", "yunagi-torpedo-type96", "george-f-elliott-duplicate",
            "northampton-fit-drift"} <= ids
    unresolved = [c for c in conflicts if c["status"] == "unresolved"]
    assert unresolved, "应保留至少一条 unresolved 冲突"
    pending = period["pending_adjudication"]
    assert len(pending) >= 10
    joined = "\n".join(pending)
    for keyword in ("月光", "照明", "待裁决"):
        assert keyword in joined or any(keyword in str(c) for c in conflicts), f"待裁决清单缺少「{keyword}」"


def main():
    period = load(PERIOD)
    record = load(RECORD)
    labels = load(LABELS)

    check_registered_pages(period, record)
    check_start(period)
    check_environment(period)
    check_forces(period)
    check_setup(period)
    check_objectives(period)
    check_weapon_models(period)
    check_profiles(period)
    check_instances(period, labels)
    check_conflicts_and_pending(period)

    warships = len(period["instances"])
    auxiliaries = len(period["auxiliary_transports"]["x_ray"]) + len(period["auxiliary_transports"]["yoke"])
    print(f"savo-island-1942.json OK: pages {SCENARIO_PDF_PAGES} (printed {SCENARIO_PRINTED_PAGES}), "
          f"{len(ALLIED_GROUPS)} allied screen groups + 2 transport groups, "
          f"{len(AXIS_GROUPS)} axis groups, {warships} named instances, {auxiliaries} auxiliary hulls, "
          f"{len(period['profiles'])} profiles, {len(period['weapon_models'])} weapon models, "
          f"{len(period['conflicts'])} conflicts, {len(period['pending_adjudication'])} pending items")
    return 0


if __name__ == "__main__":
    sys.exit(main())
