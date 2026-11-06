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

## 2026-11-06｜主炮原页与圣乔治角炮表复核

- 核对五版 §2.2.2、§2.3.4、§6.1、玩家表和四型舰卡，记下原书的火力窗口、炮座射界及弹种表。§6.1.5 是轻防空对海；主炮装填、横转和飞行秒数单列为 [RTS-GUN-04 改编](docs/rules/realtime-gunnery-sources.md)，不写入历史舰卡。
- 圣乔治角时期包升级至 `cas-cape-st-george-1943-hulls-v2`。逐列复核七个 Annex C 炮弹数据行，更正美舰 Mk30 高爆弹近／中档伤害为 18／15 DP。[战役资料检查](scripts/check-campaign.py)和首发舰表数据检查通过。此次只验证资料；历史关出击仍受运输雷装、撤离与夜战裁决差额约束。

## 2026-11-06｜Mk4 接入 1943 实时雷达演习

- `cas-realtime-v4` 雷达演习仅给已核实装的弗莱彻启用 Mk4。炮击须有本舰目视、可用前向指挥仪和合法雷达视线；本舰射击时才应用 +2 和低能见度豁免。炮口闪光、共享报告、纯搜索回波、尾向及关机／损伤均不误用这项加成。见[原页、接线与差额](docs/rules/radar-source.md)。
- Rust 38 项通过（雷达专项 7 项）：相同 D100=60 实际开火，开启 Mk4 命中扣伤、关闭落空，标签只出现在开火方战报；开关及 v3 旧局可重演。原生种子 6106 的 v4 雷达演习双方均有受损，双席完成并逐项重演一致，同盟战报 85 次标注 Mk4，轴心 0 次；两席结果均为轴心 2 比 1。资料脚本通过 6 份原件哈希、10 艘历史配置和 12 条算例。上述不含历史关或安装包验收。

## 2026-11-06｜逐秒主炮、旧部署和手游表现

- 新局默认 `cas-realtime-v4`。玩家可随时下令或取消尚未发射的炮座，撤销 AI 的待发炮击会接管炮击任务。炮座有实际转向和装填时钟，已知舰艇可挡住射线。炮弹按距离和有效弹速飞行，到达后处理命中；鱼雷尾迹显示本席确认的航段。[实时手势验收](artifacts/client/final-v4/browser-realtime/browser-receipt.json)中预计和实际首发均为第 247 秒，弹着为第 284 秒，可见鱼雷尾迹超过 1.2 公里。
- 全 16 个原想定／32 个双线关位均有可查看的档案：11 份 CAS 原书记录，5 份旧手游相对阵位和任务，共 159 个开局舰船部署；午夜关另存原版默认整列后的 91 舰。两侧开局与铁底湾 0.6.9 固定快照回放对照通过。[旧部署记录](docs/campaign/legacy-deployment.md)。历史与回退想定依然 **0 个通过出航验收**，未复用旧作武器数据或给未核舰套舰卡。
- 复用原手游征募到港演出，用实际征募凭据展示、跳过及回看，实测不会重复扣券；通过[离线与挑战回归](artifacts/client/final-v4/browser-offline/browser-receipt.json)。[序章与夜战回归](artifacts/client/final-v4/browser-story/browser-story-receipt.json)完成原剧情分支、三段真实手势、一次性奖励及夜战 10 步，照明 540 秒、炮击 543 秒、鱼雷 900 秒。
- [本地舰队电台](artifacts/client/radio/browser-receipt.json)按阵营播本席真实事件，验过后台暂停、回放不重播、音量和关闭。普通生产包含 0 段旧录音；显式本地试玩构建含 16 段与旧文件哈希相同的通用电台录音。指挥官专属录音和 BGM 未迁入。
- Rust 39 项测试通过；[原生与 WebAssembly](artifacts/parity-v4-final-20261106.json)九场对局及同席重演逐项一致，包含实时昼战、照明和 Mk4。旧版炮战和存档继续按各自版本运行。[规则覆盖](docs/rules/coverage.md)和[手游迁移](docs/mobile-migration.md)维护未完成项。
- [Windows WebView2](artifacts/windows-smoke-v4-legacy-radio-20261106-174104.json)与[Android 飞行模式模拟器](artifacts/android-smoke-v4-legacy-radio-20261106-174126.json)实装通过离线登录、母港、战役档案、实时演习、保存与重演。Android 逐项打开 11 份原页与 5 份回退档案，并验证横屏触控和后台取消。两端 360 秒状态一致，[35 个共用包内文件](artifacts/packaged-shared-web-v4-legacy-radio-20261106-174126.json)逐字节相同。Android 实体机未验。

| v4 离线试玩包（含本地电台） | SHA-256 |
|---|---|
| [Windows x64 ZIP](release/CAS-Stage0-win-x64-20261106-174104-420.zip) | `aa30095c1af72a5655407eb1f6ace4f02b964d3a55490bd4273071cc023843dc` |
| [Android APK](release/CAS-Android-0.1.0-preview-20261106-174126-905.apk) | `40911056ea8041882e21629c593dfcbc8a3ffd30d756dd1b877a75c3513582ee` |

## 2026-11-06｜弗莱彻战败 CG
以用户确认的项目原始弗莱彻立绘为参考，内置 imagegen 单独绘制十张 1536×1024 PNG。逐张目检角色、动作、表情与构图；验证十份文件内容互异且 PNG 与 ZIP 可读。[素材包](artifacts/fletcher-defeat-cg-20261106.zip) · [提示词和分镜](artifacts/fletcher-defeat-cg-20261106/prompts.md)。独立美术候选素材，未接入发行包。

## 2026-11-06｜双线战役可玩、具名舰况和独立联机内测

- 新增 `cas-campaign-v5`。[圣乔治角](docs/campaign/cape-runtime-sources.md)按原页放入十艘具名舰和四个纵队，实际雷达炮击、鱼雷命中和撤离均可复盘；同盟种子 6106 击沉目标获得决定性胜利，轴心同种子换两条航路使五舰越线并获得决定性胜利。直航雷可用本舰连续两窗直接雷达观察解算，单点、共享点与关机后的失效样本不通过；无效发射不扣雷。三艘运输舰未核定载荷和雷装，当前禁雷。
- [通道行动](docs/campaign/channel-runtime-sources.md)找不到同一 CAS 想定，保留旧作八舰阵位、航向、开局速度、四回合和任务，使用同期 CAS 舰体、武器和损伤。测试同盟达成战略胜利，轴心三舰全部存活且未降至目标航速、取得战术胜利并有实雷命中。J/K 轮机共舱特例据五版 §8.3（PDF 107）和《Home Fleet》A-36 生效；实测普通轮机临界由一档变两档、锅炉爆炸由两档变四档，直接伤害不加倍。原剧本的逐舰备雷、雷达等未补值。两关开放同盟与轴心共四个关位，其余 14 场／28 个关位仍只显示档案。
- [浏览器战役验收](artifacts/client/campaign-final-v5/browser-receipt.json)走过两关双线、三档选项和存读档重演，逐舰解码 18 张原手游立绘并核验 SHA-256。圣乔治角同盟实战三星奖励到账 600 补给币、4 常驻券、10 勋章；重启和换难度均不能重复领。三档目前对应不同敌方 AI，尚无完整的难度平衡验收。
- [独立账号服务](server/README.md)迁入双池、双券、保底、邮件、免费商店和七日签到（第七日北卡罗来纳仍待核准舰卡）。圣乔治角双线使用原生 CAS 服务权威推进、只发本席观察，并用真实战果计战役及周任务。11 项服务测试通过。[联机浏览器凭证](artifacts/client/online-check-in/browser-receipt.json)包含签到、重登防重、邮件、征募、兑换和回到同一权威战役。当前只为本机回环内测；个人舰队线上作战、排位、支付和公网部署均未开放。
- Rust 44 项测试通过；[原生与 WASM](artifacts/native-wasm-campaign-v5-final-20261106.json)13 场完整对局和同席重演逐项一致。[Windows](artifacts/windows-campaign-v5-final-20261106.json)与 [Android 飞行模式模拟器](artifacts/android-campaign-v5-final-20261106.json)实装验证离线登录、母港、两关开局及重演，Android 另验证触屏取消与切后台取消。两包 [36 个共用文件](artifacts/packaged-shared-web-v5-final-20261106.json)逐字节一致，均未包含规则 PDF。Android 实体机未验。[序章与夜战教学](artifacts/client/story-campaign-build/browser-story-receipt.json)及[实时主炮、弹道、可见雷迹](artifacts/client/campaign-v5-realtime/browser-receipt.json)也通过回归；序章开场仍是标明的 5 对 5 演示。

| 当前离线试玩包 | SHA-256 |
|---|---|
| [Windows x64 ZIP](release/CAS-Stage0-win-x64-20261106-185902-769.zip) | `05ae4a9538b127ffc54fa8d5f2ba47a9b0f75800534aa816827d6246e2c13359` |
| [Android APK](release/CAS-Android-0.1.0-preview-20261106-185924-381.apk) | `0fbae65cb9cc1adaae3b267f25b44d60204523d10a303c6d0f8c81c3b61df93d` |
