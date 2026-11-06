# 验证记录

## 2026-11-06｜Windows 昼战试玩与 Android 单机预览

实现基线：规则与内核 `c611515`，界面及运行包 `5e229ee`。独立仓库、应用名、存档、资源；原 PDF 和参考项目未改动。

- CAS 五版昼间水面裁决子集：四种首发舰型、两种编队机动、多航点预览、射界、计划和反应炮击、直航鱼雷、基本关键损伤、火灾／进水和损管。三种状态机有搜索、接敌、交战和撤离状态，玩家可按任务接管。
- `cargo test --release --locked`：14 项通过。资料检查核对了四份原件 SHA、四种舰型、炮雷射界、159 行鱼雷命中表及来源算例。
- `scripts/verify-duels.py`：六个种子、十二个席位投影。两方在每场均有实际开火、命中和受损，另一席复跑及重演结果相同。种子 6106：同盟 5 比 3，双方 60／52 次炮击；轴心 8 次鱼雷齐射，1 次命中。[对局摘要](artifacts/ai-exchange-20261106.json)。
- Edge 界面走查：同一场两种多航点机动、移动航点、拒绝不合法草稿、拖炮实际射击、取消不下令、推荐鱼雷方向 115° 手调为 113° 后实际发射；740×360 横屏触控可提交航路。[操作记录](artifacts/client/port/browser-receipt.json)。
- 母港预览：实际完成七项教学、一次性初始舰队、UP 征募、领舰预设、AI 解锁和 3 对 5 挑战；刷新恢复舰队、券余额和战局，挑战完成后常驻券与 AI 权益只领取一次。仅发布四种已核验舰型的体验池，未启用真实收费或账号资产。
- 最终 Windows EXE 和 Android 隔离模拟器均渲染实际海图和母港，存档、重演及 360 秒本方观察摘要一致。Android 在飞行模式运行，验证后台中断拖拽不下令、重启恢复；尚未验收实体 Android 手机。原生 Rust 和 WebAssembly 的两场 5 对 5 与一场 3 对 5 完整战报、结局和重演一致。

交付：

| 包 | SHA-256 |
|---|---|
| [Windows x64 试玩 ZIP](release/CAS-Stage0-win-x64-20261106-135611-455.zip) | `a29e305b39550cb10656c6b9cfd6ddea351a2fa95d3f63c38513f4ea752f57a4` |
| [Android 单机预览 APK](release/CAS-Android-0.1.0-preview-20261106-135643-378.apk) | `7f4b08bac530bdd1e2bb95e0b7c6530898c7bae6ee4ff539f0fb3c8395b7531f` |

运行证据：[Windows](artifacts/windows-final-smoke.json)、[Android](artifacts/android-final-smoke.json)、[原生与 WebAssembly 比对](artifacts/native-wasm-final-parity.json)。

阶段 0 可试玩；阶段 1 已有离线闭环预览，待实体机及正式内容验收。完整双线战役、夜战、更多舰娘与 AI 风格、跨端账号／匹配／排位及真实支付仍在后续阶段。CAS 规则未覆盖项见 [规则台账](docs/rules/open_questions.md)。

## 2026-11-06｜战斗反馈、夜航和历史档案 v2

- 本席命中／受损／起火／关键损伤／沉没等提示不拦截手势；炮弹按实体飞行并画弧，鱼雷用真实直航轨迹和尾迹。炮塔在瞄准及实际炮击时按对应炮位的射界转动。选舰显示炮雷最大射程和舰况，四种首发舰型用已核原作 ID 的舰型代表立绘。740×360 横屏仍可看舰况、选舰和取消。见[界面验收](artifacts/client/visuals/browser-visual-receipt.json)及[完整离线流程](artifacts/client/regression-v2/browser-receipt.json)。
- v2 昼夜都按 CAS 五版检定鱼雷发射迹象和尾迹；夜航演习还接入能见度、速度、炮口闪光、起火和夜间炮击修正。发射迹象不揭露发射舰或活跃轨迹。照明数据已录入并通过算例，照明命令、雷达及可选分级识别仍未开放。[光学规则](docs/rules/optical-v2.md)与[覆盖台账](docs/rules/coverage.md)分别列出调用和缺口。
- [水面雷达源数据](docs/rules/radar-source.md)已核 6 份原件、圣乔治角十艘舰的候选实装和 12 个算例。夕雾同期旧舰卡与 Annex A 冲突，保留原写法等待裁决。此批仅录源数据，未接入试玩包。
- 对照原手游 16 个想定／32 个双线关卡；11 个同一历史交战、1 个相关想定、3 个旧作架空或无对应、1 个未定位。圣乔治角、库拉湾、霍腊纽已录入原页数据并列入档案，韦拉拉韦拉原页数据在发包后录入待下一档案版本。未将任一历史场景标为可打。[战役对照](docs/campaign/source-crosswalk.md)；脚本验过铁底湾固定快照、10 个原件哈希与全部 4 份录入文件。
- `cargo test --release --locked` 通过 22 项；7 场完整昼夜对局、14 个席位投影均有双方开火命中并可重演，昼夜均有实际雷击战果。[对局摘要](artifacts/battle-v2/ai-exchange-v2.json)。四场完整对局含夜航、挑战的原生与 WebAssembly 逐项一致：[比对](artifacts/parity-v2-final-20261106.json)。
- 最终 [Windows WebView2](artifacts/windows-smoke-v2-final-20261106.json) 与 [Android 横屏模拟器](artifacts/android-smoke-v2-final-20261106.json) 通过实际离线启动、舰况立绘、夜航、母港、保存恢复和重演，360 秒状态一致。Android 还通过触屏取消和后台中断；实体机未验。当前包用于本地测试。

| v2 本地测试包 | SHA-256 |
|---|---|
| [Windows x64 ZIP](release/CAS-Stage0-win-x64-20261106-144743-162.zip) | `77503eb2752a9ac0386e55020f4ee0e6ba0fb6179dde86f148bdadb04aee4618` |
| [Android APK](release/CAS-Android-0.1.0-preview-20261106-144805-185.apk) | `c2b35d2b8c64e160034b0c6ac46421c910a46fa5dda6f0a96d6693597566a2ec` |

大厅和模式沿用铁底湾手游；夜战教学、开场序章、正式大厅和配音播放待接。当前语音触发键已随本席实际战报输出，未绑定旧音频。接线、规则边界与阻塞见[手游迁移](docs/mobile-migration.md)。

## 2026-11-06｜独立雷达演习的权威内核

- `cas-radar-v3` 独立虚构演习启用已核 1943 弗莱彻水面搜索实装 SG／SC-2。每舰按设备获取和保持接触，迟一探测窗转发冻结位置，支持开关、海岸遮挡、已核传感器失能及搜索雷达炮击。接触编号只在本席有效，画面数据不含敌舰身份、航向、航速或真态弹道。旧 v1/v2 及其安装包保留原版本。
- `cargo test --release --locked radar::` 通过 6 项，包括运行中的实际炮击造成受损、双盲、地平线、杂波、次窗分享、关机重演和 Mk4 计算。`python data/rules/check_radar_source.py` 核过 6 份原件、10 艘圣乔治角舰和 12 条原表算例。原生 `cas-sim demo 6106 allies radar`／`axis radar` 两席跑完整局并重演，均为同盟 4 比 0；同盟 63 次开炮，其中 60 次用直接雷达，轴心 49 次开炮，两边均有受损记录。
- Mk4 火控只实现计算和边界用例；尚不用于对局。雷达演习尚无浏览器大厅入口；现有 Android/Windows 包未更新。历史关、探照灯及其他夜间范围见[夜战裁决差额账本](docs/rules/night-gap.md)。

## 2026-11-06｜原手游母港、CAS 序章与夜战教学

- 从铁底湾手游工作树直接迁入母港组件、样式、夜海底图、登录界面、序章脚本及素材、七日签到页面。登录首屏使用独立本机账号，成功后进入原母港；不同本机账号的舰库、活动、战局和序章进度隔离。沿用现有 CAS 四种舰型的体验舰库和招募池。新增补给商店周券与挑战复战：真实完成五局，首通单领，重复四局最多领三次，每次两张常驻券；挑战立即重启恢复、周补给与签到幂等均通过。[离线验收](artifacts/client/final-offline-v3/browser-receipt.json)。
- 保留《未明的海》的剧情分支、领舰选择、人物与结尾 CG。开场当前为真实 CAS 5 对 5，原具名大舰队仍待舰卡与部署。浏览器走通三段实时实操和一次性见面礼；夜战十步完成，模拟第 360 秒取得接触、第 540 秒照明起亮、第 720 秒炮击、第 900 秒鱼雷离管。[序章与夜战验收](artifacts/client/final-story-v3/browser-story-receipt.json)。
- 海图演习可选择 1943 雷达；舰况可开关本舰设备，回波仅显示本席有权知道的数据。炮雷实体、重要事件提示、炮塔旋转、范围圈和舰娘舰况仍通过浏览器复核。照明弹和水面搜索雷达是各自独立的规则版本，旧战局继续按原版本重演。[战斗验收](artifacts/client/final-visuals-v3/browser-visual-receipt.json)。
- 双线 32 个旧关位已可查阅；16 个不同想定中有 11 个与 CAS 原书同一历史交战，均已录入并逐个验证详情显示；其余 5 个保留为相关、原创或未定位。210 个旧舰身份已登记，圣乔治角十艘的时期配置和序章五舰的有日期原页已核。圣乔治角双方胜利规则已写成可测试判定；历史关 **0 个开放出击**。[战役对照](docs/campaign/source-crosswalk.md)。
- Rust 32 项测试通过；原生与 WebAssembly 的六场完整对局与本席重演一致，包括实际照明和雷达炮击。[跨内核验证](artifacts/parity-v3-final-20261106.json)。Windows WebView2 和飞行模式 Android 模拟器验过注册、登录、母港、档案、存档、恢复和重演；Android 另外验证了触屏取消和切后台。两端包内 18 个共用文件逐字节一致。Android 实体机尚未验收。

| 离线试玩包 | SHA-256 |
|---|---|
| [Windows x64 ZIP](release/CAS-Stage0-win-x64-20261106-160346-708.zip) | `f3ead141edf65da3184353c03db192ea23ee8792f3d5996b7df8c945648672a1` |
| [Android 调试 APK](release/CAS-Android-0.1.0-preview-20261106-160408-960.apk) | `20e22656654b022cf357bec24220aa99059d82bc25ed56d4286a60cf8935b68c` |

包体验收：[Windows](artifacts/windows-smoke-campaign-all11-20261106.json)、[Android](artifacts/android-smoke-campaign-all11-20261106.json)。[规则覆盖](docs/rules/coverage.md)和[手游迁移记录](docs/mobile-migration.md)列出尚未启用的完整舰表、机制、原手游经济和在线服务。
