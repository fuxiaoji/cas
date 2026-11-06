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
