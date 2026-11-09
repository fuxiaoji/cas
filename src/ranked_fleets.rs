use crate::{model::*, realtime, world::World};
use serde_json::{json, Map, Value};
use std::{collections::BTreeSet, sync::OnceLock};

const POINTS_VERSION: &str = "cas-points-surface-v1";
pub(crate) const VARIANT: &str = "personal-duel";

// Point-table convention for CAS RTS multiplayer. These coefficients are a
// product-balance convention, not a table value from the printed rulebook;
// the frozen manifest at data/rules/cas-competitive-points-v1.json is the
// published copy of the same calculation. Ranges, penetration, gunnery
// standard and torpedo speed/ranges are deliberately not separate terms yet;
// see `docs/` evidence for the audit.
const POINT_UNIT: u32 = 25;
const DP_WEIGHT: f64 = 1.5;
const KNOT_WEIGHT: f64 = 5.;
const GUN_BARREL_DAMAGE_WEIGHT: f64 = 2.;
const TORPEDO_TUBE_WARHEAD_WEIGHT: f64 = 0.12;
const ARMOR_WEIGHT: f64 = 5.;
const TORPEDO_PROTECTION_WEIGHT: f64 = 0.8;

#[derive(Clone)]
struct Profile {
    id: &'static str,
    source_class: &'static str,
    name: &'static str,
    source: &'static str,
}

const LEGACY_PROFILES: &[Profile] = &[
    // `source_class` is the loaded card ID. When it differs from `id`, the
    // catalog identity reuses a same-class Form 10 card; the point value is
    // therefore a class-card proxy, not a per-identity value. The aliases are
    // called out in the source string and in the point audit artifact.
    Profile {
        id: "IBS-U-USN-FLETCHER",
        source_class: "fletcher",
        name: "弗莱彻",
        source: "序章时期包／弗莱彻舰表与具名 Form 10",
    },
    Profile {
        id: "IBS-U-USN-PERKINS",
        source_class: "IBS-U-USN-PERKINS",
        name: "帕金斯",
        source: "序章时期包／马汉级与帕金斯 Form 10",
    },
    Profile {
        id: "IBS-U-USN-MAURY",
        source_class: "IBS-U-USN-MAURY",
        name: "莫里",
        source: "序章时期包／格里德利级与莫里 Form 10",
    },
    Profile {
        id: "IBS-U-USN-DRAYTON",
        source_class: "IBS-U-USN-DRAYTON",
        name: "德雷顿",
        source: "序章时期包／马汉级与德雷顿 Form 10",
    },
    Profile {
        id: "IBS-U-USN-LAMSON",
        source_class: "IBS-U-USN-LAMSON",
        name: "拉姆森",
        source: "序章时期包／马汉级与拉姆森 Form 10",
    },
    Profile {
        id: "IBS-U-IJN-KAGERO",
        source_class: "kagero",
        name: "阳炎",
        source: "首发时期包／日本舰表 PDF 28、97、108",
    },
    Profile {
        id: "IBS-U-IJN-SENDAI",
        source_class: "sendai",
        name: "川内",
        source: "首发时期包／日本舰表 PDF 21–22、97、108",
    },
    Profile {
        id: "IBS-U-USN-UNNAMED-T01-R03",
        source_class: "north-carolina",
        name: "北卡罗来纳",
        source: "序章时期包／美国舰表 PDF 8、109",
    },
    Profile {
        id: "IBS-U-USN-WASHINGTON",
        source_class: "north-carolina",
        name: "华盛顿",
        source: "序章时期包／美国舰表 PDF 8、109",
    },
    Profile {
        id: "IBS-U-IJN-ERMA-YAMATO",
        source_class: "yamato",
        name: "大和",
        source: "序章时期包／日本舰表 PDF 7、98",
    },
    // Two more Fletchers/Mahans cannot be invented from a class card; these
    // catalog identities reuse the exact same-class prologue card and are
    // labelled here so the 3000-point escort rule can field six destroyers.
    Profile {
        id: "IBS-U-USN-UNNAMED-T01-R51",
        source_class: "IBS-U-USN-PERKINS",
        name: "邓拉普",
        source: "马汉级同型卡／帕金斯 Form 10（1942 年配置）",
    },
    Profile {
        id: "IBS-U-USN-UNNAMED-T01-R52",
        source_class: "IBS-U-USN-MAURY",
        name: "格里德利",
        source: "格里德利级同型卡／莫里 Form 10（1942 年配置）",
    },
    Profile {
        id: "IBS-U-IJN-SHIRATSUYU",
        source_class: "shiratsuyu",
        name: "白露",
        source: "首发时期包／日本舰表 A-25–A-26、C-1、F-1",
    },
    Profile {
        id: "IBS-U-IJN-YUGUMO",
        source_class: "yugumo",
        name: "夕云",
        source: "首发时期包／日本舰表 A-24、C-1、F-1",
    },
    Profile {
        id: "IBS-U-IJN-AKIZUKI",
        source_class: "akizuki",
        name: "秋月",
        source: "首发时期包／日本舰表 A-24、C-1、F-1",
    },
    Profile {
        id: "IBS-U-IJN-FUBUKI",
        source_class: "fubuki_1936_refit",
        name: "吹雪",
        source: "首发时期包／改装吹雪级 A-27、C-1、F-1",
    },
    Profile {
        id: "IBS-U-IJN-HATSUYUKI",
        source_class: "fubuki_1936_refit",
        name: "初雪",
        source: "首发时期包／改装吹雪级 A-27、C-1、F-1",
    },
    // Allied identities from data/ships/playable-cards.json (playable=true).
    Profile {
        id: "IBS-U-USN-VINCENNES",
        source_class: "new_orleans_1942",
        name: "文森斯",
        source: "provisional（待平衡复核）class_proxy：新奥尔良级类卡（Form 10 245 等）；period 逐舰卡：savo-runtime.json savo_vincennes/us_new_orleans_ca",
    },
    Profile {
        id: "IBS-U-USN-NEW-ORLEANS",
        source_class: "new_orleans_1942",
        name: "新奥尔良",
        source: "provisional（待平衡复核）class_proxy：新奥尔良级类卡（Form 10 245 等）；period 逐舰卡：tassafaronga-runtime.json tass_new_orleans/new_orleans_1942",
    },
    Profile {
        id: "IBS-U-USN-SAN-FRANCISCO",
        source_class: "new_orleans_1942",
        name: "旧金山",
        source: "provisional（待平衡复核）class_proxy：新奥尔良级类卡（Form 10 245 等）；period 逐舰卡：cape-esperance-1942.json san_francisco/new_orleans_1942（Form 10 p.245）",
    },
    Profile {
        id: "IBS-U-USN-QUINCY",
        source_class: "new_orleans_1942",
        name: "昆西",
        source: "provisional（待平衡复核）class_proxy：新奥尔良级类卡（Form 10 245 等）；period 逐舰卡：savo-runtime.json savo_quincy/us_new_orleans_ca",
    },
    Profile {
        id: "IBS-U-USN-MINNEAPOLIS",
        source_class: "new_orleans_1942",
        name: "明尼阿波里斯",
        source: "provisional（待平衡复核）class_proxy：新奥尔良级类卡（Form 10 245 等）；period 逐舰卡：tassafaronga-runtime.json tass_minneapolis/new_orleans_1942",
    },
    Profile {
        id: "IBS-U-USN-ASTORIA",
        source_class: "new_orleans_1942",
        name: "阿斯托里亚",
        source: "provisional（待平衡复核）class_proxy：新奥尔良级类卡（Form 10 245 等）；period 逐舰卡：savo-runtime.json savo_astoria/us_new_orleans_ca",
    },
    Profile {
        id: "IBS-U-USN-NORTHAMPTON",
        source_class: "northampton_1942",
        name: "北安普敦",
        source: "provisional（待平衡复核）class_proxy：北安普敦级类卡（Form 10 249 组）；period 逐舰卡：tassafaronga-runtime.json tass_northampton/northampton_1942",
    },
    Profile {
        id: "IBS-U-USN-UNNAMED-T01-R12",
        source_class: "northampton_1942",
        name: "芝加哥",
        source: "provisional（待平衡复核）class_proxy：北安普敦级类卡（Form 10 249 组）；period 逐舰卡：savo-runtime.json savo_chicago/us_northampton_ca",
    },
    Profile {
        id: "IBS-U-USN-PENSACOLA",
        source_class: "salt_lake_city_1942",
        name: "彭萨科拉",
        source: "provisional（待平衡复核）period_named：彭萨科拉级无类卡；stage0 盐湖城卡即本级 1942 装填（Esperance pensacola_1942，Form 10 254：372 DP、32 节、10×8in/55）；period 逐舰卡：tassafaronga-runtime.json tass_pensacola/pensacola_1942",
    },
    Profile {
        id: "IBS-U-USN-SALT-LAKE-CITY",
        source_class: "salt_lake_city_1942",
        name: "盐湖城",
        source: "provisional（待平衡复核）exact：同名具名卡（stage0）；period 档案 Form 10 p.254；period 逐舰卡：cape-esperance-1942.json salt_lake_city/pensacola_1942（Form 10 p.254）",
    },
    Profile {
        id: "IBS-U-USN-ST-LOUIS",
        source_class: "brooklyn_second_group_1942",
        name: "圣路易斯",
        source: "provisional（待平衡复核）class_proxy：圣路易斯级不在映射表；period 档案 A-16 明确该卡为 Brooklyn second group (St. Louis, Helena)，Esperance 运行时把海伦娜绑定到该 profile（Form 10 263），Kula 运行时把海伦娜/圣路易斯绑定到 brooklyn_2；period 逐舰卡：kula-runtime.json kula-st-louis/brooklyn_2（Form 10 p.264）",
    },
    Profile {
        id: "IBS-U-USN-HELENA",
        source_class: "brooklyn_second_group_1942",
        name: "海伦娜",
        source: "provisional（待平衡复核）class_proxy：圣路易斯级不在映射表；period 档案 A-16 明确该卡为 Brooklyn second group (St. Louis, Helena)，Esperance 运行时把海伦娜绑定到该 profile（Form 10 263），Kula 运行时把海伦娜/圣路易斯绑定到 brooklyn_2；period 逐舰卡：kula-runtime.json kula-helena/brooklyn_2（Form 10 p.263）",
    },
    Profile {
        id: "IBS-U-USN-UNNAMED-T01-R29",
        source_class: "cleveland_empress",
        name: "丹弗",
        source: "provisional（待平衡复核）class_proxy：皇后湾 1943-11 期克利夫兰级卡（与 cleveland 同源 US A-15/C-2；Empress 期按 cleveland_empress 登记）；period 逐舰卡：empress-augusta-bay-1943.json denver/cleveland_1943（Form 10 p.258）",
    },
    Profile {
        id: "IBS-U-USN-UNNAMED-T01-R26",
        source_class: "cleveland_empress",
        name: "克利夫兰",
        source: "provisional（待平衡复核）class_proxy：皇后湾 1943-11 期克利夫兰级卡（与 cleveland 同源 US A-15/C-2；Empress 期按 cleveland_empress 登记）；period 逐舰卡：empress-augusta-bay-1943.json cleveland/cleveland_1943（Form 10 p.255）",
    },
    Profile {
        id: "IBS-U-USN-UNNAMED-T01-R27",
        source_class: "cleveland_empress",
        name: "哥伦比亚",
        source: "provisional（待平衡复核）class_proxy：皇后湾 1943-11 期克利夫兰级卡（与 cleveland 同源 US A-15/C-2；Empress 期按 cleveland_empress 登记）；period 逐舰卡：empress-augusta-bay-1943.json columbia/cleveland_1943（Form 10 p.257）",
    },
    Profile {
        id: "IBS-U-USN-UNNAMED-T01-R28",
        source_class: "cleveland_empress",
        name: "蒙彼利埃",
        source: "provisional（待平衡复核）class_proxy：皇后湾 1943-11 期克利夫兰级卡（与 cleveland 同源 US A-15/C-2；Empress 期按 cleveland_empress 登记）；period 逐舰卡：empress-augusta-bay-1943.json montpelier/cleveland_1943（Form 10 p.259）",
    },
    Profile {
        id: "IBS-U-USN-CUSHING",
        source_class: "IBS-U-USN-PERKINS",
        name: "库欣",
        source: "provisional（待平衡复核）period_named：马汉级无类卡，借时期包帕金斯 Form 10（1942-01/02，p.332）",
    },
    Profile {
        id: "IBS-U-USN-PRESTON",
        source_class: "IBS-U-USN-PERKINS",
        name: "普雷斯顿",
        source: "provisional（待平衡复核）period_named：马汉级无类卡，借时期包帕金斯 Form 10（1942-01/02，p.332）",
    },
    Profile {
        id: "IBS-U-USN-CLAXTON",
        source_class: "fletcher",
        name: "克拉克斯顿",
        source: "provisional（待平衡复核）class_proxy：弗莱彻级类卡（stage0；炮 US C-2；1942 配置）；period 逐舰卡：cape-runtime.json claxton/fletcher_1943（Form 10 p.272）",
    },
    Profile {
        id: "IBS-U-USN-OBANNON",
        source_class: "fletcher",
        name: "奥班农",
        source: "provisional（待平衡复核）class_proxy：弗莱彻级类卡（stage0；炮 US C-2；1942 配置）；period 逐舰卡：kula-runtime.json kula-obannon/fletcher（Form 10 p.282）",
    },
    Profile {
        id: "IBS-U-USN-NICHOLAS",
        source_class: "fletcher",
        name: "尼古拉斯",
        source: "provisional（待平衡复核）class_proxy：弗莱彻级类卡（stage0；炮 US C-2；1942 配置）；period 逐舰卡：kula-runtime.json kula-nicholas/fletcher（Form 10 p.281）",
    },
    Profile {
        id: "IBS-U-USN-CONVERSE",
        source_class: "fletcher",
        name: "康弗斯",
        source: "provisional（待平衡复核）class_proxy：弗莱彻级类卡（stage0；炮 US C-2；1942 配置）；period 逐舰卡：cape-runtime.json converse/fletcher_1943（Form 10 p.273）",
    },
    Profile {
        id: "IBS-U-USN-DYSON",
        source_class: "fletcher",
        name: "戴森",
        source: "provisional（待平衡复核）class_proxy：弗莱彻级类卡（stage0；炮 US C-2；1942 配置）；period 逐舰卡：cape-runtime.json dyson/fletcher_1943（Form 10 p.276）",
    },
    Profile {
        id: "IBS-U-USN-LARDNER",
        source_class: "fletcher",
        name: "拉德纳",
        source: "provisional（待平衡复核）class_proxy：弗莱彻级类卡（stage0；炮 US C-2；1942 配置）；period 逐舰卡：tassafaronga-runtime.json tass_lardner/bristol_1942",
    },
    Profile {
        id: "IBS-U-USN-THATCHER",
        source_class: "fletcher",
        name: "撒切尔",
        source: "provisional（待平衡复核）class_proxy：弗莱彻级类卡（stage0；炮 US C-2；1942 配置）；period 逐舰卡：empress-augusta-bay-1943.json thatcher/fletcher_1943（Form 10 p.287）",
    },
    Profile {
        id: "IBS-U-USN-STANLY",
        source_class: "fletcher",
        name: "斯坦立",
        source: "provisional（待平衡复核）class_proxy：弗莱彻级类卡（stage0；炮 US C-2；1942 配置）；period 逐舰卡：empress-augusta-bay-1943.json stanly/fletcher_1943（Form 10 p.285）",
    },
    Profile {
        id: "IBS-U-USN-SPENCE",
        source_class: "fletcher",
        name: "斯彭斯",
        source: "provisional（待平衡复核）class_proxy：弗莱彻级类卡（stage0；炮 US C-2；1942 配置）；period 逐舰卡：cape-runtime.json spence/fletcher_1943（Form 10 p.284）",
    },
    Profile {
        id: "IBS-U-USN-CF-AUSBURNE",
        source_class: "fletcher",
        name: "查尔斯·奥斯本",
        source: "provisional（待平衡复核）class_proxy：弗莱彻级类卡（stage0；炮 US C-2；1942 配置）；crosswalk 未登记舰级，舰级由 period 档案确认；period 逐舰卡：cape-runtime.json ausburne/fletcher_1943（Form 10 p.270）",
    },
    Profile {
        id: "IBS-U-USN-TAYLOR",
        source_class: "fletcher",
        name: "泰勒",
        source: "provisional（待平衡复核）class_proxy：弗莱彻级类卡（stage0；炮 US C-2；1942 配置）；period 逐舰卡：horaniu-1943.json taylor/fletcher_1943（Form 10 p.286）",
    },
    Profile {
        id: "IBS-U-USN-FOOTE",
        source_class: "fletcher",
        name: "福特",
        source: "provisional（待平衡复核）class_proxy：弗莱彻级类卡（stage0；炮 US C-2；1942 配置）；crosswalk 未登记舰级，舰级由 period 档案确认；period 逐舰卡：empress-augusta-bay-1943.json foote/fletcher_1943（Form 10 p.278）",
    },
    Profile {
        id: "IBS-U-USN-JENKINS",
        source_class: "fletcher",
        name: "詹金斯",
        source: "provisional（待平衡复核）class_proxy：弗莱彻级类卡（stage0；炮 US C-2；1942 配置）；period 逐舰卡：kula-runtime.json kula-jenkins/fletcher（Form 10 p.279）",
    },
    Profile {
        id: "IBS-U-USN-CHEVALIER",
        source_class: "fletcher",
        name: "谢伐利埃",
        source: "provisional（待平衡复核）class_proxy：弗莱彻级类卡（stage0；炮 US C-2；1942 配置）；crosswalk 未登记舰级，舰级由 period 档案确认；period 逐舰卡：horaniu-1943.json chevalier/fletcher_1943（Form 10 p.271）",
    },
    Profile {
        id: "IBS-U-USN-RADFORD",
        source_class: "fletcher",
        name: "雷德福德",
        source: "provisional（待平衡复核）class_proxy：弗莱彻级类卡（stage0；炮 US C-2；1942 配置）；period 逐舰卡：kula-runtime.json kula-radford/fletcher（Form 10 p.283）",
    },
    // Axis identities from data/ships/playable-cards.json (playable=true).
    Profile {
        id: "IBS-U-IJN-AOBA",
        source_class: "aoba_1938",
        name: "青叶",
        source: "provisional（待平衡复核）class_proxy：青叶级（1938 改装）类卡（JP A-14/C-1）；period 逐舰卡：cape-esperance-1942.json aoba/aoba_1938（Form 10 p.46）",
    },
    Profile {
        id: "IBS-U-IJN-KAKO-I",
        source_class: "furutaka_1937",
        name: "加古(I)",
        source: "provisional（待平衡复核）class_proxy：古鹰级（1937 改装）类卡（JP A-14/C-1）；舰级由 period 档案确认（crosswalk 标签为 slug「ijn-kako-ca」）；period 逐舰卡：savo-runtime.json savo_kako/jp_furutaka_1937_ca",
    },
    Profile {
        id: "IBS-U-IJN-FURUTAKA",
        source_class: "furutaka_1937",
        name: "古鹰",
        source: "provisional（待平衡复核）class_proxy：古鹰级（1937 改装）类卡（JP A-14/C-1）；period 逐舰卡：cape-esperance-1942.json furutaka/furutaka_1937（Form 10 p.53）",
    },
    Profile {
        id: "IBS-U-IJN-KINUGASA",
        source_class: "kinugasa_1938",
        name: "衣笠",
        source: "provisional（待平衡复核）exact：同名具名卡（stage0）；period 逐舰卡：cape-esperance-1942.json kinugasa/aoba_1938（Form 10 p.47）",
    },
    Profile {
        id: "IBS-U-IJN-MYOKO",
        source_class: "myoko",
        name: "妙高",
        source: "provisional（待平衡复核）class_proxy：妙高级类卡（JP A-12/C-1）；period 逐舰卡：empress-augusta-bay-1943.json myoko/myoko_1940（Form 10 p.61）",
    },
    Profile {
        id: "IBS-U-IJN-HAGURO",
        source_class: "myoko",
        name: "羽黑",
        source: "provisional（待平衡复核）class_proxy：妙高级类卡（JP A-12/C-1）；period 逐舰卡：empress-augusta-bay-1943.json haguro/myoko_1940（Form 10 p.62）",
    },
    Profile {
        id: "IBS-U-IJN-AGANO",
        source_class: "agano",
        name: "阿贺野",
        source: "provisional（待平衡复核）class_proxy：阿贺野级类卡（JP A-17/C-1）；period 逐舰卡：empress-augusta-bay-1943.json agano/agano_1943（Form 10 p.68）",
    },
    Profile {
        id: "IBS-U-IJN-NIIZUKI",
        source_class: "akizuki",
        name: "新月",
        source: "provisional（待平衡复核）class_proxy：秋月级类卡（JP A-53/C-1）；period 逐舰卡：kula-runtime.json kula-niizuki/akizuki（Form 10 p.83）",
    },
    Profile {
        id: "IBS-U-IJN-TERUZUKI",
        source_class: "akizuki",
        name: "照月",
        source: "provisional（待平衡复核）class_proxy：秋月级类卡（JP A-53/C-1）",
    },
    Profile {
        id: "IBS-U-IJN-WAKATSUKI",
        source_class: "akizuki",
        name: "若月",
        source: "provisional（待平衡复核）class_proxy：秋月级类卡（JP A-53/C-1）；period 逐舰卡：empress-augusta-bay-1943.json wakatsuki/akizuki_1943（Form 10 p.85）",
    },
    Profile {
        id: "IBS-U-IJN-YUGIRI",
        source_class: "fubuki_1936_refit",
        name: "夕雾",
        source: "provisional（待平衡复核）class_proxy：绫波级不在映射表；Cape 运行时把天雾/夕雾绑定到 fubuki_1936_refit（Form 10 153/171），Horaniu 把涟绑定到 fubuki_1936_horaniu（p.162）；按 CAS 现行吹雪级（特型 II 型）卡归类，非跨级；period 逐舰卡：cape-runtime.json yugiri/fubuki_1936_refit（Form 10 p.171）",
    },
    Profile {
        id: "IBS-U-IJN-AMAGIRI",
        source_class: "fubuki_1936_refit",
        name: "天雾",
        source: "provisional（待平衡复核）class_proxy：绫波级不在映射表；Cape 运行时把天雾/夕雾绑定到 fubuki_1936_refit（Form 10 153/171），Horaniu 把涟绑定到 fubuki_1936_horaniu（p.162）；按 CAS 现行吹雪级（特型 II 型）卡归类，非跨级；period 逐舰卡：kula-runtime.json kula-amagiri/fubuki_1936（Form 10 p.154）",
    },
    Profile {
        id: "IBS-U-IJN-SHIKINAMI",
        source_class: "fubuki_1936_refit",
        name: "敷波",
        source: "provisional（待平衡复核）class_proxy：绫波级不在映射表；Cape 运行时把天雾/夕雾绑定到 fubuki_1936_refit（Form 10 153/171），Horaniu 把涟绑定到 fubuki_1936_horaniu（p.162）；按 CAS 现行吹雪级（特型 II 型）卡归类，非跨级",
    },
    Profile {
        id: "IBS-U-IJN-URANAMI",
        source_class: "fubuki_1936_refit",
        name: "浦波",
        source: "provisional（待平衡复核）class_proxy：吹雪级（1936 改装）类卡（JP A-27/C-1）",
    },
    Profile {
        id: "IBS-U-IJN-SAZANAMI",
        source_class: "fubuki_1936_refit",
        name: "涟",
        source: "provisional（待平衡复核）class_proxy：绫波级不在映射表；Cape 运行时把天雾/夕雾绑定到 fubuki_1936_refit（Form 10 153/171），Horaniu 把涟绑定到 fubuki_1936_horaniu（p.162）；按 CAS 现行吹雪级（特型 II 型）卡归类，非跨级；period 逐舰卡：horaniu-1943.json sazanami/fubuki_1936_horaniu（Form 10 p.162）",
    },
    Profile {
        id: "IBS-U-IJN-SHIRAYUKI",
        source_class: "fubuki_1936_refit",
        name: "白雪",
        source: "provisional（待平衡复核）class_proxy：吹雪级（1936 改装）类卡（JP A-27/C-1）",
    },
    Profile {
        id: "IBS-U-IJN-AYANAMI",
        source_class: "fubuki_1936_refit",
        name: "绫波",
        source: "provisional（待平衡复核）class_proxy：绫波级不在映射表；Cape 运行时把天雾/夕雾绑定到 fubuki_1936_refit（Form 10 153/171），Horaniu 把涟绑定到 fubuki_1936_horaniu（p.162）；按 CAS 现行吹雪级（特型 II 型）卡归类，非跨级",
    },
    Profile {
        id: "IBS-U-IJN-OYASHIO",
        source_class: "kagero",
        name: "亲潮",
        source: "provisional（待平衡复核）class_proxy：阳炎级类卡（JP A-9/C-1）；period 逐舰卡：tassafaronga-runtime.json tass_oyashio/kagero_1942_base",
    },
    Profile {
        id: "IBS-U-IJN-HATSU-KAZE",
        source_class: "kagero",
        name: "初风",
        source: "provisional（待平衡复核）class_proxy：阳炎级类卡（JP A-9/C-1）；crosswalk 未登记舰级，舰级由 period 档案确认；period 逐舰卡：empress-augusta-bay-1943.json hatsukaze/kagero_1943（Form 10 p.102）",
    },
    Profile {
        id: "IBS-U-IJN-HAMAKAZE",
        source_class: "kagero",
        name: "浜风",
        source: "provisional（待平衡复核）class_proxy：阳炎级类卡（JP A-9/C-1）；period 逐舰卡：kula-runtime.json kula-hamakaze/kagero（Form 10 p.101）",
    },
    Profile {
        id: "IBS-U-IJN-ISOKAZE",
        source_class: "kagero",
        name: "矶风",
        source: "provisional（待平衡复核）class_proxy：阳炎级类卡（JP A-9/C-1）；period 逐舰卡：horaniu-1943.json isokaze/kagero_1943_horaniu（Form 10 p.104）",
    },
    Profile {
        id: "IBS-U-IJN-AKIGUMO",
        source_class: "kagero",
        name: "秋云",
        source: "provisional（待平衡复核）class_proxy：阳炎级类卡（JP A-9/C-1）",
    },
    Profile {
        id: "IBS-U-IJN-TANIKAZE",
        source_class: "kagero",
        name: "谷风",
        source: "provisional（待平衡复核）class_proxy：阳炎级类卡（JP A-9/C-1）；period 逐舰卡：kula-runtime.json kula-tanikaze/kagero（Form 10 p.110）",
    },
    Profile {
        id: "IBS-U-IJN-YUKIKAZE",
        source_class: "kagero",
        name: "雪风",
        source: "provisional（待平衡复核）class_proxy：阳炎级类卡（JP A-9/C-1）",
    },
    Profile {
        id: "IBS-U-IJN-KUROSHIO",
        source_class: "kagero",
        name: "黑潮",
        source: "provisional（待平衡复核）class_proxy：阳炎级类卡（JP A-9/C-1）；period 逐舰卡：tassafaronga-runtime.json tass_kuroshio/kagero_1942_base",
    },
    Profile {
        id: "IBS-U-IJN-SAMIDARE",
        source_class: "shiratsuyu",
        name: "五月雨",
        source: "provisional（待平衡复核）class_proxy：白露级类卡（JP A-22/C-1）；period 逐舰卡：empress-augusta-bay-1943.json samidare/shiratsuyu_1943（Form 10 p.131）",
    },
    Profile {
        id: "IBS-U-IJN-SUZUKAZE",
        source_class: "shiratsuyu",
        name: "凉风",
        source: "provisional（待平衡复核）class_proxy：白露级类卡（JP A-22/C-1）；period 逐舰卡：kula-runtime.json kula-suzukaze/shiratsuyu（Form 10 p.137）",
    },
    Profile {
        id: "IBS-U-IJN-YUDACHI",
        source_class: "shiratsuyu",
        name: "夕立",
        source: "provisional（待平衡复核）class_proxy：白露级类卡（JP A-22/C-1）",
    },
    Profile {
        id: "IBS-U-IJN-SHIGURE",
        source_class: "shiratsuyu",
        name: "时雨",
        source: "provisional（待平衡复核）class_proxy：白露级类卡（JP A-22/C-1）；period 逐舰卡：empress-augusta-bay-1943.json shigure/shiratsuyu_1943（Form 10 p.133）",
    },
    Profile {
        id: "IBS-U-IJN-HARUSAME",
        source_class: "shiratsuyu",
        name: "春雨",
        source: "provisional（待平衡复核）class_proxy：白露级类卡（JP A-22/C-1）",
    },
    Profile {
        id: "IBS-U-IJN-MURASAME",
        source_class: "shiratsuyu",
        name: "村雨",
        source: "provisional（待平衡复核）class_proxy：白露级类卡（JP A-22/C-1）",
    },
    Profile {
        id: "IBS-U-IJN-KAWAKAZE",
        source_class: "shiratsuyu",
        name: "江风",
        source: "provisional（待平衡复核）class_proxy：白露级类卡（JP A-22/C-1）；period 逐舰卡：tassafaronga-runtime.json tass_kawakaze/shiratsuyu_1942",
    },
    Profile {
        id: "IBS-U-IJN-MAKINAMI",
        source_class: "yugumo",
        name: "卷波",
        source: "provisional（待平衡复核）class_proxy：夕云级类卡（JP A-24/C-1）；period 逐舰卡：cape-runtime.json makinami/yugumo_1943_asw（Form 10 p.89）",
    },
    Profile {
        id: "IBS-U-IJN-ONAMI",
        source_class: "yugumo",
        name: "大波",
        source: "provisional（待平衡复核）class_proxy：夕云级类卡（JP A-24/C-1）；period 逐舰卡：cape-runtime.json onami/yugumo_1943_asw（Form 10 p.93）",
    },
    Profile {
        id: "IBS-U-IJN-KIYONAMI",
        source_class: "yugumo",
        name: "清波",
        source: "provisional（待平衡复核）class_proxy：夕云级类卡（JP A-24/C-1）",
    },
    Profile {
        id: "IBS-U-IJN-NAGANAMI",
        source_class: "yugumo",
        name: "长波",
        source: "provisional（待平衡复核）class_proxy：夕云级类卡（JP A-24/C-1）；period 逐舰卡：empress-augusta-bay-1943.json naganami/yugumo_1943（Form 10 p.91）",
    },
    Profile {
        id: "IBS-U-IJN-KAZEKUMO",
        source_class: "yugumo",
        name: "风云",
        source: "provisional（待平衡复核）class_proxy：夕云级类卡（JP A-24/C-1）",
    },
    Profile {
        id: "IBS-U-IJN-TAKANAMI",
        source_class: "yugumo",
        name: "高波",
        source: "provisional（待平衡复核）class_proxy：夕云级类卡（JP A-24/C-1）；period 逐舰卡：tassafaronga-runtime.json tass_takanami/yugumo_1942",
    },
    // Period per-hull cards from `data/ships/period-cards.json` (2026-11-08).
    // These 23 catalogue identities were collection-only because the ranked
    // registry only loaded the 25 stage0/prologue class cards. Their scenario
    // packages carry a complete per-ship ShipDef, so `source_class` names that
    // period profile and `data()` copies the full card from the period payload
    // instead of aliasing a class card. Point values are provisional pending
    // the balance review; no scenario budget moves.
    // CL 博伊西 — cape-esperance-1942.json
    Profile {
        id: "IBS-U-USN-BOISE",
        source_class: "brooklyn_first_group_1942",
        name: "博伊西",
        source: "period exact · cape-esperance-1942.json boise · Form 10 p.265（点数 provisional，待平衡复核）",
    },
    // DD 法伦霍尔特 — cape-esperance-1942.json
    Profile {
        id: "IBS-U-USN-FARENHOLT",
        source_class: "bristol_1942",
        name: "法伦霍尔特",
        source: "period exact · cape-esperance-1942.json farenholt · Form 10 p.296（点数 provisional，待平衡复核）",
    },
    // DD 邓肯 — cape-esperance-1942.json
    Profile {
        id: "IBS-U-USN-DUNCAN",
        source_class: "bristol_1942",
        name: "邓肯",
        source: "period exact · cape-esperance-1942.json duncan · Form 10 p.295（点数 provisional，待平衡复核）",
    },
    // DD 拉菲 — cape-esperance-1942.json
    Profile {
        id: "IBS-U-USN-LAFFEY",
        source_class: "bristol_1942",
        name: "拉菲",
        source: "period exact · cape-esperance-1942.json laffey · Form 10 p.297（点数 provisional，待平衡复核）",
    },
    // DD 布坎南 — savo-runtime.json us_bristol_dd + Form 10 p.292/p.293
    Profile {
        id: "IBS-U-USN-BUCHANAN",
        source_class: "us_bristol_dd",
        name: "布坎南",
        source: "period exact · savo-runtime.json savo_buchanan/us_bristol_dd · Form 10 p.292/p.293 个体页（4 门单装、10 雷管、118 DP/37 节）· 点数 provisional，待平衡复核",
    },
    // DD 麦卡拉 — cape-esperance-1942.json
    Profile {
        id: "IBS-U-USN-MCCALLA",
        source_class: "bristol_1942",
        name: "麦卡拉",
        source: "period exact · cape-esperance-1942.json mccalla · Form 10 p.299（点数 provisional，待平衡复核）",
    },
    // CL 火奴鲁鲁 — kula-runtime.json
    Profile {
        id: "IBS-U-USN-HONOLULU",
        source_class: "brooklyn_1",
        name: "火奴鲁鲁",
        source: "period exact · kula-runtime.json kula-honolulu · Form 10 p.267（点数 provisional，待平衡复核）",
    },
    // DD 卯月(I) — cape-runtime.json
    Profile {
        id: "IBS-U-IJN-UZUKI",
        source_class: "mutsuki_1943_uzuki",
        name: "卯月(I)",
        source: "period exact · cape-runtime.json uzuki · Form 10 p.183（点数 provisional，待平衡复核）",
    },
    // DD 拉尔夫·托尔伯特 — savo-runtime.json
    Profile {
        id: "IBS-U-USN-RALPH-TALBOT",
        source_class: "us_bagley_dd",
        name: "拉尔夫·托尔伯特",
        source: "period exact · savo-runtime.json savo_ralph_talbot · Form 10 未核（点数 provisional，待平衡复核）",
    },
    // DD 蒙森 — savo-runtime.json us_benson_dd + Form 10 p.303
    Profile {
        id: "IBS-U-USN-MONSSEN",
        source_class: "us_benson_dd",
        name: "蒙森",
        source: "period exact · savo-runtime.json savo_monssen/us_benson_dd · Form 10 p.303 个体页（4 门单装、10 雷管、128 DP/35 节）· 点数 provisional，待平衡复核",
    },
    // CA 澳大利亚 — savo-runtime.json
    Profile {
        id: "IBS-U-RAN-AUSTRALIA",
        source_class: "gb_kent_1939_ca",
        name: "澳大利亚",
        source: "period exact · savo-runtime.json savo_australia · Form 10 未核（点数 provisional，待平衡复核）",
    },
    // CA 堪培拉 — savo-runtime.json
    Profile {
        id: "IBS-U-RAN-CANBERRA",
        source_class: "gb_kent_1939_ca",
        name: "堪培拉",
        source: "period exact · savo-runtime.json savo_canberra · Form 10 未核（点数 provisional，待平衡复核）",
    },
    // DD 巴格莱 — savo-runtime.json
    Profile {
        id: "IBS-U-USN-BAGLEY",
        source_class: "us_bagley_dd",
        name: "巴格莱",
        source: "period exact · savo-runtime.json savo_bagley · Form 10 未核（点数 provisional，待平衡复核）",
    },
    // DD 帕特森 — savo-runtime.json
    Profile {
        id: "IBS-U-USN-PATTERSON",
        source_class: "us_bagley_dd",
        name: "帕特森",
        source: "period exact · savo-runtime.json savo_patterson · Form 10 未核（点数 provisional，待平衡复核）",
    },
    // DD 赫尔姆 — savo-runtime.json
    Profile {
        id: "IBS-U-USN-HELM",
        source_class: "us_bagley_dd",
        name: "赫尔姆",
        source: "period exact · savo-runtime.json savo_helm · Form 10 未核（点数 provisional，待平衡复核）",
    },
    // DD 威尔逊 — savo-runtime.json us_benham_dd + 本舰 Form 10
    Profile {
        id: "IBS-U-USN-WILSON",
        source_class: "us_benham_dd",
        name: "威尔逊",
        source: "period exact · savo-runtime.json savo_wilson/us_benham_dd · Form 10 p.317 个体页（4 门单装、16 雷管、118 DP/38 节）· 点数 provisional，待平衡复核",
    },
    // CL 圣胡安 — savo-runtime.json us_atlanta_cl + 本舰 Form 10
    Profile {
        id: "IBS-U-USN-UNNAMED-T01-R25",
        source_class: "us_atlanta_cl",
        name: "圣胡安",
        source: "period exact · savo-runtime.json savo_san_juan/us_atlanta_cl · Form 10 p.262 个体页（8 座双联 16 管、8 雷管、304 DP）· 点数 provisional，待平衡复核",
    },
    // DD 贾维斯 — savo-runtime.json
    Profile {
        id: "IBS-U-USN-JARVIS",
        source_class: "us_bagley_dd",
        name: "贾维斯",
        source: "period exact · savo-runtime.json savo_jarvis · Form 10 未核（点数 provisional，待平衡复核）",
    },
    // DD 赛尔弗里纪 — savo-runtime.json
    Profile {
        id: "IBS-U-USN-SELFRIDGE",
        source_class: "us_porter_dd",
        name: "赛尔弗里纪",
        source: "period exact · savo-runtime.json savo_selfridge · Form 10 未核（点数 provisional，待平衡复核）",
    },
    // DD 赫尔(I) — savo-runtime.json
    Profile {
        id: "IBS-U-USN-HULL-I",
        source_class: "us_farragut_dd",
        name: "赫尔(I)",
        source: "period exact · savo-runtime.json savo_hull/us_farragut_dd · AF A-19（5 门单装、8 雷管、D/Small 200/1、105 DP/36 节）· 点数 provisional，待平衡复核",
    },
    // CA 鸟海 — savo-island-1942.json jp_takao_1939_ca + Chokai 本舰 Form 10
    Profile {
        id: "IBS-U-IJN-CHOKAI",
        source_class: "jp_takao_1939_ca",
        name: "鸟海",
        source: "period exact · savo-island-1942.json jp_takao_1939_ca · Form 10 p.49 个体页（9 管/5 座、8 雷管、471 DP）· 点数 provisional，待平衡复核",
    },
    // CL 天龙 — savo-runtime.json
    Profile {
        id: "IBS-U-IJN-TENRYU",
        source_class: "jp_tenryu_cl",
        name: "天龙",
        source: "period exact · savo-runtime.json savo_tenryu · Form 10 p.81（点数 provisional，待平衡复核）",
    },
    // CL 夕张 — savo-runtime.json
    Profile {
        id: "IBS-U-IJN-YUBARI",
        source_class: "jp_yubari_cl",
        name: "夕张",
        source: "period exact · savo-runtime.json savo_yubari · Form 10 p.75（点数 provisional，待平衡复核）",
    },
    // 91 merged per-hull cards from data/ships/merged-cards.json, generated by
    // scripts/build-merged-cards.py.
];

/// The complete registry: 111 hand-registered stage0/period profiles plus the
/// 91 generated merged profiles. Both slices are static, so the composition is
/// built once and handed out as a plain slice.
fn profiles() -> &'static [Profile] {
    static PROFILES: OnceLock<Vec<Profile>> = OnceLock::new();
    PROFILES.get_or_init(|| {
        let mut all = LEGACY_PROFILES.to_vec();
        all.extend_from_slice(&MERGED_PROFILES);
        all
    })
}

const MERGED_PROFILES: &[Profile] = include!("ranked_profiles_merged.inc");

pub(crate) fn class_for(id: &str) -> &str {
    source_class(id).unwrap_or(id)
}

/// Player-facing name for a registered task-force pick. Class IDs fall back to
/// the scenario card name; this keeps "北卡罗来纳" from becoming "北卡罗来纳级".
pub(crate) fn display_name(id: &str) -> Option<&'static str> {
    profiles().iter().find(|profile| profile.id == id).map(|profile| profile.name)
}

pub(crate) fn ship_points(ship: &ShipDef) -> u32 {
    point_value(ship)
}

pub(crate) fn options(side: usize) -> E<Value> {
    let side_name = if side == 0 { "allies" } else { "axis" };
    let rows = data()?.ships.iter().filter(|ship| ship.side == side_name).map(|ship| {
        json!({"id":ship.id, "class":class_for(&ship.id), "name":ship.name,
               "kind":ship.kind, "points":point_value(ship)})
    }).collect::<Vec<_>>();
    Ok(json!(rows))
}

pub(crate) fn source_class(id: &str) -> Option<&'static str> {
    profiles()
        .iter()
        .find(|profile| profile.id == id && profile.source_class != id)
        .map(|profile| profile.source_class)
}

pub(crate) fn data() -> E<&'static Data> {
    static DATA: OnceLock<Result<Data, String>> = OnceLock::new();
    DATA.get_or_init(|| {
        let reference = crate::prologue::data()?;
        let period = period_cards()?;
        let merged = merged_cards()?;
        let mut ships = Vec::with_capacity(profiles().len());
        for profile in profiles() {
            if let Some(card) = period.iter().find(|card| card.identity == profile.id) {
                if card.profile != profile.source_class {
                    return Err(format!("{} 的 period profile 与注册表不一致", profile.name));
                }
                if !card.verified {
                    // A period card whose printed battery could not be rebuilt is
                    // registered but not fielded: no wrong stat ships as playable,
                    // and `roster()` rejects the id.
                    continue;
                }
                // Per-hull period card: the complete ShipDef comes from the
                // scenario package, not from a stage0/prologue class card.
                let mut ship = card.ship.clone();
                ship.id = profile.id.into();
                ship.name = profile.name.into();
                ships.push(ship);
                continue;
            }
            if let Some(card) = merged.iter().find(|card| card.identity == profile.id) {
                if card.profile != profile.source_class {
                    return Err(format!("{} 的 merged class profile 与注册表不一致", profile.name));
                }
                if !card.verified {
                    // Same gate as period cards: an unverified merged hull is
                    // registered but never fielded.
                    continue;
                }
                let mut ship = card.ship.clone();
                ship.id = profile.id.into();
                ship.name = profile.name.into();
                ships.push(ship);
                continue;
            }
            let mut ship = reference
                .ships
                .iter()
                .find(|ship| ship.id == profile.source_class)
                .cloned()
                .ok_or_else(|| format!("{} 的时期舰卡尚未加载", profile.name))?;
            ship.id = profile.id.into();
            ship.name = profile.name.into();
            ships.push(ship);
        }
        Ok(Data {
            ships,
            rules: reference.rules.clone(),
        })
    })
    .as_ref()
    .map_err(Clone::clone)
}

/// `data/ships/period-cards.json`: the per-hull period cards whose complete
/// ShipDef the scenario package registers (dp, gun, torpedo, armor, damage and
/// speed rows). The ranked registry loads these next to the stage0/prologue
/// class cards so a hull with an exact period card does not need a class-card
/// alias. The file is generated by `scripts/build-period-cards.py`.
const PERIOD_CARDS: &str = include_str!("../data/ships/period-cards.json");
const PERIOD_CARD_VERSION: &str = "cas-period-cards-v1";

struct PeriodCard {
    identity: String,
    ship_id: String,
    profile: String,
    ship: ShipDef,
    /// `stat_verified` from the period card: false means the printed battery
    /// could not be rebuilt from the source page and the hull stays out of the
    /// playable registry (`data()` skips it, `roster()` rejects it).
    verified: bool,
}

fn period_cards() -> E<&'static [PeriodCard]> {
    static CARDS: OnceLock<Result<Vec<PeriodCard>, String>> = OnceLock::new();
    CARDS
        .get_or_init(|| {
            let rows: Vec<Value> = serde_json::from_str(PERIOD_CARDS)
                .map_err(|error| format!("data/ships/period-cards.json 解析失败：{error}"))?;
            rows.into_iter()
                .map(|row| {
                    let field = |name: &str| {
                        row[name]
                            .as_str()
                            .map(str::to_string)
                            .ok_or_else(|| format!("period 舰卡缺少 {name}"))
                    };
                    let identity = field("identity")?;
                    let ship_id = field("period_ship_id")?;
                    let profile = field("period_profile")?;
                    let ship: ShipDef = serde_json::from_value(row["ship"].clone()).map_err(
                        |error| format!("{identity} 的 period 舰卡不是完整 ShipDef：{error}"),
                    )?;
                    let verified = row["stat_verified"].as_bool().unwrap_or(false);
                    Ok(PeriodCard { identity, ship_id, profile, ship, verified })
                })
                .collect()
        })
        .as_ref()
        .map(|cards| cards.as_slice())
        .map_err(Clone::clone)
}

fn period_card(profile: &Profile) -> E<Option<&'static PeriodCard>> {
    Ok(period_cards()?.iter().find(|card| card.identity == profile.id))
}

/// `data/ships/merged-cards.json`: the 91 per-hull cards merged from the
/// Form 10 / APD / same-class / CAS source-table / ERMA / historical-axis
/// packages. Every row carries a complete ShipDef; the registry field
/// `class_profile` is the loaded class card (`source_class`). The file is
/// generated by `scripts/build-merged-cards.py`.
const MERGED_CARDS: &str = include_str!("../data/ships/merged-cards.json");
const MERGED_CARD_VERSION: &str = "cas-merged-cards-v1";

struct MergedCard {
    identity: String,
    profile: String,
    ship: ShipDef,
    /// `stat_verified` from the merged card: false keeps the identity out of
    /// the playable registry (`data()` skips it, `roster()` rejects it).
    verified: bool,
}

fn merged_cards() -> E<&'static [MergedCard]> {
    static CARDS: OnceLock<Result<Vec<MergedCard>, String>> = OnceLock::new();
    CARDS
        .get_or_init(|| {
            let document: Value = serde_json::from_str(MERGED_CARDS)
                .map_err(|error| format!("data/ships/merged-cards.json 解析失败：{error}"))?;
            let rows = document["cards"]
                .as_array()
                .ok_or("data/ships/merged-cards.json 缺少 cards")?
                .clone();
            rows.into_iter()
                .map(|row| {
                    let field = |name: &str| {
                        row[name]
                            .as_str()
                            .map(str::to_string)
                            .ok_or_else(|| format!("merged 舰卡缺少 {name}"))
                    };
                    let identity = field("identity")?;
                    let profile = field("class_profile")?;
                    let ship: ShipDef = serde_json::from_value(row["ship"].clone()).map_err(
                        |error| format!("{identity} 的 merged 舰卡不是完整 ShipDef：{error}"),
                    )?;
                    let verified = row["stat_verified"].as_bool().unwrap_or(false);
                    Ok(MergedCard { identity, profile, ship, verified })
                })
                .collect()
        })
        .as_ref()
        .map(|cards| cards.as_slice())
        .map_err(Clone::clone)
}

fn merged_card(profile: &Profile) -> E<Option<&'static MergedCard>> {
    Ok(merged_cards()?.iter().find(|card| card.identity == profile.id))
}

// Economy units derived from the fields of the actual frozen surface combat fit.
// These coefficients belong to CAS RTS multiplayer, not to the printed rulebook.
// `data/rules/cas-competitive-points-v1.json` is the frozen player-facing copy;
// the test below fails if this function and that manifest drift apart.
fn point_value(ship: &ShipDef) -> u32 {
    let average_gun_damage = ship.gun.damage.iter().sum::<f64>() / ship.gun.damage.len() as f64;
    let torpedo = ship.torpedo.as_ref().map_or(0., |t| {
        TORPEDO_TUBE_WARHEAD_WEIGHT * f64::from(t.tubes) * t.warhead
    });
    let raw = DP_WEIGHT * ship.dp
        + KNOT_WEIGHT * ship.max_knots
        + GUN_BARREL_DAMAGE_WEIGHT * f64::from(ship.gun.barrels) * average_gun_damage
        + torpedo
        + ARMOR_WEIGHT * (ship.armor_belt + ship.armor_deck)
        + TORPEDO_PROTECTION_WEIGHT * ship.torpedo_protection_dp;
    // Balance targets: a 3000-point escort action must fit six destroyers,
    // while a 10000-point action must fit a battleship and escorts.
    let scale = match ship.kind.as_str() {
        "DD" => 0.75,
        "CL" => 0.85,
        "CA" => 1.0,
        "BB" => 1.2,
        _ => 1.0,
    };
    ((raw * scale / f64::from(POINT_UNIT)).round() as u32) * POINT_UNIT
}

/// Catalogue reference for the card an identity's ShipDef was taken from.
fn card_ref(profile: &Profile) -> String {
    if let Ok(Some(card)) = period_card(profile) {
        return format!("{PERIOD_CARD_VERSION}#{}", card.ship_id);
    }
    if let Ok(Some(card)) = merged_card(profile) {
        return format!("{MERGED_CARD_VERSION}#{}", card.identity);
    }
    format!("cas-prologue-runtime-v1#{}", profile.source_class)
}

pub(crate) fn catalogue() -> E<Value> {
    let loaded = data()?;
    // Look the card up by identity: an unverified period card is absent from
    // the loaded set and therefore absent from the point table too.
    let ships: Map<String, Value> = profiles()
        .iter()
        .filter_map(|profile| {
            let ship = loaded.ships.iter().find(|ship| ship.id == profile.id)?;
            Some((
                profile.id.into(),
                json!({"profile_id":card_ref(profile),
            "points":point_value(ship),"source":profile.source}),
            ))
        })
        .collect();
    Ok(
        json!({"schema_version":1,"version":POINTS_VERSION,"rules_version":realtime::VERSION,
        "enabled_budgets":[3000,10000],"ships":ships}),
    )
}

fn roster(data: &Data, config: &RankedFleet, budget: u32) -> E<Vec<usize>> {
    let ship_ids = &config.ship_ids;
    let count = ship_ids.len();
    let max = if budget == 3000 { 6 } else { 8 };
    if !(3..=max).contains(&count) || ship_ids.iter().collect::<BTreeSet<_>>().len() != count {
        return Err("编队数量不符或有重复舰船".into());
    }
    let leader = ship_ids
        .iter()
        .position(|id| id == &config.leader_id)
        .ok_or("领舰不属于当前编队")?;
    let mut ships = ship_ids
        .iter()
        .map(|id| {
            data.ships
                .iter()
                .position(|ship| ship.id == *id)
                .ok_or_else(|| format!("尚未核准舰船 {id} 的 CAS 出战舰卡"))
        })
        .collect::<E<Vec<_>>>()?;
    let defs: Vec<_> = ships.iter().map(|index| &data.ships[*index]).collect();
    if defs.iter().any(|ship| ship.side != defs[0].side) {
        return Err("同一编队的舰船必须属于同一舰籍阵营".into());
    }
    let (mut dd, mut cruisers, mut bb) = (0, 0, 0);
    for ship in &defs {
        match ship.kind.as_str() {
            "DD" => dd += 1,
            // Large cruisers (CB) and seaplane tenders (AV) count against the
            // cruiser slots; battlecruisers (BC) are capital ships like BB.
            // This keeps every one of the 202 verified identities selectable
            // without inventing a fourth slot class for seven hulls.
            "CL" | "CA" | "CB" | "AV" => cruisers += 1,
            "BB" | "BC" => bb += 1,
            _ => return Err("该舰种不允许编入此对局".into()),
        }
    }
    let valid = if budget == 3000 {
        bb == 0 && dd >= 2 && cruisers <= 2
    } else {
        (1..=2).contains(&bb) && dd <= 4 && dd + cruisers >= 2
    };
    if !valid {
        return Err("编成不符合所选分档".into());
    }
    if defs.iter().map(|ship| point_value(ship)).sum::<u32>() > budget {
        return Err("编队超过所选分档的点数上限".into());
    }
    let index = ships.remove(leader);
    ships.insert(0, index);
    Ok(ships)
}

fn doctrine(id: &str) -> E<&'static str> {
    match id {
        "adaptive" | "rc_coordinated" | "coord" => Ok("coord"),
        "gunnery" => Ok("gunnery"),
        "torpedo" => Ok("torpedo"),
        _ => Err("该账号指挥官尚无对应 CAS 策略".into()),
    }
}

impl World {
    pub(crate) fn new_ranked_duel(seed: u32, config: RankedFleetMatch) -> E<Self> {
        let budget = config.budget;
        if !matches!(budget, 3000 | 10000) || config.points_version != POINTS_VERSION {
            return Err("个人舰队分档或点表版本无效".into());
        }
        let data = data()?;
        let allies = roster(data, &config.fleets.allies, budget)?;
        let axis = roster(data, &config.fleets.axis, budget)?;
        let profiles = [
            doctrine(&config.fleets.allies.ai_profile)?,
            doctrine(&config.fleets.axis.ai_profile)?,
        ];
        let mut world = Self::blank(data, seed, 0, "coord", VARIANT, "coord", 0);
        if budget == 10000 {
            world.field = Field {
                width: 60_000.,
                height: 36_000.,
                limit: LIMIT,
            };
        }
        world.host_duel = true;
        // The two seats are tactical sides, independent from national fleet identity.
        world.ranked_duel = Some(config);
        for (owner, definitions) in [allies, axis].into_iter().enumerate() {
            let id = owner as u32 + 1;
            let (x, heading, y) = if budget == 3000 {
                if owner == 0 {
                    (4200., 90., 6550.)
                } else {
                    (19_800., 270., 7650.)
                }
            } else if owner == 0 {
                (12_000., 90., 15_500.)
            } else {
                (48_000., 270., 20_500.)
            };
            let gap = if budget == 3000 { 450. } else { 950. };
            let direction = P::bearing(heading);
            let start = P { x, y };
            let mut members = Vec::new();
            for (slot, def) in definitions.into_iter().enumerate() {
                let name = data.ships[def].name.clone();
                members.push(world.spawn(
                    def,
                    owner,
                    id,
                    name,
                    (start - direction * (gap * slot as f64)).snap(),
                    heading,
                )?);
            }
            world.fleets.push(Fleet {
                id,
                side: owner,
                name: if owner == 0 {
                    "同盟席编队".into()
                } else {
                    "轴心席编队".into()
                },
                leader: members[0],
                members,
                mode: "follow".into(),
                speed: 26.,
                actual: 0.,
                turn_degrees: 0.,
                points: vec![],
                ai: Ai::new(profiles[owner], "suggest"),
                notice: None,
                last_ai_route: 0,
                tactic: Tactic::Search,
            });
        }
        world.gun_streak.resize(world.ships.len(), (0, 0, 0));
        world
            .surface_damage
            .resize(world.ships.len(), Default::default());
        world.init_realtime(realtime::VERSION)?;
        world.add(
            3,
            "start",
            "个人舰队演习 · 双方预设已冻结，四十五分钟按击沉数决胜。".into(),
            Some("RTS-PVP-01"),
            None,
        );
        world.detect(true);
        Ok(world)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn preset(ids: &[&str]) -> RankedFleet {
        RankedFleet {
            ship_ids: ids.iter().map(|id| (*id).into()).collect(),
            leader_id: ids[1].into(),
            ai_profile: "rc_coordinated".into(),
        }
    }

    fn duel(budget: u32, allies: RankedFleet, axis: RankedFleet) -> RankedFleetMatch {
        RankedFleetMatch {
            budget,
            points_version: POINTS_VERSION.into(),
            fleets: RankedFleets { allies, axis },
        }
    }

    #[test]
    fn free_fleet_mirrors_keep_their_named_profiles_and_replay() {
        let ids = ["IBS-U-USN-FLETCHER", "IBS-U-USN-PERKINS", "IBS-U-USN-MAURY"];
        let mut world =
            World::new_ranked_duel(6106, duel(3000, preset(&ids), preset(&ids))).unwrap();
        for (seat, (fleet, x, y)) in [(1, 15_000, 6550), (2, 9000, 7650)].into_iter().enumerate() {
            let view = world.observation(seat);
            assert_eq!(view["ships"].as_array().unwrap().len(), 3);
            assert_eq!(view["ships"][0]["characterId"], ids[1]);
            assert_eq!(view["ships"][1]["classId"], ids[0]);
            assert_eq!(view["fleets"][0]["leader"], view["ships"][0]["id"]);
            assert_eq!(view["fleets"][0]["ai"]["mode"], "suggest");
            world.external_for(seat, json!({"op":"route","fleet":fleet,"mode":"follow","speed":25,"points":[{"x":x,"y":y}]})).unwrap();
        }
        for _ in 0..540 {
            world.advance();
        }
        for seat in [0, 1] {
            let gun = world
                .suggestions(seat, seat as u32 + 1)
                .unwrap()
                .into_iter()
                .find(|order| order["op"] == "fire" && order["weapon"] == "gun")
                .unwrap();
            world.external_for(seat, gun).unwrap();
        }
        for _ in 0..120 {
            world.advance();
        }
        assert!([0, 1].into_iter().all(|seat| world
            .visible_events(seat, None)
            .iter()
            .any(|event| event["kind"] == "gun" && event.get("own_ship").is_some())));
        let save = world.save();
        let restored = World::from_save(save.clone(), save.tick).unwrap();
        for seat in [0, 1] {
            assert_eq!(restored.observation(seat), world.observation(seat));
        }
        assert_eq!(json!(restored.save()), json!(save));
        assert!(World::new_ranked_duel(6106, duel(10000, preset(&ids), preset(&ids))).is_err());
    }

    #[test]
    fn capital_ships_inherit_source_batteries_and_armor() {
        let allies = preset(&[
            "IBS-U-USN-UNNAMED-T01-R03",
            "IBS-U-USN-FLETCHER",
            "IBS-U-USN-MAURY",
        ]);
        let axis = preset(&[
            "IBS-U-IJN-ERMA-YAMATO",
            "IBS-U-IJN-SENDAI",
            "IBS-U-IJN-KAGERO",
        ]);
        let world = World::new_ranked_duel(42, duel(10000, allies, axis)).unwrap();
        assert_eq!(
            world.observation(0)["ships"][1]["systems"]["torpedoProtection"]["capacity"].as_f64(),
            Some(165.)
        );
        assert_eq!(
            world.observation(1)["ships"][1]["systems"]["torpedoProtection"]["capacity"].as_f64(),
            Some(195.)
        );
        let table = catalogue().unwrap();
        assert_eq!(table["enabled_budgets"], json!([3000, 10000]));
        assert_eq!(table["ships"]["IBS-U-USN-FLETCHER"]["points"], 475);
    }

    #[test]
    fn frozen_manifest_matches_the_runtime_point_formula() {
        let manifest: Value = serde_json::from_str(include_str!(
            "../data/rules/cas-competitive-points-v1.json"
        ))
        .expect("point manifest parses");
        assert_eq!(manifest["version"], POINTS_VERSION);
        assert_eq!(manifest["rules_version"], realtime::VERSION);
        assert_eq!(manifest["enabled_budgets"], json!([3000, 10000]));
        let manifest_ships = manifest["ships"].as_object().expect("ships object");
        // 88 stage0/prologue class cards + 23 per-hull period cards + 91 merged
        // per-hull cards. The registry is the single source of the point table.
        assert_eq!(profiles().len(), 202);
        assert_eq!(manifest_ships.len(), profiles().len());
        assert_eq!(
            data().unwrap().ships.len(),
            profiles().len(),
            "every profile is fielded (no stat_verified=false card)"
        );
        let table = catalogue().unwrap();
        for profile in profiles() {
            let ship = data()
                .unwrap()
                .ships
                .iter()
                .find(|ship| ship.id == profile.id)
                .expect("profile card is loaded");
            let expected = point_value(ship);
            let row = manifest_ships
                .get(profile.id)
                .unwrap_or_else(|| panic!("{} is missing from the manifest", profile.id));
            assert_eq!(
                row["points"].as_u64(),
                Some(u64::from(expected)),
                "{} points: manifest {:?}, runtime {expected}",
                profile.id,
                row["points"]
            );
            let profile_id = card_ref(profile);
            assert_eq!(
                row["profile_id"].as_str(),
                Some(profile_id.as_str()),
                "{}",
                profile.id
            );
            assert_eq!(table["ships"][profile.id]["points"], expected, "{}", profile.id);
            assert_eq!(
                table["ships"][profile.id]["profile_id"],
                row["profile_id"],
                "{}",
                profile.id
            );
            assert_eq!(table["ships"][profile.id]["source"], row["source"], "{}", profile.id);
        }
    }

    #[test]
    fn every_profile_source_class_resolves_to_a_loaded_card() {
        let reference = crate::prologue::data().unwrap();
        let period = period_cards().unwrap();
        let merged = merged_cards().unwrap();
        assert_eq!(period.len(), 23, "the period-card registry holds 23 hulls");
        assert_eq!(merged.len(), 91, "the merged registry holds 91 hulls");
        for profile in profiles() {
            if let Some(card) = period_card(profile).unwrap() {
                // Period hulls resolve from the per-hull period card, never
                // from a stage0/prologue class card alias.
                assert_eq!(card.profile, profile.source_class, "{}", profile.id);
                assert_eq!(card.ship.id, profile.id, "{} period card id", profile.id);
                assert_eq!(card.ship.name, profile.name, "{} period card name", profile.id);
                assert!(card.verified, "{} period card is not stat-verified", profile.id);
            } else if let Some(card) = merged_card(profile).unwrap() {
                assert_eq!(card.profile, profile.source_class, "{}", profile.id);
                assert_eq!(card.ship.id, profile.id, "{} merged card id", profile.id);
                assert_eq!(card.ship.name, profile.name, "{} merged card name", profile.id);
                assert!(card.verified, "{} merged card is not stat-verified", profile.id);
            } else {
                assert!(
                    reference.ships.iter().any(|ship| ship.id == profile.source_class),
                    "{} source class {} is missing from the prologue card set",
                    profile.id,
                    profile.source_class
                );
            }
            assert!(
                data().unwrap().ships.iter().any(|ship| ship.id == profile.id),
                "{} is missing from the ranked card set",
                profile.id
            );
            assert_eq!(
                display_name(profile.id),
                Some(profile.name),
                "{} display name",
                profile.id
            );
            assert_eq!(class_for(profile.id), profile.source_class, "{} class", profile.id);
        }
    }

    #[test]
    fn period_cards_carry_complete_hulls_into_a_ranked_duel() {
        let data = data().unwrap();
        let period = period_cards().unwrap();
        // Every period card is a complete ShipDef, not a name-only stub: hull,
        // gun battery with real mounts, armor and the printed damage/speed rows.
        for card in period {
            let ship = data
                .ships
                .iter()
                .find(|ship| ship.id == card.identity)
                .expect("period card is loaded");
            assert!(ship.dp > 0., "{} dp", card.identity);
            assert!((20. ..=40.).contains(&ship.max_knots), "{} knots", card.identity);
            assert!(!ship.damage_speed.is_empty(), "{} damage rows", card.identity);
            assert!(ship.gun.barrels > 0, "{} barrels", card.identity);
            assert!(!ship.gun.mounts.is_empty(), "{} gun mounts", card.identity);
            assert_eq!(ship.gun.mounts.iter().map(|m| m.barrels).sum::<u32>(), ship.gun.barrels);
            assert!(ship.gun.range_yd.len() == 4 && ship.gun.damage.len() == 4, "{} gun table", card.identity);
            assert!(matches!(ship.kind.as_str(), "DD" | "CL" | "CA"), "{} kind", card.identity);
        }

        // Six of the period destroyers form a lawful 3000-point escort fleet
        // and the whole battery runs through the ranked world.
        let ids = [
            "IBS-U-USN-HULL-I",
            "IBS-U-USN-MONSSEN",
            "IBS-U-USN-BAGLEY",
            "IBS-U-USN-PATTERSON",
            "IBS-U-USN-HELM",
            "IBS-U-USN-JARVIS",
        ];
        let axis = ["IBS-U-IJN-UZUKI", "IBS-U-IJN-KAGERO", "IBS-U-IJN-TENRYU"];
        let mut world = World::new_ranked_duel(6123, duel(3000, preset(&ids), preset(&axis))).unwrap();
        let view = world.observation(0);
        assert_eq!(view["ships"].as_array().unwrap().len(), 6);
        assert_eq!(view["ships"][0]["characterId"], ids[1]);
        assert_eq!(view["ships"][1]["classId"], ids[0]);
        assert!(view["ships"]
            .as_array()
            .unwrap()
            .iter()
            .all(|ship| ids.contains(&ship["characterId"].as_str().unwrap())));
        for _ in 0..120 {
            world.advance();
        }
    }

    #[test]
    fn period_card_stats_follow_the_printed_hull_pages() {
        let data = data().unwrap();
        let hull = |id: &str| data.ships.iter().find(|ship| ship.id == id).expect("period hull");

        // Chokai — Form 10 p.49 (Aug 42): one single + four twin mount rows.
        let chokai = hull("IBS-U-IJN-CHOKAI");
        assert_eq!(chokai.gun.barrels, 9);
        assert_eq!(
            chokai.gun.mounts.iter().map(|m| m.barrels).collect::<Vec<_>>(),
            vec![1, 2, 2, 2, 2]
        );
        assert_eq!(chokai.dp, 471.);
        let torpedo = chokai.torpedo.as_ref().expect("Chokai torpedoes");
        assert_eq!(torpedo.tubes, 8);
        assert_eq!(torpedo.mounts.iter().map(|m| m.reserve).sum::<u32>(), 8);

        // Wilson — Form 10 p.317 (Dec 41): four singles, four quadruple racks.
        let wilson = hull("IBS-U-USN-WILSON");
        assert_eq!(wilson.gun.barrels, 4);
        assert_eq!(wilson.gun.mounts.len(), 4);
        assert_eq!(wilson.dp, 118.);
        assert_eq!(wilson.max_knots, 38.);
        let torpedo = wilson.torpedo.as_ref().expect("Wilson torpedoes");
        assert_eq!(torpedo.tubes, 16);
        assert_eq!(torpedo.mounts.len(), 4);

        // Monssen — Form 10 p.303 (May 42): four singles, one quintuple rack.
        let monssen = hull("IBS-U-USN-MONSSEN");
        assert_eq!(monssen.gun.barrels, 4);
        assert_eq!(monssen.gun.mounts.len(), 4);
        assert_eq!(monssen.dp, 128.);
        assert_eq!(monssen.max_knots, 35.);
        assert_eq!(
            monssen.damage_speed.iter().map(|row| row.knots).collect::<Vec<_>>(),
            vec![35., 26., 18., 9., 0., 0.]
        );
        let torpedo = monssen.torpedo.as_ref().expect("Monssen torpedoes");
        assert_eq!(torpedo.tubes, 10);
        assert_eq!(torpedo.mounts.len(), 2);
        assert_eq!(torpedo.mounts.iter().map(|m| m.tubes).collect::<Vec<_>>(), vec![5, 5]);

        // Buchanan — Form 10 p.292/p.293 (Mar 42): four singles, two quintuple racks.
        let buchanan = hull("IBS-U-USN-BUCHANAN");
        assert_eq!(buchanan.gun.barrels, 4);
        assert_eq!(buchanan.gun.mounts.len(), 4);
        let torpedo = buchanan.torpedo.as_ref().expect("Buchanan torpedoes");
        assert_eq!(torpedo.tubes, 10);
        assert_eq!(torpedo.mounts.len(), 2);

        // Hull — AF A-19 Farragut: D/Small with 200 yd rudder advance, the
        // printed 0/26/53/79/95/105 damage rows and 5 single 5in mounts.
        let hull_ship = hull("IBS-U-USN-HULL-I");
        assert_eq!(hull_ship.size, "D");
        assert_eq!(hull_ship.turn_advance_yards, 200.);
        assert_eq!(hull_ship.speed_loss_knots, 1.);
        assert_eq!(hull_ship.gun.barrels, 5);
        assert_eq!(
            hull_ship.damage_speed.iter().map(|row| (row.damage, row.knots)).collect::<Vec<_>>(),
            vec![(0., 36.), (26., 27.), (53., 18.), (79., 9.), (95., 0.), (105., 0.)]
        );
        assert_eq!(hull_ship.torpedo.as_ref().expect("Hull torpedoes").tubes, 8);

        // San Juan — Form 10 p.262 (May 42): eight twins, two quadruple racks.
        let san_juan = hull("IBS-U-USN-UNNAMED-T01-R25");
        assert_eq!(san_juan.gun.barrels, 16);
        assert_eq!(
            san_juan.gun.mounts.iter().map(|m| m.barrels).collect::<Vec<_>>(),
            vec![2u32; 8]
        );
        assert_eq!(san_juan.torpedo.as_ref().expect("San Juan torpedoes").tubes, 8);

        // Every period card is fielded: none is parked as stat_verified=false.
        assert!(period_cards().unwrap().iter().all(|card| card.verified));
        // The printed gun table itself is untouched by the mount correction.
        assert_eq!(chokai.gun.damage, vec![26., 20., 17., 15.]);
    }

    #[test]
    fn every_period_hull_has_a_realtime_gun_cadence() {
        let data = data().unwrap();
        let mut world = World::blank(data, 7, 0, "coord", VARIANT, "coord", 0);
        for (slot, card) in period_cards().unwrap().iter().enumerate() {
            let def = data
                .ships
                .iter()
                .position(|ship| ship.id == card.identity)
                .expect("period card is loaded");
            let side = usize::from(data.ships[def].side == "axis");
            let p = P { x: 1_000. + 1_000. * (slot % 6) as f64, y: 1_000. + 1_000. * (slot / 6) as f64 };
            world
                .spawn(def, side, side as u32 + 1, card.ship.name.clone(), p, 0.)
                .unwrap();
        }
        world.gun_streak.resize(world.ships.len(), (0, 0, 0));
        world.surface_damage.resize(world.ships.len(), Default::default());
        world
            .init_realtime(realtime::VERSION)
            .expect("every period hull needs an approved realtime battery");
        assert_eq!(world.ships.len(), 23);
    }

    #[test]
    fn every_merged_hull_has_a_realtime_gun_cadence() {
        let data = data().unwrap();
        let mut world = World::blank(data, 7, 0, "coord", VARIANT, "coord", 0);
        for (slot, card) in merged_cards().unwrap().iter().enumerate() {
            let def = data
                .ships
                .iter()
                .position(|ship| ship.id == card.identity)
                .expect("merged card is loaded");
            let side = usize::from(data.ships[def].side == "axis");
            let p = P { x: 1_000. + 900. * (slot % 10) as f64, y: 1_000. + 900. * (slot / 10) as f64 };
            world
                .spawn(def, side, side as u32 + 1, card.ship.name.clone(), p, 0.)
                .unwrap();
        }
        world.gun_streak.resize(world.ships.len(), (0, 0, 0));
        world.surface_damage.resize(world.ships.len(), Default::default());
        world
            .init_realtime(realtime::VERSION)
            .expect("every merged hull needs an approved realtime battery");
        assert_eq!(world.ships.len(), 91);
    }

    #[test]
    fn merged_destroyers_form_a_lawful_3000_point_duel() {
        let allies = preset(&[
            "IBS-U-USN-WALKE",
            "IBS-U-USN-BENHAM",
            "IBS-U-USN-BARTON",
            "IBS-U-USN-GWIN",
            "IBS-U-USN-LA-VALLETTE",
            "IBS-U-USN-GEARING",
        ]);
        let axis = preset(&[
            "IBS-U-IJN-AKATSUKI",
            "IBS-U-IJN-ASAGUMO",
            "IBS-U-IJN-YUGURE",
            "IBS-U-IJN-MURAKUMO",
            "IBS-U-IJN-AMATSU-KAZE",
            "IBS-U-IJN-ERMA-SHIMAKAZE",
        ]);
        let mut world = World::new_ranked_duel(6124, duel(3000, allies, axis)).unwrap();
        assert_eq!(world.observation(0)["ships"].as_array().unwrap().len(), 6);
        assert_eq!(world.observation(1)["ships"].as_array().unwrap().len(), 6);
        for _ in 0..120 {
            world.advance();
        }
    }

    #[test]
    fn registry_holds_202_playable_hulls_and_eight_collection_identities() {
        let data = data().unwrap();
        assert_eq!(data.ships.len(), 202);
        let table = catalogue().unwrap();
        assert_eq!(table["ships"].as_object().unwrap().len(), 202);
        let collection = [
            "IBS-U-IJN-AMAGI",
            "IBS-U-IJN-AKAGI",
            "IBS-U-IJN-OWARI",
            "IBS-U-IJN-ERMA-IBUKI",
            "IBS-U-IJN-ERMA-KURAMA",
            "IBS-U-IJN-ERMA-GOKASE",
            "IBS-U-USN-MIDWAY",
            "IBS-U-IJN-XIFENG",
        ];
        for identity in collection {
            assert!(!data.ships.iter().any(|ship| ship.id == identity), "{identity} must stay collection-only");
            assert!(display_name(identity).is_none(), "{identity} has no registered name");
            assert!(table["ships"].get(identity).is_none(), "{identity} has no point row");
            let fleet = preset(&[identity, "IBS-U-USN-FLETCHER", "IBS-U-USN-PERKINS"]);
            assert!(
                roster(data, &fleet, 3000).is_err(),
                "roster() must reject collection-only {identity}"
            );
        }
        // The seven capital-adjacent hulls are selectable under their tiers.
        assert_eq!(class_for("IBS-U-IJN-ERMA-SHINANO"), "erma_ijn_yamato_bb");
        assert_eq!(display_name("IBS-U-IJN-ERMA-SHINANO"), Some("信浓"));
        assert_eq!(display_name("IBS-U-USN-WALKE"), Some("沃克"));
        // BC counts as a capital slot, CB/AV against the cruiser slots, so all
        // three new kinds are fieldable in their declared tiers.
        let bc = preset(&["IBS-U-USN-UNNAMED-T01-R06", "IBS-U-USN-FLETCHER", "IBS-U-USN-PERKINS"]);
        assert!(roster(data, &bc, 10000).is_ok(), "BC must fit the 10000 tier");
        let heavy_axis = preset(&["IBS-U-IJN-NAGATO", "IBS-U-IJN-KAGERO", "IBS-U-IJN-MUTSUKI"]);
        assert!(World::new_ranked_duel(6126, duel(10000, bc, heavy_axis)).is_ok());
        let cb = preset(&["IBS-U-USN-ERMA-ALASKA", "IBS-U-USN-FLETCHER", "IBS-U-USN-PERKINS"]);
        assert!(roster(data, &cb, 3000).is_ok(), "CB must fit the 3000 tier");
        let av = preset(&["IBS-U-IJN-CHITOSE", "IBS-U-IJN-KAGERO", "IBS-U-IJN-MUTSUKI"]);
        assert!(roster(data, &av, 3000).is_ok(), "AV must be fieldable");
        assert!(World::new_ranked_duel(6125, duel(3000, cb.clone(), av)).is_ok());
    }

    #[test]
    fn declared_tiers_fit_the_cheapest_legal_fleets() {
        let data = data().unwrap();
        for side in ["allies", "axis"] {
            let mut dds: Vec<(&str, u32)> = data
                .ships
                .iter()
                .filter(|ship| ship.side == side && ship.kind == "DD")
                .map(|ship| (ship.id.as_str(), point_value(ship)))
                .collect();
            dds.sort_by_key(|(_, points)| *points);
            assert!(dds.len() >= 6, "{side} needs six DD cards for the 3000 tier");
            let six: Vec<String> = dds.iter().take(6).map(|(id, _)| (*id).into()).collect();
            let cost: u32 = dds.iter().take(6).map(|(_, points)| *points).sum();
            assert!(cost <= 3000, "{side} six cheapest DDs cost {cost}");
            let fleet = RankedFleet {
                ship_ids: six.clone(),
                leader_id: six[0].clone(),
                ai_profile: "coord".into(),
            };
            assert!(roster(data, &fleet, 3000).is_ok(), "{side} six-DD 3000 fleet must pass");
        }

        // A 10000-point fleet can carry two battleships and four destroyers.
        let mut bb: Vec<(&str, u32)> = data
            .ships
            .iter()
            .filter(|ship| ship.side == "allies" && ship.kind == "BB")
            .map(|ship| (ship.id.as_str(), point_value(ship)))
            .collect();
        bb.sort_by_key(|(_, points)| *points);
        let mut dds: Vec<(&str, u32)> = data
            .ships
            .iter()
            .filter(|ship| ship.side == "allies" && ship.kind == "DD")
            .map(|ship| (ship.id.as_str(), point_value(ship)))
            .collect();
        dds.sort_by_key(|(_, points)| *points);
        assert!(bb.len() >= 2, "the 10000 tier needs two BB cards");
        let mut ids: Vec<String> = bb.iter().take(2).map(|(id, _)| (*id).into()).collect();
        ids.extend(dds.iter().take(4).map(|(id, _)| (*id).into()));
        let cost: u32 = bb.iter().take(2).map(|(_, points)| *points).sum::<u32>()
            + dds.iter().take(4).map(|(_, points)| *points).sum::<u32>();
        assert!(cost <= 10000, "two BBs and four DDs cost {cost}");
        let fleet = RankedFleet {
            ship_ids: ids.clone(),
            leader_id: ids[0].clone(),
            ai_profile: "coord".into(),
        };
        assert!(roster(data, &fleet, 10000).is_ok(), "two-BB 10000 fleet must pass");

        let too_many = RankedFleet {
            ship_ids: dds.iter().take(7).map(|(id, _)| (*id).into()).collect(),
            leader_id: dds[0].0.into(),
            ai_profile: "coord".into(),
        };
        assert!(roster(data, &too_many, 3000).is_err(), "the 3000 tier caps at six hulls");
    }
}
