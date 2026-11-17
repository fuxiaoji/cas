# 单人打捞动态天气 v1

规则登记：`CAS-SALVAGE-WEATHER-01`，内容版本 `salvage-weather-v1`。仅用于新建的架空打捞航次，不改变历史战役、序章、教程或旧存档的固定环境。

## 已核依据与实现范围

2026-11-11 目视英文《Command at Sea Fifth Edition》PDF 49、50、58（印刷 5-12、5-13、6-2），原件只读，渲染核页留在 `artifacts/weather/source/`。沿用既有 `data/rules/optical-v2.json`，不改变任何表格单元格。

| 原页内容 | 本轮使用 | 边界 |
| --- | --- | --- |
| PDF 50，Surface-to-Surface Visibility，100/40/20% 档与全尺寸表 | `World::environment` 下发当前能见度；现有逐秒目视、接触保持/丢失、鱼雷发射与尾迹观察直接消费此值 | 预设雨40%、雾20%是架空场景作者选择，不宣称天气名称与能见度档位是原书固定映射 |
| PDF 58，Gunfire Hit Chance Modifiers，能见度≤40%为−2，≤20%为−4 | 新天气版本下日间炮击复用已有 `night_gun_modifier` 的互斥档位；瞄准、AI门槛、实际炮击统一通过 `gun_values` | 不叠加两个档位，不改命中表。已有射程/炮组倍率继续生效。打捞没有雷达火控配置，不新造雷达豁免 |
| PDF 49，§5.4.2 Clouds | 云量变化只进入视觉；晴、多云、阴天均保留100%水面能见度 | 原页主要是舰空/空空通视，不能据云量单独减少舰舰视距 |
| PDF 49，§5.4.3 Squalls | 未实现该规则；本次只有全区域的架空天气阶段 | 未生成原页6千码圆形局部雨阵、强度骰及随实际风漂移。历史局部天气仍保留原有缺口 |

海况始终为原打捞值2，光照始终白天。风向/速度仅用于画面云雨漂移，不影响航速、炮弹、鱼雷、烟幕或航空。雷达雨杂波虽有已核独立函数，打捞模式没有实装雷达，因此本轮不启用。不得将该实现登记为完整气象、全海况运动或全规则天气裁决。

## 架空天气过程

`data/salvage/weather-v1.json` 固定场景参数。首段晴朗，每240模拟秒切换；首个后继是多云，此后根据带种子的邻接表选择，无同段反复抽签。晴/多云/阴不减少水面能见度，雨40%、雾20%。固定240秒是演出与行动节奏参数，不是CAS天气生成概率。

每段结束前45模拟秒发一次公开预报事件，开始云雨雾视觉过渡。到 `rules_change_tick` 才同时切换 `environment.visibility/precipitation`。过渡期间显示的旧能见度仍是实际裁决值，`next_visibility` 是预报值。阶段开始发一次生效事件，两类事件均有上述规则登记号且双方可见，不携带敌方单位或未来命令。

随机流由 `seed XOR 0xa197725b46d380e1` 独立构建；不使用 `World.rng/optics_rng/surface_critical_rng`。天气变化会通过真实视距与命中条件间接改变战斗结果，但天气生成自身不挪用战斗骰。时间仅来自权威 `World.tick`；观察、客户端帧率、墙钟、暂停期间重绘都不能推进天气。

## 保存与公开接口

新航次的 `start.weather` 写入版本；加载无该字段的旧存档时不补版本，重演保持固定晴天。未知天气版本拒绝加载。时间线由存档原种子、冻结版本和回放时钟重建，无客户端重新抽天。存档仍为原有命令日志重演，不新增另一套快照。

只有启用天气的打捞观察包含 `weather` 对象；历史和旧航次完全不添加此字段。原 `environment` 四字段结构保持不变。

| 字段 | 意义 |
| --- | --- |
| `version` | `salvage-weather-v1` |
| `kind` / `next` | 当前有效天气 / 下一阶段天气：`clear/cloudy/overcast/rain/fog` |
| `phase_started_tick` / `phase_ends_tick` / `rules_change_tick` | 模拟秒；后两者相等 |
| `transition_seconds` / `transition_progress` | 45秒 / 段末45秒的0..1视觉进度 |
| `cloud_cover` / `rain_intensity` / `fog_density` | 0..1，仅视觉参数，权威按当前tick插值 |
| `visual_wind_heading_deg` | 北0°，顺时针，仅画面漂移方向 |
| `visual_wind_speed` | 世界米/模拟秒，仅画面平移参数，固定12；不是已实现物理风速 |
| `visibility` / `next_visibility` | 当前有效CAS能见度百分档 / 下一档 |

## 验证门

`src/salvage_weather.rs` 定向测试覆盖独立随机流、全部天气可达、预报/生效边界、只读观察不推进、新旧保存及继续重演、历史/教程无动态天气、雨雾瞄准概率与实际炮弹阈值一致、低能见度下真实接触丢失。原生/WASM与真实Godot时间/暂停/视觉证据由本轮运行回执补充，不以该文档自身替代实际验收。

2026-11-11 原核实测：`cargo test --release --locked` 152项加stdio桥接1项通过；其中打捞/天气17项，天气新增5项。`scripts/verify-dynamic-weather.mjs` 3个新航次的222条请求，逐段覆盖预报/生效、阶段中加载和重演；另3个旧航次使用修改前原生exe在600秒生成的真实快照，修改后观察canonical JSON一致，继续航行仍固定晴天。全部6组原生/WASM一致，回执 `artifacts/weather/receipt.json`。既有24组历史/演习/教程/序章/AI对照与重演通过，见 `artifacts/weather/fixed-scenarios-parity.json`。Godot经济音频56项通过；实际视觉与完整客户端回归由主集成另附，不将原核只读测试冒称GUI暂停验收。
