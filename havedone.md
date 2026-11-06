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
