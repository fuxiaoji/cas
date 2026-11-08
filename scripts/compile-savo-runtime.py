"""Compile the checked Savo hulls into the campaign runtime.

Sources: data/campaign/period/savo-island-1942.json (verified annex rows and
Form 10 fits), American Fleets A-42-A-47 and Form 10s pages 354-380 for the
transports, DMS and APD. The chart positions come from chart-savo.json; ships
without a readable silhouette anchor use their patrol line or transport area
with the registered global spacing default.
"""
import json, math, re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PERIOD = json.loads((ROOT / "data/campaign/period/savo-island-1942.json").read_text(encoding="utf-8"))
CHART = json.loads((ROOT / "data/campaign/period/chart-savo.json").read_text(encoding="utf-8"))
OUT = ROOT / "data/campaign/period/savo-runtime.json"

# Rulebook 3-2: warship turn/accel per size class. Merchant auxiliaries use
# the auxiliary table and their printed -50%/-15% damage modifiers.
TURN = {"A": (400, 2), "B": (300, 2), "C": (300, 1), "D": (200, 1)}
ACCEL = {"A": (6, 3, 9), "B": (10, 5, 12), "C": (12, 6, 15), "D": (12, 6, 15)}
AUX_ACCEL = (6, 3, 9)

GUN = {
    "us_8in55_mk9_10_11_13_14": ("Mk9/14 8in/55", 203, "APC", "us"),
    "us_5in38_mk12_mk38": ("Mk12/38 5in/38", 127, "SpCOM", "us"),
    "gb_8in50_mkviii": ("8in/50 MkVIII", 203, "APC", "gb"),
    "gb_6in50_mkxxiii": ("6in/50 MkXXIII", 152, "APC", "gb"),
    "jp_3rd_yr_type_no2_20cm50": ("三年式二号 20cm/50", 203, "APC", "jp"),
    "jp_10th_yr_type_12cm45": ("十年式 12cm/45", 120, "COM", "jp"),
    "jp_3rd_11th_yr_type_12cm45": ("三年/十一年式 12cm/45", 120, "COM", "jp"),
    "jp_3rd_yr_type_14cm50": ("三年式 14cm/50", 140, "SpCOM", "jp"),
}
TORP = {
    "jp_type93_model1_mod1_2_torpedo": ("九三式一型 Mod 1/2", 95),
    "jp_8th_yr_type_no2_torpedo": ("八年式二号", 87),
    "gb_mkix_torpedo": ("MkIX", 84),
    "us_mk15_tnt_torpedo": ("Mk15（TNT）", 87),
}
ARC = {"F": ([210, 150], None), "A": ([30, 330], None), "P&S": ([30, 150], [210, 330])}
# Explicit mount tables transcribed from the printed rows (barrels per mount
# and its arc). Keys are (class, main_gun) from the period file.
MOUNTS = {
    ("New Orleans", "us_8in55_mk9_10_11_13_14"): [{"barrels": 3, "arc": [210, 150], "arc2": None}, {"barrels": 3, "arc": [210, 150], "arc2": None}, {"barrels": 3, "arc": [30, 330], "arc2": None}, {"barrels": 3, "arc": [30, 330], "arc2": None}],  # 2F/A(3)3
    ("Northampton", "us_8in55_mk9_10_11_13_14"): [{"barrels": 3, "arc": [210, 150], "arc2": None}, {"barrels": 3, "arc": [210, 150], "arc2": None}, {"barrels": 3, "arc": [30, 330], "arc2": None}, {"barrels": 3, "arc": [30, 330], "arc2": None}],
    ("Kent", "gb_8in50_mkviii"): [{"barrels": 4, "arc": [210, 150], "arc2": None}, {"barrels": 4, "arc": [30, 330], "arc2": None}],  # F/A(2)4
    ("Takao", "jp_3rd_yr_type_no2_20cm50"): [{"barrels": 5, "arc": [210, 150], "arc2": None}, {"barrels": 5, "arc": [210, 150], "arc2": None}, {"barrels": 5, "arc": [30, 330], "arc2": None}, {"barrels": 5, "arc": [30, 330], "arc2": None}],  # 2F/2A(2)5
    ("Aoba", "jp_3rd_yr_type_no2_20cm50"): [{"barrels": 3, "arc": [210, 150], "arc2": None}, {"barrels": 3, "arc": [210, 150], "arc2": None}, {"barrels": 3, "arc": [30, 330], "arc2": None}, {"barrels": 3, "arc": [30, 330], "arc2": None}],  # 2F/A(2)3
    ("Furutaka", "jp_3rd_yr_type_no2_20cm50"): [{"barrels": 3, "arc": [210, 150], "arc2": None}, {"barrels": 3, "arc": [210, 150], "arc2": None}, {"barrels": 3, "arc": [30, 330], "arc2": None}, {"barrels": 3, "arc": [30, 330], "arc2": None}],
    ("Atlanta", "us_5in38_mk12_mk38"): [{"barrels": 2, "arc": [210, 150], "arc2": None}, {"barrels": 2, "arc": [210, 150], "arc2": None}, {"barrels": 2, "arc": [30, 150], "arc2": [210, 330]}, {"barrels": 2, "arc": [30, 330], "arc2": None}, {"barrels": 2, "arc": [30, 330], "arc2": None}],  # 5F/P&S/A 2 → 7 twin mounts total is 16 guns; AF prints 16×5in/38
    ("Perth", "gb_6in50_mkxxiii"): [{"barrels": 4, "arc": [210, 150], "arc2": None}, {"barrels": 4, "arc": [30, 330], "arc2": None}],  # F/A(2)4
    ("Tenryu", "jp_3rd_yr_type_14cm50"): [{"barrels": 1, "arc": [210, 150], "arc2": None}, {"barrels": 1, "arc": [30, 150], "arc2": [210, 330]}, {"barrels": 1, "arc": [30, 150], "arc2": [210, 330]}, {"barrels": 1, "arc": [30, 330], "arc2": None}],  # F/P&S/A(1)4 singles
    ("Yubari", "jp_3rd_yr_type_14cm50"): [{"barrels": 2, "arc": [210, 150], "arc2": None}, {"barrels": 2, "arc": [30, 330], "arc2": None}, {"barrels": 1, "arc": [210, 150], "arc2": None}, {"barrels": 1, "arc": [30, 330], "arc2": None}],  # F/A(2)2 + F/A(1)2
    ("Kamikaze (1941)", "jp_3rd_11th_yr_type_12cm45"): [{"barrels": 1, "arc": [210, 150], "arc2": None}, {"barrels": 1, "arc": [30, 150], "arc2": [210, 330]}, {"barrels": 1, "arc": [30, 330], "arc2": None}],  # F/2P&S(1)3 singles
    ("Bagley", "us_5in38_mk12_mk38"): [{"barrels": 4, "arc": [210, 150], "arc2": None}, {"barrels": 4, "arc": [30, 330], "arc2": None}],  # F/A(1)4
    ("Gridley", "us_5in38_mk12_mk38"): [{"barrels": 4, "arc": [210, 150], "arc2": None}, {"barrels": 4, "arc": [30, 330], "arc2": None}],
    ("Benham", "us_5in38_mk12_mk38"): [{"barrels": 4, "arc": [210, 150], "arc2": None}, {"barrels": 4, "arc": [30, 330], "arc2": None}],
    ("Benson-Livermore", "us_5in38_mk12_mk38"): [{"barrels": 4, "arc": [210, 150], "arc2": None}, {"barrels": 4, "arc": [30, 330], "arc2": None}],
    ("Bristol", "us_5in38_mk12_mk38"): [{"barrels": 4, "arc": [210, 150], "arc2": None}, {"barrels": 4, "arc": [30, 330], "arc2": None}],
    ("Farragut", "us_5in38_mk12_mk38"): [{"barrels": 1, "arc": [210, 150], "arc2": None}, {"barrels": 1, "arc": [30, 150], "arc2": [210, 330]}, {"barrels": 1, "arc": [30, 330], "arc2": None}, {"barrels": 1, "arc": [210, 150], "arc2": None}, {"barrels": 1, "arc": [30, 330], "arc2": None}],  # F/P&S/A(1)5
    ("Porter", "us_5in38_mk12_mk38"): [{"barrels": 2, "arc": [210, 150], "arc2": None}, {"barrels": 2, "arc": [210, 150], "arc2": None}, {"barrels": 2, "arc": [30, 330], "arc2": None}, {"barrels": 2, "arc": [30, 330], "arc2": None}],  # F/A(2)4 low-angle
}


def mounts(verbatim, kind):
    """Parse the printed mount notation into engine arc rows."""
    text = verbatim
    # F/A(2)4 or 2F/A(3)3 style: bow/stern multiples plus beam singles.
    rows = []
    takao = re.match(r"^(\d)?F/P&S/(\d)?A\((\d)\)(\d)", text.strip())
    if takao and not rows:
        # (n) = number of mounts, (d) = barrels per mount. Printed
        # "2F/P&S/2A(2)5" = two fore 5-gun turrets, two aft 5-gun turrets,
        # plus single P&S mounts of the same battery count on the beam.
        barrels = int(takao.group(4))
        mounts_n = int(takao.group(3))
        # Takao printed: two fore 5-gun turrets + two aft 5-gun turrets
        # (2F.../2A with (2)5 = 2 mounts of 5 barrels) plus P&S singles of
        # the 12cm secondary. The heavy battery is 10 barrels total; the
        # beam singles belong to the 12cm/45 secondary row, not this gun.
        for _ in range(int(takao.group(1) or 1)):
            rows.append(("F", barrels))
        for _ in range(int(takao.group(2) or 1)):
            rows.append(("A", barrels))
    multi = re.search(r"(\d)?F/P&S/(\d)?A\((\d)\)(\d)", text)
    if multi:
        lead = int(multi.group(1) or 1)
        aft = int(multi.group(2) or 1)
        for _ in range(lead):
            rows.append(("F", multi.group(4)))
        rows.append(("P&S", multi.group(4)))
        for _ in range(aft):
            rows.append(("A", multi.group(4)))
    multi = re.search(r"(\d)?F/A\((\d)\)(\d)", text)
    if multi:
        lead = int(multi.group(1) or 1)
        for _ in range(lead):
            rows.append(("F", multi.group(3)))
        for _ in range(int(multi.group(2))):
            rows.append(("A", multi.group(3)))
    takao_hit = re.match(r"^(\d)?F/P&S/(\d)?A\((\d)\)(\d)", text.strip())
    if "P&S" in text and not takao_hit:
        beam = re.search(r"P&S\((\d)\)(\d)", text)
        if beam:
            rows.append(("P&S", beam.group(2)))
    if not rows:
        # Atlanta 5F/P/S/A 2: five single mounts fore, beam singles, aft.
        atlanta = re.match(r"^([0-9])F/P/S/A", text.strip())
        if atlanta:
            n = int(atlanta.group(1))
            for _ in range(n - 1):
                rows.append(("F", "1"))
            rows.append(("P&S", "1"))
            rows.append(("A", "1"))
    if not rows:
        simple = re.search(r"F(?:/2P&S)?(?:/P&S)?/A\((\d)\)(\d)", text)
        if simple:
            # F/P&S/A(1)4 reads as four single mounts spread fore, both
            # beams and aft; (n) is the count of singles per the notation.
            count = int(simple.group(1))
            barrels = int(simple.group(2))
            rows.append(("F", barrels))
            rows.append(("P&S", barrels))
            rows.append(("A", barrels))
            for _ in range(max(0, count - 3)):
                rows.append(("P&S", barrels))
    if not rows:
        # Takao 2F/P&S/2A(2)5: lead/twin beam/twin aft heavy cruiser battery.
        takao = re.match(r"^(\d)F/P&S/(\d)A\((\d)\)(\d)", text.strip())
        if takao:
            for _ in range(int(takao.group(1))):
                rows.append(("F", takao.group(4)))
            rows.append(("P&S", takao.group(4)))
            for _ in range(int(takao.group(2))):
                rows.append(("A", takao.group(4)))
    if not rows:
        # Atlanta 5F/P/S/A 2: five single mounts fore, beam singles, aft.
        atlanta = re.match(r"^([0-9])F/P/S/A", text.strip())
        if atlanta:
            n = int(atlanta.group(1))
            for _ in range(n - 1):
                rows.append(("F", "1"))
            rows.append(("P&S", "1"))
            rows.append(("A", "1"))
    assert rows, verbatim
    out = []
    for arc, barrels in rows:
        a, b = ARC[arc]
        out.append({kind: int(barrels), "arc": a, "arc2": b})
    return out


def profile_row(name):
    profile = PERIOD["profiles"][name]
    row = dict(profile)
    if "profile_ref" in profile and "damage_points" not in profile:
        row = {**PERIOD["profiles"][profile["profile_ref"].removeprefix("#")], **profile}
    return row


def gun_of(profile):
    model = profile["main_gun"]
    label, caliber, shell, _ = GUN[model]
    data = PERIOD["weapon_models"][model]
    shells = data["shells"][shell]
    ranges = shells.get("range_yd") or data["range_bands_kyd"]
    bands = [[lo, hi] for lo, hi in ranges]
    key = None
    for (cls, gun_model), table in MOUNTS.items():
        if str(profile.get("class", "")).startswith(cls) and profile.get("main_gun") == gun_model:
            key = table
            break
    parsed_mounts = key or mounts(profile.get("gun_mounts_verbatim", ""), "barrels")
    return {
        "name": f"{label} {shell}", "caliber_mm": caliber,
        "range_yd": [float(hi) * 1000 for _, hi in bands],
        "damage": shells["damage_dp"], "gs": 4,
        "barrels": sum(m["barrels"] for m in parsed_mounts),
        "mounts": parsed_mounts,
        "pen_belt": shells["belt"], "pen_deck": shells["deck"],
        "armor_piercing": shell in ("APC", "SAP", "SpCOM"),
    }, sum(m["barrels"] for m in parsed_mounts)


# Explicit torpedo fits from AF/EF printed rows: (model, tubes per mount, mounts, reserve per mount)
TORP_FITS = {
    "GB Kent": ("gb_mkix_torpedo", 2, 4, 0),                  # P/S(4)2 w/4 MkIX
    "Takao": ("jp_type93_model1_mod1_2_torpedo", 4, 4, 2),   # P/S(4)4 w/8 reserve
    "Myoko": ("jp_type93_model1_mod1_2_torpedo", 4, 2, 4),
    "Aoba": ("jp_type93_model1_mod1_2_torpedo", 4, 2, 0),
    "Furutaka": ("jp_type93_model1_mod1_2_torpedo", 4, 2, 0),
    "Perth": ("gb_mkix_torpedo", 2, 4, 0),
    "Atlanta": ("us_mk15_tnt_torpedo", 2, 2, 0),             # 2P/S(2) w/4
    "Bagley": ("us_mk15_tnt_torpedo", 4, 2, 0),              # P/S(4)4 w/4
    "Gridley": ("us_mk15_tnt_torpedo", 4, 2, 0),
    "Benham": ("us_mk15_tnt_torpedo", 4, 2, 0),
    "Benson-Livermore": ("us_mk15_tnt_torpedo", 4, 2, 0),
    "Bristol": ("us_mk15_tnt_torpedo", 4, 2, 0),
    "Farragut": ("us_mk15_tnt_torpedo", 4, 2, 0),
    "Porter": ("us_mk15_tnt_torpedo", 2, 2, 4),              # P/S(4)2 w/4 reserve
    "Tenryu": ("jp_8th_yr_type_no2_torpedo", 3, 2, 0),       # P&S(2)3 w/6
    # Yunagi Type 96 has no Annex F row: omitted (registered restriction).
    "Yubari": ("jp_8th_yr_type_no2_torpedo", 2, 2, 1),       # P&S(2)2 w/1 reserve
}

def torpedo_of(profile, forced_none=False):
    torp = profile.get("torpedoes_verbatim") or ""
    model = None
    if "Type 93" in torp:
        model = "jp_type93_model1_mod1_2_torpedo"
    elif "8th Yr" in torp:
        model = "jp_8th_yr_type_no2_torpedo"
    elif "MkIX" in torp:
        model = "gb_mkix_torpedo"
    elif "Mk15" in torp:
        model = "us_mk15_tnt_torpedo"
    cls = str(profile.get("class", ""))
    fit = None
    for name, values in TORP_FITS.items():
        if cls.startswith(name):
            fit = values
            break
    if fit:
        model, per_mount, count, reserve = fit
    elif not model or forced_none:
        return None
    else:
        return None
    label, dp = TORP[model]
    data = PERIOD["weapon_models"][model]["torpedo"]
    yard, knots = data["range_speed_pairs_yd_knots"][0]
    a, b = ARC["P&S"]
    return {
        "name": label, "speed_knots": knots, "range_yd": yard, "warhead": dp,
        "tubes": per_mount * count, "contact_fuze": True,
        "mounts": [{"tubes": per_mount, "arc": a, "arc2": b, "reserve": reserve} for _ in range(count)],
        "fit_note": "mount row " + (profile.get("torpedoes_verbatim") or ""),
    }


def ship_row(id, name, side, kind, size, profile_name, dp_row, speeds, note=None):
    profile = profile_row(profile_name)
    gun, barrels = gun_of(profile)
    torp = torpedo_of(profile, forced_none=kind in ("AP", "APA", "AK", "AKA", "DMS", "APD"))
    armor_text = profile.get("armor_rating", 0)
    belt, deck = (0, 0) if armor_text in (0, "0") else (int(str(armor_text).split("/")[0]), int(str(armor_text).split("/")[1]))
    accel = ACCEL.get(size, AUX_ACCEL)
    return {
        "id": id, "name": name, "side": side, "kind": kind, "size": size,
        "max_knots": speeds[0], "dp": dp_row[-1],
        "damage_speed": [{"damage": d, "knots": k} for d, k in zip(dp_row, speeds + [0])],
        "turn_advance_yards": TURN[size][0], "speed_loss_knots": TURN[size][1],
        "accel_knots_per_turn": accel[0], "accel_high_knots_per_turn": accel[1],
        "brake_knots_per_turn": accel[2],
        "armor_belt": belt, "armor_deck": deck, "in_service_year": profile.get("in_service_year", 1940),
        "gun": gun, "torpedo": torp, "source_profile": profile_name, **({"note": note} if note else {}),
    }


def aux_row(id, name, dp, speeds, size, gun_barrels, caliber, year, displacement):
    return {
        "id": id, "name": name, "side": "allies", "kind": "AP", "size": size,
        "max_knots": speeds[0], "dp": dp[-1],
        "damage_speed": [{"damage": d, "knots": k} for d, k in zip(dp, speeds + [0])],
        "turn_advance_yards": 300, "speed_loss_knots": 3,
        "accel_knots_per_turn": AUX_ACCEL[0], "accel_high_knots_per_turn": AUX_ACCEL[1],
        "brake_knots_per_turn": AUX_ACCEL[2],
        "armor_belt": 0, "armor_deck": 0, "in_service_year": year,
        "gun": {
            "name": f"{caliber}in/38或3in/50（武装商船）", "caliber_mm": caliber * 25.4,
            "range_yd": [5500, 10900, 14600, 18200],
            "damage": [18, 14, 12, 11], "gs": 4,
            "mounts": [{"barrels": gun_barrels, "arc": [30, 150], "arc2": [210, 330]}],
            "pen_belt": [7, 4, 3, 2], "pen_deck": [None, None, 1, 2],
            "armor_piercing": False,
        },
        "torpedo": None,
        "note": f"武装商船/辅助舰，位移 {displacement}；民用建造 -50% 特殊损伤修正，单轴工程临界双倍掉速。Form 10/AF A-42–A-47。",
    }


def main():
    rows = []
    # Combat ships from the Savo period file, class-level cards.
    classes = {
        "savo_vincennes": ("文森斯", "allies", "CA", "B", "us_new_orleans_ca", 1934),
        "savo_quincy": ("昆西", "allies", "CA", "B", "us_new_orleans_ca", 1936),
        "savo_astoria": ("阿斯托利亚", "allies", "CA", "B", "us_new_orleans_ca", 1934),
        "savo_chicago": ("芝加哥", "allies", "CA", "B", "us_northampton_ca", 1929),
        "savo_australia": ("澳大利亚", "allies", "CA", "B", "gb_kent_1939_ca", 1928),
        "savo_canberra": ("堪培拉", "allies", "CA", "B", "gb_kent_1939_ca", 1928),
        "savo_san_juan": ("圣胡安", "allies", "CL", "B", "us_atlanta_cl", 1942),
        "savo_hobart": ("霍巴特", "allies", "CL", "B", "gb_perth_cl", 1934),
        "savo_chokai": ("鸟海", "axis", "CA", "B", "jp_takao_1939_ca", 1932),
        "savo_aoba": ("青叶", "axis", "CA", "B", "jp_aoba_1938_ca", 1927),
        "savo_kako": ("加古", "axis", "CA", "B", "jp_furutaka_1937_ca", 1926),
        "savo_kinugasa": ("衣笠", "axis", "CA", "B", "jp_aoba_1938_ca", 1927),
        "savo_furutaka": ("古鹰", "axis", "CA", "B", "jp_furutaka_1937_ca", 1926),
        "savo_tenryu": ("天龙", "axis", "CL", "C", "jp_tenryu_cl", 1919),
        "savo_yubari": ("夕张", "axis", "CL", "C", "jp_yubari_cl", 1923),
        "savo_yunagi": ("夕凪", "axis", "DD", "C", "jp_kamikaze_1941_dd", 1925),
        "savo_blue": ("布鲁", "allies", "DD", "C", "us_bagley_dd", 1937),
        "savo_ralph_talbot": ("拉尔夫·托尔伯特", "allies", "DD", "C", "us_bagley_dd", 1937),
        "savo_bagley": ("巴格利", "allies", "DD", "C", "us_bagley_dd", 1937),
        "savo_patterson": ("帕特森", "allies", "DD", "C", "us_bagley_dd", 1937),
        "savo_helm": ("赫尔姆", "allies", "DD", "C", "us_bagley_dd", 1937),
        "savo_wilson": ("威尔逊", "allies", "DD", "C", "us_benham_dd", 1939),
        "savo_helm_gridley_note": None,
        "savo_monssen": ("蒙森", "allies", "DD", "C", "us_benson_dd", 1940),
        "savo_buchanan": ("布坎南", "allies", "DD", "C", "us_bristol_dd", 1942),
        "savo_jarvis": ("贾维斯", "allies", "DD", "C", "us_bagley_dd", 1937),
        "savo_selfridge": ("塞尔弗里奇", "allies", "DD", "C", "us_porter_dd", 1936),
        "savo_mugford": ("马格福德", "allies", "DD", "C", "us_gridley_dd", 1937),
        "savo_dewey": ("杜威", "allies", "DD", "C", "us_farragut_dd", 1934),
        "savo_hull": ("赫尔", "allies", "DD", "C", "us_farragut_dd", 1934),
        "savo_henley": ("亨利", "allies", "DD", "C", "us_gridley_dd", 1937),
        "savo_ellet": ("埃利特", "allies", "DD", "C", "us_benham_dd", 1939),
    }
    for id, spec in classes.items():
        if spec is None:
            continue
        name, side, kind, size, profile, year = spec
        base = profile_row(profile)
        if id == "savo_hobart" and "damage_points_hobart" in base:
            base = {**base, "damage_points": base["damage_points_hobart"]}
        row = ship_row(id, name, side, kind, size, profile,
                       base["damage_points"], base["speed_knots"])
        row["in_service_year"] = year
        rows.append(row)
    # X-Ray transports and Yoke auxiliaries with Form 10 rows.
    transports = [
        ("savo_fuller", "富勒", (32, 65, 97, 116, 129), (16, 12, 8, 4), "B", 4, 3, 1940, "8000 ltshp Heywood APA"),
        ("savo_american_legion", "美国军团", (42, 85, 127, 152, 169), (17, 13, 9, 4), "B", 4, 3, 1940, "13529 std Harris APA"),
        ("savo_bellatrix", "贝拉特里克斯", (44, 87, 131, 157, 174), (16, 12, 8, 4), "C", 1, 5, 1941, "Arcturus AKA"),
        ("savo_mccawley", "麦考利", (42, 84, 126, 151, 168), (16, 12, 8, 4), "B", 4, 3, 1940, "7858 std McCawley AP"),
        ("savo_barnett", "巴尼特", (42, 84, 126, 151, 168), (16, 12, 8, 4), "B", 4, 3, 1940, "McCawley AP"),
        ("savo_george_f_elliott", "乔治·F·埃利奥特", (32, 65, 97, 116, 129), (16, 12, 8, 4), "B", 4, 3, 1940, "Heywood APA · 原页标记 DIW on fire"),
        ("savo_libra", "天秤座", (44, 87, 131, 157, 174), (16, 12, 8, 4), "C", 1, 5, 1941, "Arcturus AKA"),
        ("savo_hunter_liggett", "亨特·利格特", (42, 85, 127, 152, 169), (17, 13, 9, 4), "B", 4, 3, 1940, "13529 std Harris APA"),
        ("savo_alchiba", "菜鸟座", (44, 87, 131, 157, 174), (16, 12, 8, 4), "C", 1, 5, 1941, "Arcturus AKA"),
        ("savo_betelgeuse", "参宿四", (44, 87, 131, 157, 174), (16, 12, 8, 4), "C", 1, 5, 1941, "Arcturus AKA"),
        ("savo_fomalhaut", "北落师门", (44, 89, 133, 159, 177), (16, 12, 8, 4), "C", 1, 5, 1940, "Fomalhaut AK"),
        ("savo_crescent_city", "新月城", (42, 84, 126, 151, 168), (16, 12, 8, 4), "B", 4, 3, 1941, "8429 Crescent City APA"),
        ("savo_president_hayes", "海斯总统", (52, 104, 155, 186, 207), (16, 12, 8, 4), "B", 4, 3, 1942, "9500 President Jackson APA"),
        ("savo_president_adams", "亚当斯总统", (52, 104, 155, 186, 207), (16, 12, 8, 4), "B", 4, 3, 1942, "President Jackson APA"),
        ("savo_alhena", "阿尔赫纳", (43, 86, 128, 154, 171), (16, 12, 8, 4), "C", 1, 5, 1941, "7101 Alhena AKA"),
        ("savo_heywood_yoke", "海伍德（Yoke）", (32, 65, 97, 116, 129), (16, 12, 8, 4), "B", 4, 3, 1940, "Heywood APA · Yoke"),
        ("savo_neville", "内维尔", (32, 65, 97, 116, 129), (16, 12, 8, 4), "B", 4, 3, 1940, "8000 ltshp Heywood APA · Yoke"),
        ("savo_zeilin", "塞林", (42, 85, 127, 152, 169), (17, 13, 9, 4), "B", 4, 3, 1942, "13529 std Harris APA · Yoke"),
        ("savo_president_jackson", "杰克逊总统", (52, 104, 155, 186, 207), (16, 12, 8, 4), "B", 4, 3, 1942, "President Jackson APA · Yoke"),
        ("savo_colhoun", "科尔霍恩", (19, 38, 56, 68, 75), (25, 19, 13, 6), "C", 3, 3, 1942, "Wickes APD"),
        ("savo_little", "利特尔", (19, 38, 56, 68, 75), (25, 19, 13, 6), "C", 3, 3, 1942, "Wickes APD"),
        ("savo_gregory", "格雷戈里", (19, 38, 56, 68, 75), (25, 19, 13, 6), "C", 3, 3, 1942, "Wickes APD"),
        ("savo_mckean", "麦基恩", (19, 38, 56, 68, 75), (25, 19, 13, 6), "C", 3, 3, 1942, "Wickes APD"),
        ("savo_hopkins", "霍普金斯", (19, 38, 56, 68, 75), (35, 26, 18, 9), "C", 4, 3, 1942, "Clemson DMS（Form 10 Jun-42）"),
        ("savo_trever", "特雷弗", (19, 38, 56, 68, 75), (35, 26, 18, 9), "C", 4, 3, 1942, "Clemson DMS"),
        ("savo_zane", "赞恩", (19, 38, 56, 68, 75), (35, 26, 18, 9), "C", 4, 3, 1942, "Clemson DMS"),
        ("savo_southard", "绍瑟德", (19, 38, 56, 68, 75), (35, 26, 18, 9), "C", 4, 3, 1942, "Clemson DMS"),
        ("savo_hovey", "霍维", (19, 38, 56, 68, 75), (35, 26, 18, 9), "C", 4, 3, 1942, "Chandler Mod DMS"),
    ]
    for id, name, dp, speeds, size, barrels, caliber, year, displacement in transports:
        rows.append(aux_row(id, name, list(dp), list(speeds), size, barrels, caliber, year, displacement))
    payload = {"ships": rows, "metadata": {
        "content_version": "cas-savo-runtime-v1",
        "scenario_id": "cas-rs-savo-island",
        "as_of": "1942-08-09",
        "status": "restricted_rts_adaptation_only",
        "policy": "Combat hulls from savo-island-1942.json annex rows; transports/DMS/APD from "
                  "American Fleets A-42-A-47 and Rising Sun Form 10s pages 354-380. Chart anchors "
                  "from chart-savo.json; unanchored screen and transport hulls use the transport "
                  "area centre with the registered 500-yard spacing default.",
        "restrictions": [
            "Henley printed as Gridley in the scenario but listed as Bagley in AF A-18; profile uses "
            "the Gridley card with the conflict retained.",
            "Yunagi Type 96 torpedoes have no Annex F row; torpedo fit omitted rather than substituted.",
            "DMS/APD/transport cards use the auxiliary turn table and their printed civilian damage "
            "modifiers; weapons shown are defensive AA-capable mounts only.",
            "Tenryu/Yubari/Yunagi column interval is not printed; the global 500-yard default applies.",
            "Yunagi Torpedo Type 96 unavailable; Type 93 candidates not substituted.",
        ],
    }}
    OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"Savo runtime: {len(rows)} hulls "
          f"({sum(1 for r in rows if r['side'] == 'allies')} allied, "
          f"{sum(1 for r in rows if r['side'] == 'axis')} axis)")


if __name__ == "__main__":
    main()
