"""Assemble the Empress Augusta Bay period hull file from the registered annex
cards and dated Form 10s. One-off builder; the JSON it writes is the artifact."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load(path):
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


cape = load("data/campaign/period/cape-st-george-1943.json")
esp = load("data/campaign/period/cape-esperance-1942.json")
savo = load("data/campaign/period/savo-island-1942.json")

weapon_models = {}


def take(name, src, key=None):
    weapon_models[name] = src["weapon_models"][key or name]


take("us_6in47_mk16", esp)
take("us_mk30_5in38", cape)
take("jp_3rd_yr_127mm50", cape)
take("jp_20cm50_3rd_yr_type_no2", esp)
take("jp_3rd_yr_type_14cm50", savo)
take("jp_type93_m1_mod1_2", cape)
take("us_mk15_tnt", cape)
take("jp_8th_yr_type_no2", savo, "jp_8th_yr_type_no2_torpedo")


def gun(pdf, printed, shells):
    return {"source": {"document": "emperors_fleet", "pdf_pages": [pdf], "printed_pages": [printed]},
            "shells": shells}


weapon_models["jp_type89_12_7cm40"] = gun(97, "C-1", {
    "COM": {"range_yd": [[0, 4800], [4900, 9600], [9700, 12800], [12900, 16000]],
            "belt": [4, 2, 2, 2], "deck": [None, None, 1, 1], "damage_dp": [16, 13, 12, 10]},
    "HE": {"range_yd": [[0, 4800], [4900, 9600], [9700, 12800], [12900, 16000]],
           "belt": [4, 2, 2, 2], "deck": [None, None, 1, 1], "damage_dp": [18, 15, 14, 12]},
})
weapon_models["jp_41st_yr_15cm50"] = gun(98, "C-2", {
    "COM": {"range_yd": [[0, 5800], [5900, 12000], [12100, 19200], [19300, 24000]],
            "belt": [6, 4, 2, 2], "deck": [None, None, 1, 3], "damage_dp": [22, 16, 14, 12]},
    "HE": {"range_yd": [[0, 5800], [5900, 12000], [12100, 19200], [19300, 24000]],
           "belt": [2, 1, 1, 1], "deck": [None, None, 1, 1], "damage_dp": [22, 18, 16, 14]},
})
weapon_models["jp_type98_8cm60"] = gun(97, "C-1", {
    "SpCOM": {"range_yd": [[0, 4400], [4500, 8900], [9000, 11800], [11900, 14800]],
              "belt": [4, 3, None, 1], "deck": [None, None, 1, 1], "damage_dp": [11, 8, 7, 6]},
    "COM": {"range_yd": [[0, 4400], [4500, 8900], [9000, 11800], [11900, 14800]],
            "belt": [3, 2, None, 1], "deck": [None, None, 1, 1], "damage_dp": [11, 9, 8, 7]},
    "HE": {"range_yd": [[0, 4400], [4500, 8900], [9000, 11800], [11900, 14800]],
           "belt": [1, 1, 0, 0], "deck": [None, None, 0, 0], "damage_dp": [12, 10, 9, 8]},
})
weapon_models["jp_type98_10cm65"] = gun(97, "C-1", {
    "COM": {"range_yd": [[0, 6600], [6700, 13200], [13300, 17600], [17700, 22000]],
            "belt": [6, 1, None, 0], "deck": [None, None, 1, 1], "damage_dp": [17, 14, 12, 11]},
})

maneuver_classes = {
    "A": {"normal_advance_yd": 400, "normal_loss_knots": 2, "hard_advance_yd": 300, "hard_loss_knots": 3},
    "B": {"normal_advance_yd": 300, "normal_loss_knots": 2, "hard_advance_yd": 200, "hard_loss_knots": 3},
    "C": {"normal_advance_yd": 300, "normal_loss_knots": 1, "hard_advance_yd": 200, "hard_loss_knots": 2},
    "D": {"normal_advance_yd": 200, "normal_loss_knots": 1, "hard_advance_yd": 100, "hard_loss_knots": 2},
}

profiles = {
    "cleveland_1943": {
        "class": "Cleveland", "side": "allies", "kind": "CL",
        "source": {"document": "american_fleets", "pdf_pages": [18], "printed_pages": ["A-15"]},
        "class_in_service_year": 1942, "crew": 1285, "std_displacement_tons": 10000,
        "size": "B", "armor_rating": "13/6", "gunnery_standard": 4, "turn_class": "B",
        "accel_decel_knots_per_turn": [10, 12, 5],
        "damage_speed_rows_dp_knots": [[0, 33], [84, 25], [168, 16], [252, 8], [302, 0], [336, "Sunk"]],
        "main_gun": "us_6in47_mk16",
        "gun_mounts": [["F", 3], ["F", 3], ["A", 3], ["A", 3]],
        "secondary_gun": {"model": "us_mk30_5in38",
                          "mounts": [["F", 2], ["P", 2], ["P", 2], ["S", 2], ["S", 2], ["A", 2]],
                          "directors": ["Mk4 fwd", "Mk4 aft"]},
        "torpedo_mounts": None,
        "radar_confirmed": ["us_sg", "us_sc", "us_mk3_fc", "us_mk4_fd"],
        "notes": "CL 55-58 aluminum superstructure, special damage modifier -15%; class DP row applies (Form 10 prints the CL 66+ 396 row: conflict).",
    },
    "fletcher_1943": {
        "class": "Fletcher", "side": "allies", "kind": "DD",
        "source": {"document": "american_fleets", "pdf_pages": [20], "printed_pages": ["A-17"]},
        "class_in_service_year": 1942, "crew": 273, "std_displacement_tons": 2200,
        "size": "C", "armor_rating": "0", "gunnery_standard": 4, "turn_class": "A",
        "accel_decel_knots_per_turn": [12, 6, 15],
        "damage_speed_rows_dp_knots": [[0, 37], [36, 28], [72, 18], [108, 9], [130, 0], [144, "Sunk"]],
        "main_gun": "us_mk30_5in38",
        "gun_mounts": [["F", 1], ["F", 1], ["P&S", 1], ["A", 1], ["A", 1]],
        "secondary_gun": None,
        "torpedo_mounts": {"model": "us_mk15_tnt", "arc": "P&S",
                           "loaded_tubes_per_mount": [5, 5], "reserve_per_mount": [0, 0],
                           "reload_seconds": None},
        "radar_confirmed": ["us_sg", "us_sc2", "us_mk4_fd"],
        "notes": "Fletcher class appendix; no torpedo reload.",
    },
    "myoko_1940": {
        "class": "Myoko (1940 refit)", "side": "axis", "kind": "CA",
        "source": {"document": "emperors_fleet", "pdf_pages": [15, 18], "printed_pages": ["A-12", "A-15"]},
        "class_in_service_year": 1940, "crew": 920, "std_displacement_tons": 13000,
        "size": "B", "armor_rating": "7/5", "gunnery_standard": 4, "turn_class": "B",
        "accel_decel_knots_per_turn": [10, 10, 5],
        "damage_speed_rows_dp_knots": [[0, 33], [118, 25], [236, 16], [353, 8], [424, 0], [471, "Sunk"]],
        "main_gun": "jp_20cm50_3rd_yr_type_no2",
        "gun_mounts": [["F", 2], ["F", 2], ["P&S", 2], ["P&S", 2], ["A", 2]],
        "secondary_gun": {"model": "jp_type89_12_7cm40",
                          "mounts": [["P", 2], ["P", 2], ["S", 2], ["S", 2]],
                          "directors": ["Port secondary director", "Stbd secondary director"]},
        "torpedo_mounts": {"model": "jp_type93_m1_mod1_2", "arc": "P&S",
                           "loaded_tubes_per_mount": [4, 4], "reserve_per_mount": [4, 4],
                           "reload_seconds": 360},
        "radar_confirmed": ["jp_type21"],
        "notes": "Form 10 Jun-Jul 43: DP 471, speed 33, Type 21; class card prints 428/35 (Tone row) as a conflict.",
    },
    "sendai_1943": {
        "class": "Sendai (May-Jun 43 refit)", "side": "axis", "kind": "CL",
        "source": {"document": "emperors_fleet", "pdf_pages": [21, 22], "printed_pages": ["A-18", "A-19"]},
        "class_in_service_year": 1924, "crew": 453, "std_displacement_tons": 5195,
        "size": "C", "armor_rating": "4/2", "gunnery_standard": 3, "turn_class": "B",
        "accel_decel_knots_per_turn": [10, 10, 5],
        "damage_speed_rows_dp_knots": [[0, 35], [54, 26], [109, 18], [163, 9], [195, 0], [217, "Sunk"]],
        "main_gun": "jp_3rd_yr_type_14cm50",
        "gun_mounts": [["F", 1], ["P&S", 1], ["PW", 1], ["SW", 1], ["P&S", 1], ["A", 1]],
        "secondary_gun": {"model": None, "mounts": [["P&S", 1]], "directors": [],
                          "note": "3rd Yr Type 8cm/40 AA not registered for surface fire."},
        "torpedo_mounts": {"model": "jp_8th_yr_type_no2", "arc": "P&S",
                           "loaded_tubes_per_mount": [2, 2, 2, 2], "reserve_per_mount": [2, 2, 2, 2],
                           "reload_seconds": 900},
        "radar_confirmed": ["jp_type21"],
        "notes": "May-Jun 43: No.5 14cm removed, 10x25mm added, Type 21, DC rails; 8th Year torpedoes with 2 reloads per mount (15 min).",
    },
    "agano_1943": {
        "class": "Agano", "side": "axis", "kind": "CL",
        "source": {"document": "emperors_fleet", "pdf_pages": [20], "printed_pages": ["A-17"]},
        "class_in_service_year": 1942, "crew": 730, "std_displacement_tons": 6652,
        "size": "B", "armor_rating": "4/2", "gunnery_standard": 4, "turn_class": "B",
        "accel_decel_knots_per_turn": [10, 10, 5],
        "damage_speed_rows_dp_knots": [[0, 35], [76, 26], [151, 18], [227, 9], [272, 0], [302, "Sunk"]],
        "main_gun": "jp_41st_yr_15cm50",
        "gun_mounts": [["F", 2], ["F", 2], ["A", 2]],
        "secondary_gun": {"model": "jp_type98_8cm60", "mounts": [["P", 2], ["S", 2]], "directors": []},
        "torpedo_mounts": {"model": "jp_type93_m1_mod1_2", "arc": "P&S",
                           "loaded_tubes_per_mount": [4, 4], "reserve_per_mount": [0, 0],
                           "reload_seconds": None},
        "radar_confirmed": ["jp_type21"],
        "notes": "Jun 43: Type 21, ESM; Jul 43: 25mm fit. No torpedo reload printed.",
    },
    "kagero_1943": {
        "class": "Kagero", "side": "axis", "kind": "DD",
        "source": {"document": "emperors_fleet", "pdf_pages": [28], "printed_pages": ["A-9"]},
        "class_in_service_year": 1939, "crew": 240, "std_displacement_tons": 2065,
        "size": "C", "armor_rating": "0", "gunnery_standard": 4, "turn_class": "A",
        "accel_decel_knots_per_turn": [12, 6, 15],
        "damage_speed_rows_dp_knots": [[0, 35], [35, 26], [69, 18], [104, 9], [124, 0], [138, "Sunk"]],
        "main_gun": "jp_3rd_yr_127mm50",
        "gun_mounts": [["F", 2], ["A", 2], ["A", 2]],
        "secondary_gun": None,
        "torpedo_mounts": {"model": "jp_type93_m1_mod1_2", "arc": "P&S",
                           "loaded_tubes_per_mount": [4, 4], "reserve_per_mount": [4, 4],
                           "reload_seconds": 360},
        "radar_confirmed": [],
        "notes": "May-Aug 43 fit; Form 10 prints no radar for Hatsukaze at this date.",
    },
    "shiratsuyu_1943": {
        "class": "Shiratsuyu", "side": "axis", "kind": "DD",
        "source": {"document": "emperors_fleet", "pdf_pages": [28], "printed_pages": ["A-22"]},
        "class_in_service_year": 1936, "crew": 180, "std_displacement_tons": 1712,
        "size": "C", "armor_rating": "0", "gunnery_standard": 4, "turn_class": "A",
        "accel_decel_knots_per_turn": [12, 6, 15],
        "damage_speed_rows_dp_knots": [[0, 34], [31, 26], [61, 17], [92, 9], [110, 0], [122, "Sunk"]],
        "main_gun": "jp_3rd_yr_127mm50",
        "gun_mounts": [["F", 1], ["A", 1], ["P", 1], ["S", 1], ["P&S", 1]],
        "secondary_gun": None,
        "torpedo_mounts": {"model": "jp_type93_m1_mod1_2", "arc": "P&S",
                           "loaded_tubes_per_mount": [4, 4], "reserve_per_mount": [4, 4],
                           "reload_seconds": 360},
        "radar_confirmed": [],
        "notes": "Feb-Mar 43 Shigure / Nov 42-Mar 43 Shiratsuyu; no radar printed.",
    },
    "yugumo_1943": {
        "class": "Yugumo", "side": "axis", "kind": "DD",
        "source": {"document": "emperors_fleet", "pdf_pages": [27], "printed_pages": ["A-24"]},
        "class_in_service_year": 1941, "crew": 228, "std_displacement_tons": 2110,
        "size": "C", "armor_rating": "0", "gunnery_standard": 4, "turn_class": "A",
        "accel_decel_knots_per_turn": [12, 6, 15],
        "damage_speed_rows_dp_knots": [[0, 35], [35, 26], [70, 18], [105, 9], [124, 0], [138, "Sunk"]],
        "main_gun": "jp_3rd_yr_127mm50",
        "gun_mounts": [["F", 2], ["A", 2], ["A", 2]],
        "secondary_gun": None,
        "torpedo_mounts": {"model": "jp_type93_m1_mod1_2", "arc": "P&S",
                           "loaded_tubes_per_mount": [4, 4], "reserve_per_mount": [4, 4],
                           "reload_seconds": 360},
        "radar_confirmed": [],
        "notes": "Mar-Apr 43 Naganami; no radar printed.",
    },
    "akizuki_1943": {
        "class": "Akizuki", "side": "axis", "kind": "DD",
        "source": {"document": "emperors_fleet", "pdf_pages": [27], "printed_pages": ["A-53"]},
        "class_in_service_year": 1942, "crew": 300, "std_displacement_tons": 2744,
        "size": "C", "armor_rating": "0", "gunnery_standard": 4, "turn_class": "A",
        "accel_decel_knots_per_turn": [12, 6, 15],
        "damage_speed_rows_dp_knots": [[0, 33], [42, 25], [84, 16], [125, 8], [150, 0], [167, "Sunk"]],
        "main_gun": "jp_type98_10cm65",
        "gun_mounts": [["F", 2], ["F", 2], ["A", 2], ["A", 2]],
        "secondary_gun": None,
        "torpedo_mounts": {"model": "jp_type93_m1_mod1_2", "arc": "P&S",
                           "loaded_tubes_per_mount": [4], "reserve_per_mount": [4],
                           "reload_seconds": 360},
        "radar_confirmed": ["jp_type21"],
        "notes": "May 43 Wakatsuki; Type 21 printed.",
    },
}


def inst(profile, pages, radars):
    return {"profile": profile,
            "form10": {"document": "rising_sun_form10", "pdf_pages": pages, "printed_pages": pages},
            "radar_confirmed": radars}


instances = {
    "montpelier": inst("cleveland_1943", [259], ["us_sg", "us_sc", "us_mk4_fd", "us_mk3_fc"]),
    "cleveland": inst("cleveland_1943", [255], ["us_sg", "us_sc", "us_mk4_fd", "us_mk3_fc"]),
    "columbia": inst("cleveland_1943", [257], ["us_sg", "us_sc", "us_mk4_fd", "us_mk3_fc"]),
    "denver": inst("cleveland_1943", [258], ["us_sg", "us_sc", "us_mk4_fd", "us_mk3_fc"]),
    "ausburne": inst("fletcher_1943", [270], ["us_sg", "us_sc2", "us_mk4_fd"]),
    "dyson": inst("fletcher_1943", [276], ["us_sg", "us_sc2", "us_mk4_fd"]),
    "stanly": inst("fletcher_1943", [285], ["us_sg", "us_sc2", "us_mk4_fd"]),
    "claxton": inst("fletcher_1943", [272], ["us_sg", "us_sc2", "us_mk4_fd"]),
    "spence": inst("fletcher_1943", [284], ["us_sg", "us_sc2", "us_mk4_fd"]),
    "thatcher": inst("fletcher_1943", [287], ["us_sg", "us_sc2", "us_mk4_fd"]),
    "converse": inst("fletcher_1943", [273], ["us_sg", "us_sc2", "us_mk4_fd"]),
    "foote": inst("fletcher_1943", [278], ["us_sg", "us_sc2", "us_mk4_fd"]),
    "myoko": inst("myoko_1940", [61], ["jp_type21"]),
    "haguro": inst("myoko_1940", [62, 63], ["jp_type21"]),
    "sendai": inst("sendai_1943", [74], ["jp_type21"]),
    "agano": inst("agano_1943", [68], ["jp_type21"]),
    "shigure": inst("shiratsuyu_1943", [133], []),
    "samidare": inst("shiratsuyu_1943", [131], []),
    "shiratsuyu": inst("shiratsuyu_1943", [135], []),
    "hatsukaze": inst("kagero_1943", [102], []),
    "wakatsuki": inst("akizuki_1943", [85], ["jp_type21"]),
    "naganami": inst("yugumo_1943", [91], []),
}

out = {
    "schema_version": 1,
    "content_version": "cas-empress-augusta-bay-1943-hulls-v1",
    "scenario_id": "cas-rs-empress-augusta-bay",
    "as_of": "1943-11-02",
    "status": "source_data_not_launchable",
    "policy": "Scenario exceptions, then Fifth Edition rules, then annex class and dated refit entries. Legacy dated Form 10 is corroboration, with differences retained explicitly. Nulls and unresolved alternatives are not executable.",
    "mount_sector_source": {"document": "rising_sun_5e", "pdf_pages": [90], "printed_pages": [90]},
    "maneuver_source": {"document": "rising_sun_5e", "pdf_pages": [90], "printed_pages": [90]},
    "maneuver_classes": maneuver_classes,
    "weapon_models": weapon_models,
    "profiles": profiles,
    "instances": instances,
    "conflicts": [
        {"id": "cleveland-dp-row", "status": "unresolved",
         "detail": "Class card A-15 prints DP 336 for CL 55-65 and 396 for CL 66+; the Montpelier/Cleveland/Columbia/Denver Form 10s print the 396 row (0/99/198/297/356/396). The profile uses the class row (336) for CL 55-58; the dated form difference is retained."},
        {"id": "myoko-dp-speed", "status": "unresolved",
         "detail": "Class card A-15 prints 428 DP and 35 knots; the Jun-Jul 43 Form 10 prints 471 DP and 33 knots. The profile uses the dated Form 10 (471/33); the class-card difference is retained."},
        {"id": "sendai-torpedo-model", "status": "unresolved",
         "detail": "Sendai May-Jun 43 Form 10 still prints 8th Year Type No.2 torpedoes with two reloads per mount (15 min), not Type 93; the 1943 refit remarks do not change the torpedo model."},
        {"id": "sendai-secondary", "status": "unresolved",
         "detail": "3rd Yr Type 8cm/40 secondary is not registered as a surface-fire weapon model; the profile leaves secondary_gun.model null."},
        {"id": "agano-dp", "status": "unresolved",
         "detail": "Class-card table near A-17 prints 346; the Agano Jun-Jul 43 Form 10 prints 302. The profile uses the dated Form 10."},
        {"id": "floatplanes", "status": "unresolved",
         "detail": "Two F1M2 Petes are airborne at the start; aviation search and flares are outside the current surface scope and are not executable."},
        {"id": "multi-column", "status": "unresolved",
         "detail": "The scenario has three columns per side; the current engine deploys one fleet per side with per-ship follow/sync. Multi-column deployment and the Cape Torokina bearing rule are not yet executable."},
    ],
}

path = ROOT / "data/campaign/period/empress-augusta-bay-1943.json"
path.write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
print("wrote", path, len(weapon_models), "weapon models,", len(profiles), "profiles,", len(instances), "instances")
