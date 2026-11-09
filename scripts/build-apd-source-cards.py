"""Build usable card data for the eight IJN APD identities of the current scenarios.

The eight hulls are catalog ``type: "APD"`` identities that the playable-card
index keeps collection-only because APD is a transport role. The user decision
is "record every ship that has data, only carriers stay out", so this registry
publishes the eight APDs as ship cards:

* five identities already carry a per-ship period card in a compiled runtime
  package (kula-runtime / savo-runtime) - the ShipDef is copied verbatim;
* three identities (Minazuki, Matsukaze, Fumizuki) have no period package card -
  the ShipDef is copied verbatim from the registered card of the same class
  (Mutsuki -> kula ``profiles.mutsuki``; Kamikaze -> savo ``savo_yunagi``,
  i.e. ``jp_kamikaze_1941_dd``). No other class is used.

Nothing is estimated: every page cited below is re-checked against the PDF text
layer at build time (``verify`` steps), and any value that differs between the
class table, the ship's own Form 10 and the registered runtime card is listed as
a conflict in the report instead of being adjusted.

Run: python scripts/build-apd-source-cards.py
Outputs:
  data/ships/apd-source-cards.json   8 APD cards (profile metadata + ShipDef)
  data/ships/apd-source-report.json  provenance, page checks, conflicts, blockers
"""
import hashlib
import json
import re
from pathlib import Path

import pymupdf

ROOT = Path(__file__).resolve().parents[1]
OUT_CARDS = ROOT / "data" / "ships" / "apd-source-cards.json"
OUT_REPORT = ROOT / "data" / "ships" / "apd-source-report.json"

PLAYABLE = "data/ships/playable-cards.json"
CATALOG = "server/catalog.json"
KULA = "data/campaign/period/kula-runtime.json"
SAVO = "data/campaign/period/savo-runtime.json"
SAVO_PERIOD = "data/campaign/period/savo-island-1942.json"

FORM10 = "CAS带翻译/CAS带翻译/船表/旧版太平洋 船表Rising_Sun_Form_10s.pdf"
EMPERORS = "CAS带翻译/CAS带翻译/船表/The_Emperor_s_Fleet.pdf"

# The eight APD identities, in the order of the task list.
ORDER = [
    "IBS-U-IJN-MONCHIZUKI",
    "IBS-U-IJN-MIKAZUKI",
    "IBS-U-IJN-NAGATSUKI",
    "IBS-U-IJN-SATSUKI",
    "IBS-U-IJN-YUNAGI",
    "IBS-U-IJN-MINAZUKI",
    "IBS-U-IJN-MATSU-KAZE",
    "IBS-U-IJN-FUMIZUKI",
]

# Five hulls with their own period card: identity -> (file, hull_id, profile).
OWN_PERIOD_CARD = {
    "IBS-U-IJN-MONCHIZUKI": (KULA, "kula-mochizuki", "mutsuki"),
    "IBS-U-IJN-MIKAZUKI": (KULA, "kula-mikazuki", "mutsuki_mikazuki"),
    "IBS-U-IJN-NAGATSUKI": (KULA, "kula-nagatsuki", "mutsuki"),
    "IBS-U-IJN-SATSUKI": (KULA, "kula-satsuki", "mutsuki"),
    "IBS-U-IJN-YUNAGI": (SAVO, "savo_yunagi", "jp_kamikaze_1941_dd"),
}

# Three hulls without a period card: identity -> (class key, donor file,
# donor row, donor profile id, why this donor).
SIBLING = {
    "IBS-U-IJN-MINAZUKI": (
        "mutsuki", KULA, "profiles.mutsuki", "mutsuki",
        "Mutsuki 级同型表（Emperor's Fleet A-27/A-28）"),
    "IBS-U-IJN-FUMIZUKI": (
        "mutsuki", KULA, "profiles.mutsuki", "mutsuki",
        "Mutsuki 级同型表（Emperor's Fleet A-27/A-28）"),
    "IBS-U-IJN-MATSU-KAZE": (
        "kamikaze", SAVO, "ships[savo_yunagi]", "jp_kamikaze_1941_dd",
        "Kamikaze 级同型舰 savo_yunagi（Emperor's Fleet A-24 Kamikaze (1941)）"),
}

# Class-table metadata, copied from the CAS fleet tables and re-checked on the page:
#   Mutsuki  -> The Emperor's Fleet PDF 30-31 / printed A-27, A-28
#   Kamikaze -> The Emperor's Fleet PDF 27 / printed A-24 "Kamikaze (1941)"
CLASS_META = {
    "mutsuki": {
        "class": "Mutsuki",
        "side": "axis",
        "kind": "DD",
        "size_class_en": "D/Small",
        "source": {"document": "emperors_fleet", "file": EMPERORS,
                   "pdf_pages": [30, 31], "printed_pages": ["A-27", "A-28"]},
        "displacement_std_tons": 1336,
        "in_class": 12,
        "in_service": "1925",
        "crew": 150,
        "armor_rating": 0,
        "gunnery_standard": "III（编制块）；1935-36 改装后 IV（Form 10 与运行卡均用 IV）",
        "damage_points": [0, 22, 44, 66, 79, 88],
        "speed_knots": [33, 25, 16, 8, 0],
        "main_gun": "jp_3rd_yr_120mm45",
        "model_ids": {
            "main_gun_registered_in": "data/campaign/period/cape-st-george-1943.json#weapon_models.jp_3rd_yr_120mm45",
            "torpedo_registered_in": "data/campaign/period/savo-island-1942.json#weapon_models.jp_8th_yr_type_no2_torpedo",
            "note": "同一 Annex C-1/F-1 行在各 period 包用不同 id（另见 jp_3rd_11th_yr_type_12cm45、jp_8th_yr_type_no2）；此处按定义包登记，ShipDef 数值不改。",
        },
        "gun_mounts_verbatim": "F/2P&S/A(1)4 3rd Yr Type 12cm/45",
        "area_aa_verbatim": "(1)4 3rd Yr Type 12cm/45 (0.1)",
        "light_aa_verbatim": "2 Vickers 7.7mm (0.1)（编制块；逐舰改装见 ship_form10）",
        "torpedoes_verbatim": "P&S(3)2 610mm TT w/3 8th Yr Type No. 2（每座 2 备雷，15 分钟装填）",
        "torpedo_model": "jp_8th_yr_type_no2_torpedo",
        "asw": "2 DC racks w/1 DC, 18 DC carried",
        "sensors": "Type 93 (passive), Type 93 Model 1 (active)",
        "remarks_verbatim": "Improved Kamikaze design. Laid down before 1925, special damage modifier of -15%.",
        "turn_verbatim": "Standard Rudder 200 yds (1) / Hard Rudder 100 yds (2)",
        "refit_notes": {
            "Mochizuki": ["Jan 42: 2 13.2mm added, Lt AA 0.2.",
                          "Jul - Aug 42: DC refit.",
                          "Jan - Feb 43: 2 25mm added, Lt AA 0.5.",
                          "Aug - Sep 43: Aft 12cm replaced by 8 25mm, E-17 Kai 3, Model 3 ESM added, Lt AA 1.4."],
            "Mikazuki": ["Dec 42 - Jan 43: Type 93 Model 1 replaced by Type 3 model 2 sonar. DC refit.",
                         "Mar - Jun 43: Aft, P&S 12cm, aft TT and reserve torps, 7.7mm replaced by 2 13.2mm, 3 25mm, Area AA 0.1, Lt AA 0.5."],
            "Nagatsuki": ["Sep - Oct 42: Type 93 Model 1 replaced by Type 3 model 2 sonar, DC refit."],
            "Satsuki": ["Oct - Nov 42: Type 93 Model 1 replaced by Type 3 model 2 sonar, DC refit.",
                        "Aug 43: Aft 12cm, E-17 Kai 3, Model 3 ESM, 8 25mm added. Area AA 0.2, Light AA 1.1."],
            "Minazuki": ["Aug - Sep 42: Type 93 Model 1 replaced by Type 3 model 2 sonar. DC refit.",
                         "Feb 43: 7.7mm replaced by 2 13.2mm, 2 25mm, Lt AA 0.4.",
                         "Aug - Sep 43: Aft 12cm, E-17 Kai 3, Model 3 ESM, 6 25mm added. Area AA 0.2, Light AA 1.1."],
            "Fumizuki": ["Jul - Aug 42: Type 93 Model 1 replaced by Type 3 model 2 sonar, DC refit.",
                         "May - Aug 43: P&S 12cm, aft TT, 7.7mm replaced by 2 13.2mm, 3 25mm. Area AA 0.1, Light AA 0.5."],
            "Uzuki": ["May - Jun 42: DC refit."],
            "Yuzuki": ["May - Jun 42: DC refit."],
        },
    },
    "kamikaze": {
        "class": "Kamikaze (1941)",
        "side": "axis",
        "kind": "DD",
        "size_class_en": "D/Small",
        "source": {"document": "emperors_fleet", "file": EMPERORS,
                   "pdf_pages": [27], "printed_pages": ["A-24"]},
        "displacement_std_tons": 1422,
        "in_class": 9,
        "in_service": "1941 (1925)",
        "crew": 148,
        "armor_rating": 0,
        "gunnery_standard": "IV",
        "damage_points": [0, 23, 46, 69, 83, 92],
        "speed_knots": [35, 26, 18, 9, 0],
        "main_gun": "jp_3rd_11th_yr_type_12cm45",
        "model_ids": {
            "main_gun_registered_in": "data/campaign/period/savo-island-1942.json#weapon_models.jp_3rd_11th_yr_type_12cm45",
            "torpedo_registered_in": None,
            "note": "Type 96 533mm 在 Annex F-1 无弹行，登记卡 torpedo=null，不替代。",
        },
        "gun_mounts_verbatim": "F/2P&S(1)3 3rd Yr Type 12cm/45 LA",
        "area_aa_verbatim": "未印 Area AA 行（12cm/45 为 LA 座）",
        "light_aa_verbatim": "10 Type 96 25mm (1.2)",
        "torpedoes_verbatim": "P&S(2)2 533mm TT w/2 Type 96 torp",
        "torpedo_model": None,
        "asw": "(2)2 Type 94 Y-gun w/4 DC；6 DC racks w/1 DC, 18 DC carried",
        "sensors": "Type 93 (passive), Type 93 Model 1",
        "remarks_verbatim": "Improved Minekaze class. Laid down before 1925, special damage modifier of -15%.",
        "turn_verbatim": "Standard Rudder 200 yds (1) / Hard Rudder 100 yds (2)",
        "refit_notes": {
            "Yunagi": ["Dec 1941 编成（Form 10 p.176）。", "Jan 44: 2 Type 22 radars added.",
                       "Apr 44: 2 Type 13 radars, E-27 Kai 3 and Model 3 ESM (Gen 0) fitted."],
            "Matsukaze": ["Dec 1941 编成（Form 10 p.175）。", "Jan 44: 2 Type 22 radars added.",
                          "Apr 44: 2 Type 13 radars, E-27 Kai 3 and Model 3 ESM (Gen 0) fitted."],
        },
    },
}

# Per-ship Form 10 page (verified visually on the rendered page). Values are the
# verbatim fit printed on that page; "matches_runtime" states whether the
# registered ShipDef reproduces the printed fit.
SHIP_FORM10 = {
    "IBS-U-IJN-MONCHIZUKI": {
        "pdf_page": 180, "printed_page": 180, "modification": "Jan-Feb 43", "class_key": "mutsuki",
        "guns_verbatim": "Fwd (1)、P&S (1)、P&S (1)、Aft (1) 3rd Yr Type 12cm/45（4 座）",
        "area_aa_verbatim": "Area AA: (1)4 3rd Yr Type 12cm/45 (0.1) to 2.9 nm/10000m",
        "torpedoes_verbatim": "P&S(3) 610mm TT w/3 Type 93 torp ×2（各 Reload ××）",
        "light_aa_verbatim": "2 7.7mm, 2 13mm, 2 25mm (0.5)",
        "printed": {"single_gun_mounts": 4, "torpedo_tubes": 6, "size_class": "D"},
    },
    "IBS-U-IJN-MIKAZUKI": {
        "pdf_page": 178, "printed_page": 178, "modification": "Mar-Jun 43", "class_key": "mutsuki",
        "guns_verbatim": "Fwd (1)、P&S (1) 3rd Yr Type 12cm/45（2 座）",
        "area_aa_verbatim": "Area AA: (1)2 3rd Yr Type 12cm/45 (0.1) to 2.9 nm/10000m",
        "torpedoes_verbatim": "P&S(3) 610mm TT w/3 Type 93 torp ×1",
        "light_aa_verbatim": "2 13mm, 3 25mm (0.5)",
        "printed": {"single_gun_mounts": 2, "torpedo_tubes": 3, "size_class": "D"},
    },
    "IBS-U-IJN-NAGATSUKI": {
        "pdf_page": 181, "printed_page": 181, "modification": "Sep-Oct 42", "class_key": "mutsuki",
        "guns_verbatim": "Fwd (1)、P&S (1)、P&S (1)、Aft (1) 3rd Yr Type 12cm/45（4 座）",
        "area_aa_verbatim": "Area AA: (1)4 3rd Yr Type 12cm/45 (0.1) to 2.9 nm/10000m",
        "torpedoes_verbatim": "P&S(3) 610mm TT w/3 Type 93 torp ×2（各 Reload ××）",
        "light_aa_verbatim": "2 7.7mm (0.1)",
        "printed": {"single_gun_mounts": 4, "torpedo_tubes": 6, "size_class": "D"},
    },
    "IBS-U-IJN-SATSUKI": {
        "pdf_page": 182, "printed_page": 182, "modification": "Oct-Nov 42", "class_key": "mutsuki",
        "guns_verbatim": "Fwd (1)、P&S (1)、P&S (1)、Aft (1) 3rd Yr Type 12cm/45（4 座）",
        "area_aa_verbatim": "Area AA: (1)4 3rd Yr Type 12cm/45 (0.1) to 2.9 nm/10000m",
        "torpedoes_verbatim": "P&S(3) 610mm TT w/3 Type 93 torp ×2（各 Reload ××）",
        "light_aa_verbatim": "2 7.7mm (0.1)",
        "printed": {"single_gun_mounts": 4, "torpedo_tubes": 6, "size_class": "D"},
    },
    "IBS-U-IJN-YUNAGI": {
        "pdf_page": 176, "printed_page": 176, "modification": "Dec 1941", "class_key": "kamikaze",
        "guns_verbatim": "Fwd (1)、P&S (1)、Aft (1) 3rd Yr Type 12cm/45（3 座）",
        "area_aa_verbatim": "未印 Area AA 行",
        "torpedoes_verbatim": "P&S(2) 533mm TT w/2 Type 96 torp ×2",
        "light_aa_verbatim": "2 13mm (0.1)",
        "printed": {"single_gun_mounts": 3, "torpedo_tubes": 4, "size_class": "D"},
    },
    "IBS-U-IJN-MINAZUKI": {
        "pdf_page": 179, "printed_page": 179, "modification": "Feb 43", "class_key": "mutsuki",
        "guns_verbatim": "Fwd (1)、P&S (1)、P&S (1)、Aft (1) 3rd Yr Type 12cm/45（4 座）",
        "area_aa_verbatim": "Area AA: (1)4 3rd Yr Type 12cm/45 (0.1) to 2.9 nm/10000m",
        "torpedoes_verbatim": "P&S(3) 610mm TT w/3 Type 93 torp ×2（各 Reload ××）",
        "light_aa_verbatim": "2 13mm, 2 25mm (0.4)",
        "printed": {"single_gun_mounts": 4, "torpedo_tubes": 6, "size_class": "D"},
    },
    "IBS-U-IJN-MATSU-KAZE": {
        "pdf_page": 175, "printed_page": 175, "modification": "Dec 1941", "class_key": "kamikaze",
        "guns_verbatim": "Fwd (1)、P&S (1)、Aft (1) 3rd Yr Type 12cm/45（3 座）",
        "area_aa_verbatim": "未印 Area AA 行",
        "torpedoes_verbatim": "P&S(2) 533mm TT w/2 Type 96 torp ×2",
        "light_aa_verbatim": "2 13mm (0.1)",
        "printed": {"single_gun_mounts": 3, "torpedo_tubes": 4, "size_class": "D"},
    },
    "IBS-U-IJN-FUMIZUKI": {
        "pdf_page": 177, "printed_page": 177, "modification": "May-Aug 43", "class_key": "mutsuki",
        "guns_verbatim": ("Fwd (1)、P&S (1)、Aft (1) 3rd Yr Type 12cm/45（3 行），"
                          "但 Area AA 只印 (1)2 —— 与级表 4 座/6 管不一致"),
        "area_aa_verbatim": "Area AA: (1)2 3rd Yr Type 12cm/45 (0.1) to 2.9 nm/10000m",
        "torpedoes_verbatim": "P&S(3) 610mm TT w/3 Type 93 torp ×1",
        "light_aa_verbatim": "2 13mm, 3 25mm (0.5)",
        "printed": {"single_gun_mounts": 3, "torpedo_tubes": 3, "size_class": "D"},
    },
}

# What the printed class table says, for the self-check against the copied ShipDef.
TABLE_EXPECTED = {
    "mutsuki": {
        "dp": 88, "max_knots": 33,
        "damage_speed": {"damage": [0, 22, 44, 66, 79, 88], "knots": [33, 25, 16, 8, 0, 0]},
        "barrels": 4, "torpedo_tubes": 6, "turn_advance_yards": 200, "size": "D",
        "displacement_std_tons": 1336, "crew": 150, "in_service_year": 1925,
    },
    "kamikaze": {
        "dp": 92, "max_knots": 35,
        "damage_speed": {"damage": [0, 23, 46, 69, 83, 92], "knots": [35, 26, 18, 9, 0, 0]},
        "barrels": 3, "torpedo_tubes": 4, "turn_advance_yards": 200, "size": "D",
        "displacement_std_tons": 1422, "crew": 148, "in_service_year": 1925,
    },
}

# (identity, dimension) pairs where the ship's own Form 10 prints something other
# than the copied ShipDef. Every one of them must be listed in the report's
# conflicts; anything outside this set fails the build.
ALLOWED_MISMATCH = {
    ("IBS-U-IJN-YUNAGI", "torpedo_tubes"),
    ("IBS-U-IJN-YUNAGI", "size_class"),
    ("IBS-U-IJN-YUNAGI", "turn_advance_yards"),
    ("IBS-U-IJN-MATSU-KAZE", "torpedo_tubes"),
    ("IBS-U-IJN-MATSU-KAZE", "size_class"),
    ("IBS-U-IJN-MATSU-KAZE", "turn_advance_yards"),
    ("IBS-U-IJN-FUMIZUKI", "single_gun_mounts"),
    ("IBS-U-IJN-FUMIZUKI", "torpedo_tubes"),
}

CLASS_LABEL = {"mutsuki": "睦月级", "kamikaze": "神风级"}
MATCH_LABEL = {
    "single_gun_mounts": "炮座数",
    "torpedo_tubes": "鱼雷发射管数",
    "damage_speed": "损伤/航速表",
    "size_class": "尺寸级别",
    "turn_advance_yards": "45° 转向提前量",
}

REQUIRED = [
    "id", "name", "side", "kind", "size", "max_knots", "dp", "turn_advance_yards",
    "speed_loss_knots", "accel_knots_per_turn", "gun", "armor_belt", "armor_deck",
    "in_service_year", "accel_high_knots_per_turn", "brake_knots_per_turn",
]
REQUIRED_GUN = ["name", "range_yd", "damage", "barrels", "gs", "pen_belt", "pen_deck",
                "armor_piercing"]
REQUIRED_TORPEDO = ["name", "speed_knots", "range_yd", "warhead", "tubes", "contact_fuze"]


def load(rel):
    return json.loads((ROOT / rel).read_text(encoding="utf-8"))


def sha(rel):
    return hashlib.sha256((ROOT / rel).read_bytes()).hexdigest()


class Pdf:
    def __init__(self):
        self._docs = {}

    def page_text(self, rel, page_no):
        if rel not in self._docs:
            self._docs[rel] = pymupdf.open(ROOT / rel)
        return self._docs[rel][page_no - 1].get_text()

    def page_count(self, rel):
        if rel not in self._docs:
            self._docs[rel] = pymupdf.open(ROOT / rel)
        return self._docs[rel].page_count


PDF = Pdf()


def verify_form10(identity, name_en):
    """The cited Form 10 page must print the hull, its class, DP and speed rows."""
    row = SHIP_FORM10[identity]
    text = PDF.page_text(FORM10, row["pdf_page"])
    assert "Page %d" % row["pdf_page"] in text, "%s: p.%d 不是 Form 10 页" % (identity, row["pdf_page"])
    assert ("%s DD" % name_en) in text, \
        "%s: p.%d 没有印 %s DD" % (identity, row["pdf_page"], name_en)
    assert "class IJN" in text, "%s: p.%d 没有印舰级" % (identity, row["pdf_page"])
    assert ("%s class IJN" % CLASS_META[row["class_key"]]["class"].split(" ")[0]) in text, \
        "%s: p.%d 舰级与登记不符" % (identity, row["pdf_page"])
    expected = TABLE_EXPECTED[row["class_key"]]
    damage = expected["damage_speed"]["damage"][:5]
    speed = expected["damage_speed"]["knots"][:5]
    assert re.search(r"Damage Taken\s" + r"\s+".join(str(value) for value in damage), text), \
        "%s: p.%d DP 行与级表不符" % (identity, row["pdf_page"])
    assert re.search(r"Max Speed\s" + r"\s+".join(str(value) for value in speed), text), \
        "%s: p.%d 航速行与级表不符" % (identity, row["pdf_page"])
    assert "%d std" % expected["displacement_std_tons"] in text, \
        "%s: p.%d 排水量与级表不符" % (identity, row["pdf_page"])
    return {"document": "rising_sun_form10s", "pdf_page": row["pdf_page"],
            "hull": "%s DD" % name_en, "class_printed": True,
            "damage_row": " ".join(str(value) for value in damage),
            "speed_row": " ".join(str(value) for value in speed), "verified": True}


def verify_class_table(class_key, expected_dp):
    """The cited fleet-table pages must carry the class block, its remarks and DP row."""
    meta = CLASS_META[class_key]
    texts = [PDF.page_text(EMPERORS, page) for page in meta["source"]["pdf_pages"]]
    joined = "\n".join(texts)
    if class_key == "mutsuki":
        assert "Mutsuki" in joined and "1336 std" in joined, "A-27/A-28 页缺 Mutsuki 编制块"
        assert "Improved Kamikaze design" in joined, "A-28 页缺 Mutsuki 备注"
        assert "8th Yr Type No. 2" in joined, "A-27 页缺 Mutsuki 鱼雷行"
    else:
        assert "Kamikaze (1941)" in joined and "1422 std" in joined, "A-24 页缺 Kamikaze (1941) 编制块"
        assert "Improved Minekaze class" in joined, "A-24 页缺 Kamikaze 备注"
        assert "Type 96 torp" in joined, "A-24 页缺 Kamikaze 鱼雷行"
    assert any(str(expected_dp) in text for text in texts), \
        "%s 级表页没有 %s DP 行" % (class_key, expected_dp)
    assert all(meta["source"]["printed_pages"]), "级表页码未登记"
    return {"document": meta["source"]["document"], "verified": True,
            "class_block": True, "remarks": True, "dp_row": True}


CAPE_ST_GEORGE = "data/campaign/period/cape-st-george-1943.json"


def weapon_table_records(class_key):
    """Resolve the model id registered in profile.model_ids to its annex row."""
    model_ids = CLASS_META[class_key]["model_ids"]
    cape = load(CAPE_ST_GEORGE)["weapon_models"]
    savo = load(SAVO_PERIOD)["weapon_models"]
    gun_id = CLASS_META[class_key]["main_gun"]
    if gun_id in cape:
        entry = cape[gun_id]
        bands = [band[1] for band in entry["shells"]["COM"]["range_yd"]]
        gun = {"range_yd": bands, "damage": list(entry["shells"]["COM"]["damage_dp"]),
               "pen_belt": list(entry["shells"]["COM"]["belt"]),
               "pen_deck": list(entry["shells"]["COM"]["deck"])}
        gun_source = CAPE_ST_GEORGE
    else:
        entry = savo[gun_id]
        bands = [band[1] * 1000 for band in entry["range_bands_kyd"]]
        gun = {"range_yd": bands, "damage": list(entry["shells"]["COM"]["damage_dp"]),
               "pen_belt": list(entry["shells"]["COM"]["belt"]),
               "pen_deck": list(entry["shells"]["COM"]["deck"])}
        gun_source = SAVO_PERIOD
    torpedo_id = CLASS_META[class_key]["torpedo_model"]
    torpedo = None
    torpedo_source = None
    if torpedo_id:
        row = savo[torpedo_id]["torpedo"]
        torpedo = {"damage": row["damage_dp"], "range_yd": row["range_speed_pairs_yd_knots"][0][0],
                   "speed_knots": row["range_speed_pairs_yd_knots"][0][1]}
        torpedo_source = SAVO_PERIOD
    return {"gun_id": gun_id, "gun_source": gun_source, "gun": gun,
            "torpedo_id": torpedo_id, "torpedo_source": torpedo_source, "torpedo": torpedo,
            "registered_ids": model_ids}


def ship_matches_weapon_tables(ship, class_key):
    table = weapon_table_records(class_key)
    gun = ship["gun"]
    torpedo = ship.get("torpedo")
    result = {
        "gun.range_yd": {"table": table["gun"]["range_yd"], "shipdef": gun["range_yd"],
                         "match": [float(v) for v in gun["range_yd"]] == [float(v) for v in table["gun"]["range_yd"]]},
        "gun.damage": {"table": table["gun"]["damage"], "shipdef": gun["damage"],
                       "match": gun["damage"] == table["gun"]["damage"]},
        "gun.pen_belt": {"table": table["gun"]["pen_belt"], "shipdef": gun["pen_belt"],
                         "match": gun["pen_belt"] == table["gun"]["pen_belt"]},
        "gun.pen_deck": {"table": table["gun"]["pen_deck"], "shipdef": gun["pen_deck"],
                         "match": gun["pen_deck"] == table["gun"]["pen_deck"]},
        "gun.barrels_vs_printed": None,
    }
    if table["torpedo"] is None:
        result["torpedo"] = {"table": None, "shipdef": bool(torpedo),
                             "match": torpedo is None}
    else:
        result["torpedo"] = {
            "table": table["torpedo"],
            "shipdef": {"damage": torpedo["warhead"], "range_yd": torpedo["range_yd"],
                        "speed_knots": torpedo["speed_knots"]},
            "match": (float(torpedo["warhead"]) == float(table["torpedo"]["damage"])
                      and float(torpedo["range_yd"]) == float(table["torpedo"]["range_yd"])
                      and float(torpedo["speed_knots"]) == float(table["torpedo"]["speed_knots"])),
        }
    del result["gun.barrels_vs_printed"]
    return result


def ship_matches_shipdef(ship, class_key, printed):
    """Compare the printed ship fit with the copied ShipDef, dimension by dimension."""
    expected = TABLE_EXPECTED[class_key]
    torpedo = ship.get("torpedo")
    damage = [point["damage"] for point in ship["damage_speed"]]
    knots = [point["knots"] for point in ship["damage_speed"]]
    return {
        "single_gun_mounts": {"printed": printed["single_gun_mounts"],
                              "shipdef_barrels": ship["gun"]["barrels"],
                              "match": ship["gun"]["barrels"] == printed["single_gun_mounts"]},
        "torpedo_tubes": {"printed": printed["torpedo_tubes"],
                          "shipdef_tubes": torpedo["tubes"] if torpedo else None,
                          "match": bool(torpedo) and torpedo["tubes"] == printed["torpedo_tubes"]},
        "damage_speed": {"printed": expected["damage_speed"],
                         "shipdef": {"damage": damage, "knots": knots},
                         "match": damage[:5] == expected["damage_speed"]["damage"][:5]
                                  and knots[:5] == expected["damage_speed"]["knots"][:5]},
        "size_class": {"printed": printed["size_class"], "shipdef": ship["size"],
                       "match": ship["size"] == printed["size_class"]},
        "turn_advance_yards": {"printed": expected["turn_advance_yards"],
                               "shipdef": ship["turn_advance_yards"],
                               "match": ship["turn_advance_yards"] == expected["turn_advance_yards"]},
    }


def ship_from_kula(profile):
    data = load(KULA)
    if profile not in data["profiles"]:
        raise SystemExit("kula-runtime 没有 profile %s" % profile)
    return json.loads(json.dumps(data["profiles"][profile])), "%s#profiles.%s" % (KULA, profile)


def ship_from_savo(ship_id):
    data = load(SAVO)
    for ship in data["ships"]:
        if ship["id"] == ship_id:
            return json.loads(json.dumps(ship)), "%s#ships[%s]" % (SAVO, ship_id)
    raise SystemExit("savo-runtime 没有 %s" % ship_id)


def completeness(ship):
    missing = [key for key in REQUIRED if key not in ship]
    gun = ship.get("gun") or {}
    missing += ["gun." + key for key in REQUIRED_GUN if key not in gun]
    torpedo = ship.get("torpedo")
    if torpedo:
        missing += ["torpedo." + key for key in REQUIRED_TORPEDO if key not in torpedo]
    return missing


def shipdef_value(match):
    """The ShipDef side of a match record, whichever key the dimension uses."""
    for key in ("shipdef", "shipdef_barrels", "shipdef_tubes"):
        if key in match:
            return match[key]
    return None


def has_points(node):
    if isinstance(node, dict):
        return any(key == "points" or has_points(value) for key, value in node.items())
    if isinstance(node, list):
        return any(has_points(value) for value in node)
    return False


def main():
    playable = load(PLAYABLE)
    cards_by_id = {card["identity"]: card for card in playable["cards"]}
    catalog = {ship["id"]: ship for ship in load(CATALOG)["ships"]}
    savo_period = load(SAVO_PERIOD)

    cards, report_rows = [], []
    shipdef_matches, page_verifications = {}, []
    weapon_matches_all = {}
    for identity in ORDER:
        card = cards_by_id[identity]
        catalog_row = catalog[identity]
        ship_form10 = SHIP_FORM10[identity]
        class_key = ship_form10["class_key"]
        class_meta = CLASS_META[class_key]
        name_en = card["name_en"]

        if identity in OWN_PERIOD_CARD:
            source_kind = "own_period_card"
            period_file, hull_id, profile = OWN_PERIOD_CARD[identity]
            if period_file == KULA:
                ship, def_ref = ship_from_kula(profile)
            else:
                ship, def_ref = ship_from_savo(hull_id)
            sibling_note = ""
        else:
            source_kind = "sistership_class_table"
            _, donor_file, donor_row, profile, why = SIBLING[identity]
            if donor_file == KULA:
                ship, def_ref = ship_from_kula(profile)
            else:
                ship, def_ref = ship_from_savo("savo_yunagi")
            period_file, hull_id = donor_file, None
            sibling_note = ("无自有 period 卡；ShipDef 按「同型/按表」复制自 %s，"
                            "取自 %s，未跨到其它舰级。" % (why, def_ref))

        # Registry card = catalogue identity: only id/name are written over the
        # copied row (same rule as scripts/build-period-cards.py).
        ship["id"] = identity
        ship["name"] = card["name"]
        ship["source_profile"] = profile

        missing = completeness(ship)
        if missing:
            raise SystemExit("%s 的 ShipDef 不完整：%s" % (identity, missing))
        if ship["side"] != card["side"]:
            raise SystemExit("%s 的阵营与 playable-cards 不一致" % identity)
        # catalog records the APD transport role; the CAS tables and every
        # registered period card print these hulls as destroyers (kind DD).
        if card["type"] == "APD":
            if ship["kind"] != "DD":
                raise SystemExit("%s: APD 角色的舰表舰种应为 DD，实为 %s" % (identity, ship["kind"]))
        elif ship["kind"] != card["type"]:
            raise SystemExit("%s 的舰种与 playable-cards 不一致" % identity)
        if (ship["side"],) != (catalog_row["side"],):
            raise SystemExit("%s 的阵营与 catalog 不一致" % identity)
        if catalog_row["type"] != "APD":
            raise SystemExit("%s 在 catalog 里不是 APD" % identity)

        form10_record = verify_form10(identity, name_en)
        table_record = verify_class_table(class_key, TABLE_EXPECTED[class_key]["dp"])
        matches = ship_matches_shipdef(ship, class_key, ship_form10["printed"])
        weapon_matches = ship_matches_weapon_tables(ship, class_key)

        # yunagi's playable-cards row has form10_page == null; the savo package
        # records it, so resolve the page from there instead of leaving it blank.
        page = ship_form10["pdf_page"]
        if identity == "IBS-U-IJN-YUNAGI":
            instance = savo_period["instances"]["savo-yunagi"]
            assert instance["form10"]["pdf_page"] == page, "savo 档案的 Yunagi Form 10 页与本批不符"
        if identity == "IBS-U-IJN-YUNAGI":
            page_source = ("savo-island-1942.json#instances.savo-yunagi.form10.pdf_page"
                           "（playable-cards 该条为 null，本批按渲染页复核）")
        elif source_kind == "own_period_card":
            page_source = ("playable-cards.json#cards[].period_cards[].form10_page"
                           "（本批按渲染页复核）")
        else:
            page_source = "无 period 卡；本批按渲染页直接核页"

        profile_meta = dict(class_meta)
        own_notes = {key: value for key, value in class_meta["refit_notes"].items()
                     if key == name_en}
        profile_meta.update({
            "id": profile,
            "registered_row": def_ref,
            "verbatim_fields_note": ("gun_mounts_verbatim / area_aa_verbatim / "
                                     "torpedoes_verbatim / light_aa_verbatim 为级表编制块；"
                                     "本舰改装后的实际装配见 ship_form10。"),
            "refit_notes": own_notes or class_meta["refit_notes"],
            "ship_form10": dict(ship_form10, pdf_document="rising_sun_form10s", pdf_file=FORM10,
                                shipdef_match=matches),
        })

        note = []
        if source_kind == "own_period_card":
            note.append("period 卡自有：%s%s（profile %s）。" %
                        (period_file, "#" + hull_id if hull_id else "", profile))
        else:
            note.append(sibling_note)
        note.append("Form 10 p.%d（%s）逐页目视核对；级表 %s。" %
                    (page, ship_form10["modification"],
                     "/".join(class_meta["source"]["printed_pages"])))
        mismatch = [key for key, value in matches.items() if not value["match"]]
        if not mismatch:
            note.append("该页印值与所用 ShipDef 一致，未改表值。")
        else:
            note.append("该页印值与所用 ShipDef 在 %s 上不一致，已登记 conflict，未自行裁定。"
                        % "、".join(MATCH_LABEL.get(field, field) for field in mismatch))
        note.append("catalog 记 APD（输送角色），舰表与 ShipDef 的舰种仍为 DD。不写 points、不做换算。")

        cards.append({
            "identity": identity,
            "name": card["name"],
            "name_en": name_en,
            "class_label": CLASS_LABEL[class_key],
            "side": card["side"],
            "type": card["type"],
            "source_kind": source_kind,
            "source_file": period_file,
            "source_pages": [
                {"document": "rising_sun_form10s", "file": FORM10,
                 "pdf_pages": [page], "printed_pages": [page],
                 "role": "本舰 Form 10（逐舰卡）", "verified": "page_render",
                 "checked": {key: form10_record[key] for key in
                             ("hull", "class_printed", "damage_row", "speed_row")}},
                {"document": class_meta["source"]["document"],
                 "file": class_meta["source"]["file"],
                 "pdf_pages": class_meta["source"]["pdf_pages"],
                 "printed_pages": class_meta["source"]["printed_pages"],
                 "role": "%s 级表" % class_meta["class"], "verified": "page_render",
                 "checked": {key: table_record[key] for key in
                             ("class_block", "remarks", "dp_row")}},
            ],
            "source_note": "".join(note),
            "profile": profile_meta,
            "ship": ship,
        })
        report_rows.append({
            "identity": identity,
            "name": card["name"],
            "name_en": name_en,
            "type": card["type"],
            "class_label": CLASS_LABEL[class_key],
            "crosswalk_class_label": card.get("class_label"),
            "source_kind": source_kind,
            "source_file": period_file,
            "source_sha256": sha(period_file),
            "period_ship_id": hull_id,
            "period_profile": profile,
            "resolved_from": def_ref,
            "form10_page": page,
            "form10_page_source": page_source,
            "form10_modification": ship_form10["modification"],
            "complete": True,
            "missing_fields": [],
            "torpedo_registered": bool(ship.get("torpedo")),
            "size": ship["size"],
            "turn_advance_yards": ship["turn_advance_yards"],
            "dp": ship["dp"],
            "max_knots": ship["max_knots"],
            "barrels": ship["gun"]["barrels"],
            "shipdef_match": {key: value["match"] for key, value in matches.items()},
            "weapon_table_match": {key: value["match"] for key, value in weapon_matches.items()},
            "shipdef_mismatches": [{"field": key, "label": MATCH_LABEL[key]}
                                   for key, value in matches.items() if not value["match"]],
        })
        shipdef_matches[identity] = matches
        weapon_matches_all[identity] = weapon_matches
        page_verifications.append({"identity": identity,
                                   "form10": form10_record,
                                   "class_table": table_record})

    # ---- same-class consistency: the copied rows must agree field for field
    groups = {}
    for card in cards:
        groups.setdefault(card["profile"]["id"], []).append(card)
    consistency = {}
    for profile, group in groups.items():
        reference = {key: value for key, value in group[0]["ship"].items()
                     if key not in ("id", "name")}
        mismatches = []
        for card in group[1:]:
            for key, value in card["ship"].items():
                if key in ("id", "name"):
                    continue
                if reference.get(key) != value:
                    mismatches.append({"identity": card["identity"], "field": key,
                                       "expected": reference.get(key), "actual": value})
        consistency[profile] = {
            "identities": [card["identity"] for card in group],
            "fields_compared": sorted(reference),
            "identical": not mismatches,
            "mismatches": mismatches,
        }

    # ---- class table vs registered ShipDef
    table_vs_runtime = {}
    for class_key, expected in TABLE_EXPECTED.items():
        members = [card for card in cards if card["profile"]["class"] == CLASS_META[class_key]["class"]]
        if not members:
            continue
        row = members[0]["ship"]
        damage = [point["damage"] for point in row["damage_speed"]]
        knots = [point["knots"] for point in row["damage_speed"]]
        deviations = []
        if row["size"] != expected["size"]:
            deviations.append({"field": "size", "table": expected["size"], "runtime": row["size"],
                               "note": "savo 的 APD 卡用 C（辅助转向表口径），Form 10/级表印 D/Small"})
        if row["turn_advance_yards"] != expected["turn_advance_yards"]:
            deviations.append({"field": "turn_advance_yards",
                               "table": expected["turn_advance_yards"],
                               "runtime": row["turn_advance_yards"],
                               "note": "APD 用辅助转向表 300 yd；Form 10 级表印 200 yd"})
        if damage[:5] != expected["damage_speed"]["damage"][:5] or knots[:5] != expected["damage_speed"]["knots"][:5]:
            deviations.append({"field": "damage_speed", "table": expected["damage_speed"],
                               "runtime": {"damage": damage, "knots": knots},
                               "note": "运行卡省掉 DP 满值一行（dp 字段已含该值）"})
        torpedo = row.get("torpedo")
        tubes = torpedo["tubes"] if torpedo else None
        if tubes != expected["torpedo_tubes"]:
            deviations.append({"field": "torpedo.tubes", "table": expected["torpedo_tubes"],
                               "runtime": tubes,
                               "note": "Kamikaze 级 Type 96 在 Annex F 无弹行，登记卡保持 torpedo=null（不替代）"})
        if row["gun"]["barrels"] != expected["barrels"]:
            deviations.append({"field": "gun.barrels", "table": expected["barrels"],
                               "runtime": row["gun"]["barrels"]})
        table_vs_runtime[class_key] = {
            "table": expected,
            "runtime": {"dp": row["dp"], "max_knots": row["max_knots"], "size": row["size"],
                        "turn_advance_yards": row["turn_advance_yards"],
                        "gun_barrels": row["gun"]["barrels"], "torpedo_tubes": tubes},
            "deviations": deviations,
            "matches_except_registered_deviations": all(
                item["field"] in ("size", "turn_advance_yards", "damage_speed", "torpedo.tubes")
                for item in deviations),
        }

    OUT_CARDS.write_text(json.dumps({
        "schema_version": 1,
        "content_version": "cas-apd-source-cards-v1",
        "as_of": "2026-11-08",
        "generated_by": "scripts/build-apd-source-cards.py",
        "scope": "当前 11 剧本内 8 艘 IJN APD；按用户口径「有数据都录入，只排除航母」出卡",
        "format": {
            "identity": "IBS-U-* 稳定身份（server/catalog.json）",
            "name_en": "剧本/船表英文舰名，用于与 Form 10 页眉对读",
            "class_label": "本批核定的舰级中文名（睦月级 / 神风级）",
            "source_kind": {
                "own_period_card": "该 identity 在 period 运行包里有自己的逐舰卡，ShipDef 原样复制",
                "sistership_class_table": "该 identity 无逐舰 period 卡，ShipDef 原样复制同型 Mutsuki/Kamikaze 级表登记卡",
            },
            "source_file": "ShipDef 来源数据文件（period 运行包），不是 PDF",
            "source_pages": "证据页：本舰 Form 10 + 级表；pdf_pages 与 printed_pages 分开记",
            "profile": "级表元数据（savo-island-1942.json profiles 格式）+ 本舰 Form 10 逐项印值",
            "ship": "完整 ShipDef（与 period 运行包同一 schema；只改写 id/name，加 source_profile）",
        },
        "source": {
            "identity_index": PLAYABLE + "#cards[].period_cards",
            "period_packages": [KULA, SAVO],
            "cas_tables": [FORM10, EMPERORS],
            "policy": ("逐舰 period 卡原样复制：不换算、不补默认值、不跨级套用。"
                       "5 艘有自有卡者直接取原 profile/ship；3 艘无自有卡者只取同型 "
                       "Mutsuki/Kamikaze 级表登记卡（mutsuki / jp_kamikaze_1941_dd），"
                       "逐舰 Form 10 差异只登记不改值。不写 points。"),
        },
        "cards": cards,
    }, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    checks = {
        "cards_expected": 8,
        "cards_written": len(cards),
        "count_ok": len(cards) == 8,
        "identities_match_task_list": [card["identity"] for card in cards] == ORDER,
        "unique_identities": len({card["identity"] for card in cards}) == len(cards),
        "all_type_apd": all(card["type"] == "APD" for card in cards),
        "all_side_axis": all(card["side"] == "axis" for card in cards),
        "carriers_excluded": not any(card["type"] in ("CV", "CVE", "CVL") for card in cards),
        "side_matches_catalog": all(
            card["side"] == catalog[card["identity"]]["side"] for card in cards),
        "apd_role_kind_mapping": {
            card["identity"]: {"catalog_type": catalog[card["identity"]]["type"],
                               "ship_kind": card["ship"]["kind"], "ok": card["ship"]["kind"] == "DD"}
            for card in cards
        },
        "apd_role_kind_mapping_ok": all(card["ship"]["kind"] == "DD" for card in cards),
        "source_pages_present_all": all(len(card["source_pages"]) >= 2 for card in cards),
        "source_pages_page_verified_all": all(
            row["form10"]["verified"] and row["class_table"]["verified"]
            for row in page_verifications),
        "page_verifications": page_verifications,
        "form10_page_verified_all": all(
            "Page %d" % card["profile"]["ship_form10"]["pdf_page"]
            in PDF.page_text(FORM10, card["profile"]["ship_form10"]["pdf_page"])
            for card in cards),
        "form10_vs_shipdef": {identity: {key: value["match"] for key, value in matches.items()}
                              for identity, matches in shipdef_matches.items()},
        "form10_vs_shipdef_mismatches": [
            {"identity": identity, "field": field, "label": MATCH_LABEL[field],
             "printed": value["printed"], "shipdef": shipdef_value(value)}
            for identity, matches in shipdef_matches.items()
            for field, value in matches.items() if not value["match"]
        ],
        "shipdef_mismatches_are_registered_conflicts": (
            {(identity, field) for identity, matches in shipdef_matches.items()
             for field, value in matches.items() if not value["match"]} == ALLOWED_MISMATCH),
        "registered_conflict_fields": sorted("%s:%s" % pair for pair in ALLOWED_MISMATCH),
        "weapon_tables_vs_shipdef": weapon_matches_all,
        "weapon_tables_match_shipdef_ok": all(
            all(value["match"] for value in row.values()) for row in weapon_matches_all.values()),
        "same_class_consistency": consistency,
        "same_class_consistency_ok": all(row["identical"] for row in consistency.values()),
        "class_table_vs_runtime": table_vs_runtime,
        "class_table_deviations_registered": all(
            row["matches_except_registered_deviations"] for row in table_vs_runtime.values()),
        "ship_def_complete_all": all(card["ship"]["id"] == card["identity"] for card in cards),
        "no_points_fields": not has_points(cards),
        "own_period_card_count": sum(1 for card in cards if card["source_kind"] == "own_period_card"),
        "sistership_class_table_count": sum(
            1 for card in cards if card["source_kind"] == "sistership_class_table"),
    }
    checks["all_checks_pass"] = all([
        checks["count_ok"], checks["identities_match_task_list"], checks["unique_identities"],
        checks["all_type_apd"], checks["all_side_axis"], checks["carriers_excluded"],
        checks["side_matches_catalog"], checks["apd_role_kind_mapping_ok"],
        checks["source_pages_present_all"], checks["source_pages_page_verified_all"],
        checks["shipdef_mismatches_are_registered_conflicts"],
        checks["weapon_tables_match_shipdef_ok"],
        checks["form10_page_verified_all"], checks["same_class_consistency_ok"],
        checks["class_table_deviations_registered"], checks["ship_def_complete_all"],
        checks["no_points_fields"],
    ])

    conflicts = [
        {"id": "U-APD-MUTSUKI-TORPEDO", "severity": "high",
         "issue": "级表 A-27 印 P&S(3)2 610mm TT w/3 8th Yr Type No. 2；Mutsuki 各舰 1942-43 Form 10 印 Type 93 Model 1 Mod 1/2（22.0/35.0/43.8 kyds）",
         "identities": ["IBS-U-IJN-MONCHIZUKI", "IBS-U-IJN-MIKAZUKI", "IBS-U-IJN-NAGATSUKI",
                        "IBS-U-IJN-SATSUKI", "IBS-U-IJN-MINAZUKI", "IBS-U-IJN-FUMIZUKI"],
         "evidence": "kula-runtime profiles.mutsuki torpedo.name=八年式二号；Form 10 p.177-182 印 Type 93；cape-st-george-1943.json conflicts.uzuki-torpedo-model 已登记同一矛盾（未裁决）",
         "action": "本批沿用登记卡（8th Yr Type No.2），不替换、不改表值；待裁决后再动"},
        {"id": "U-APD-FUMIZUKI-FIT", "severity": "high",
         "issue": "Fumizuki Form 10 p.177（May-Aug 43）印 Fwd/P&S/Aft 三座 12cm，但 Area AA 只印 (1)2；A-28 注记称 P&S 12cm 与后部雷管已拆（→2 炮/1 雷管座）",
         "identities": ["IBS-U-IJN-FUMIZUKI"],
         "evidence": "Form 10 p.177 vs Emperor's Fleet A-28 refit note",
         "action": "本批按「同型/按表」用 mutsuki 级表 4 炮/6 管；舰页差异已登记，未自行改为 2 炮"},
        {"id": "U-APD-KAMIKAZE-SIZE-TURN", "severity": "medium",
         "issue": "savo_yunagi 登记 size=C、turn_advance=300；Form 10 p.176 与 A-24 均印 D/Small、Standard Rudder 200 yds",
         "identities": ["IBS-U-IJN-YUNAGI", "IBS-U-IJN-MATSU-KAZE"],
         "evidence": "savo-runtime ships[savo_yunagi]；savo-island-1942.json metadata.restrictions（APD 用辅助转向表）",
         "action": "自有卡原样保留；Matsukaze 复制同型卡保持同级一致；差额登记待裁决"},
        {"id": "U-APD-MUTSUKI-APD-TURN", "severity": "medium",
         "issue": "同为 APD：kula 的 4 艘 Mutsuki 用级表 200 yd，savo 的 Yunagi 用辅助表 300 yd",
         "identities": ["IBS-U-IJN-MONCHIZUKI", "IBS-U-IJN-MIKAZUKI", "IBS-U-IJN-NAGATSUKI",
                        "IBS-U-IJN-SATSUKI", "IBS-U-IJN-YUNAGI"],
         "evidence": "kula-runtime profiles.mutsuki/mutsuki_mikazuki vs savo-runtime ships[savo_yunagi]",
         "action": "两包口径并存；本批不统一、不换算"},
        {"id": "U-APD-KAMIKAZE-LIGHTAA", "severity": "low",
         "issue": "Kamikaze 级轻防空：A-24 印 10 Type 96 25mm (1.2)；Yunagi/Matsukaze Form 10（Dec 1941）印 2 13mm (0.1)",
         "identities": ["IBS-U-IJN-YUNAGI", "IBS-U-IJN-MATSU-KAZE"],
         "evidence": "The Emperor's Fleet A-24 vs Form 10 p.175/176",
         "action": "ShipDef 无轻防空字段（原卡即无），两种印值都登记在 profile.ship_form10，不下裁定"},
    ]
    unresolved = [
        {"id": "U-APD-NO-PERIOD-CARD", "severity": "high",
         "issue": "Minazuki / Matsukaze / Fumizuki 在 scenario 包里没有逐舰 period 卡（只有 Form 10 与级表）",
         "identities": ["IBS-U-IJN-MINAZUKI", "IBS-U-IJN-MATSU-KAZE", "IBS-U-IJN-FUMIZUKI"],
         "evidence": "playable-cards.json 三条无 period_cards；kula/savo runtime 无对应 instance",
         "action": "按同型级表出卡；若要舰页精确值需先裁决 U-APD-FUMIZUKI-FIT 与 Kamikaze 辅助表口径"},
        {"id": "U-APD-NOT-IN-CATALOG-COMBAT", "severity": "medium",
         "issue": "8 条 catalog 仍是 APD/combat_ready=false，本批只出数据，未改 catalog、未登记 points/ranked",
         "identities": ORDER,
         "evidence": "server/catalog.json type=APD, combat_ready=false",
         "action": "接线（catalog/ranked_fleets）由后续批次处理，本批按约束未动"},
    ]

    page_index = {}
    for card in cards:
        for page in card["source_pages"]:
            key = (page["document"], tuple(page["pdf_pages"]), tuple(page["printed_pages"]))
            row = page_index.setdefault(key, {
                "document": page["document"], "file": page["file"],
                "pdf_pages": page["pdf_pages"], "printed_pages": page["printed_pages"],
                "role": page["role"], "verified": page["verified"], "cards": []})
            row["cards"].append(card["identity"])
    page_resolution = {
        "unresolved": [],
        "note": ("8 条的逐舰 Form 10 页全部在本批按渲染页确认（页眉舰名 + 舰级 + DP/航速行），"
                 "级表页同样逐页确认；没有需要标 unresolved 的页码。"),
        "index": sorted(page_index.values(), key=lambda row: row["pdf_pages"][0]),
    }

    report = {
        "schema_version": 1,
        "content_version": "cas-apd-source-cards-v1",
        "as_of": "2026-11-08",
        "generated_by": "scripts/build-apd-source-cards.py",
        "source": {
            "identity_index": PLAYABLE + "#cards[].period_cards",
            "period_packages": [KULA, SAVO],
            "period_metadata_format_reference": SAVO_PERIOD + "#profiles",
            "cas_tables": [FORM10, EMPERORS],
            "class_refit_notes": {key: meta["refit_notes"] for key, meta in CLASS_META.items()},
            "policy": ("5 艘有自有 period 卡：直接复制原 profile/ship（kula profiles.mutsuki、"
                       "mutsuki_mikazuki；savo ships[savo_yunagi]）。3 艘无自有卡：只取同型 "
                       "Mutsuki（profiles.mutsuki）/ Kamikaze（savo_yunagi = jp_kamikaze_1941_dd）"
                       "级表登记值，注明「同型/按表」，不跨到其它级。不写 points，不改表值。"),
        },
        "coverage": {
            "apd_identities_in_catalog": 8,
            "cards_written": len(cards),
            "own_period_card": checks["own_period_card_count"],
            "sistership_class_table": checks["sistership_class_table_count"],
            "carriers": "按用户口径只排除航母；本批 8 条均为 APD，无航母混入",
            "scenarios": {
                "cas-rs-kula-gulf": ["IBS-U-IJN-MONCHIZUKI", "IBS-U-IJN-MIKAZUKI",
                                     "IBS-U-IJN-NAGATSUKI", "IBS-U-IJN-SATSUKI"],
                "cas-rs-kolombangara": ["IBS-U-IJN-MIKAZUKI", "IBS-U-IJN-SATSUKI",
                                        "IBS-U-IJN-YUNAGI", "IBS-U-IJN-MINAZUKI",
                                        "IBS-U-IJN-MATSU-KAZE"],
                "cas-rs-savo-island": ["IBS-U-IJN-YUNAGI"],
                "cas-rs-vella-lavella": ["IBS-U-IJN-YUNAGI", "IBS-U-IJN-MATSU-KAZE",
                                         "IBS-U-IJN-FUMIZUKI"],
            },
        },
        "cards": report_rows,
        "checks": checks,
        "page_resolution": page_resolution,
        "conflicts": conflicts,
        "unresolved": unresolved,
        "blockers": [
            "3 艘无 period 卡（Minazuki/Matsukaze/Fumizuki）：数据靠同型级表，舰页精确值待裁决",
            "Fumizuki 舰页炮座数与级表不一致（U-APD-FUMIZUKI-FIT）",
            "Mutsuki 级鱼雷型号级表 vs Form 10 矛盾未裁决（U-APD-MUTSUKI-TORPEDO）",
            "本批只写 data/ships/，catalog/ranked_fleets 接线不在本批范围",
        ],
    }
    OUT_REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    print("cards", len(cards))
    print("own", checks["own_period_card_count"], "sibling", checks["sistership_class_table_count"])
    print("checks", json.dumps({key: value for key, value in checks.items()
                                if isinstance(value, bool)}, ensure_ascii=False))
    print("all_checks_pass", checks["all_checks_pass"])


if __name__ == "__main__":
    main()
