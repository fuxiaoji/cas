# 铁底湾手游内容与 CAS 实时战斗的接线

铁底湾 0.6.9（`48385c8`）是进程和内容结构基线；实际代码从该对话的工作树 `F:/Codex/worktrees/android-mobile/铁底湾` 的 `3ba9c5b` 直接迁入。CAS 英文五版及适用想定是战斗数据基线。保留旧角色和关卡 ID 作为迁移键；CAS 用户、经济和存档使用独立数据。

| 迁入代码 | CAS 落点与适配 |
| --- | --- |
| `mobile/src/progression/GrowthPort.tsx` 的母港区、`growth.css` | `client/src/GrowthPort.tsx`；沿用原结构、值更舰、海报和底部入口，由独立 CAS 存档提供数据。 |
| `mobile/src/online/AccountPanel.tsx` 的登录区、`account.css` | `client/src/Login.tsx`；本机登录和注册接 `account.ts`。账号之间隔离，首个账号接续本机旧 CAS 离线档。 |
| `mobile/src/prologue/script.ts`、角色立绘及结尾 CG | `client/src/prologue/`；保留剧情与选择。开场是有标记的真实 CAS 5 对 5 演示，三段实操在同一内核完成；具名五舰和原大舰队尚未完整装入内核。 |
| `mobile/src/activities/ActivityCenter.tsx`、`activity.css`、`check-in.ts`，以及 `mobile/src/meta/store.ts` 周奖励 | `client/src/activities/`；已接前六天的奖励、周补给商店和挑战奖励。第七天北卡罗来纳在对应 CAS 舰卡及战列舰能力核验后启用。 |
| `mobile/src/economy/ShipArrival.tsx`、`ship-arrival.css` | `client/src/RecruitArrival.tsx`；复用到港演出。只在实际征募入账后显示当次 CAS 舰娘、兑换勋章和保底结果。 |

| 原手游模块 | 保留的体验 | 接到 CAS 的验收条件 |
| --- | --- | --- |
| 母港、大厅、舰库、编队、征募和邮箱 | 初始舰队、值更舰、双池双券、保底、邮件和已解锁 AI；进港能继续上次进度。 | 已有母港、初始舰队、离线体验池、预设、部分商店和活动。原舰池、指定兑换、三舰礼包、邮箱和正式经济仍需舰卡、货架或账号服务。 |
| 战役与越级挑战 | 同盟／轴心双线、三档难度、评级，历史编制借舰；挑战和竞技使用个人舰队。 | 按[战役原页对照](campaign/source-crosswalk.md)载入 CAS 编制、海域、目标和特例，不能只换海图或舰名；另核周本和首通奖励。没有原书对应的旧作原创关，保持原剧情 ID，以明确标注的 CAS 架空想定承接。 |
| 对战大厅与约战 | 先免费约战与 3000 分非排位，再按旧方案排位；10000 分保留战列舰和护航编制。 | CAS 实战重定舰价、用原生同一内核做权威战局。排位仍由玩家确认服务器 AI 建议。跨端重连、本席回放和结果幂等均实测后再开放。 |
| 日间教学与夜战教学 | 沿用原夜战教学 `CAMP-NIGHT-01` 的学习顺序，以实时操作取代格子操作。 | 昼间和夜间教学已通过浏览器实操。夜战使用独立规则版本，以 CAS 内核实际照明、炮击和鱼雷离管事件推进；不要求炮弹或鱼雷命中。 |
| 开场序章 | 保留舰队演出、五位初始舰娘、对白选择、选领舰、教学和一次性奖励。 | 对照旧 `docs/mobile-prologue-plan-20261105.md` 与 `mobile/src/prologue/script.ts`。大编队演出用实际 CAS 对局录制；交互部分检验多航点、同步、拖炮雷和接管。Fletcher、Maury／Gridley、Perkins／Drayton／Lamson 的 Mahan 系在美舰 Annex A PDF 20–22（A-17–19）有定位；仍需冻结演出时期并核对舰号与实装，尤其 Lamson 的后期特改。不能用现有四张舰卡替代旧序章五名角色或全舰队。 |
| AI 指挥官 | 保留原作人设、头像和擅长的任务。 | 旧 `tactical.py` 与 `formation_tactics.py` 的搜索、接近、交战、屏护、雷击和撤退条件转为实时状态；旧六角距离不作为 CAS 参数。全程使用本席观察和同一命令校验。 |

指挥官语音的事件名对照旧 `mobile/src/events.ts`、`mobile/src/sound.ts` 及 `mobile/public/audio/manifest.json`。本地试玩的舰队电台使用旧作按阵营播放的通用录音，按局、席位和本席事件 ID 去重；重演、跳转和回到前台不会重新播旧事件。鱼雷发射迹象只给通用提醒；确认尾迹后由内核以最近己舰为参考给方向。后台或演习暂停时暂停播报。三位指挥官专属音频和 BGM 未迁入。阵营录音只在显式开启本地试玩音频的构建中打包，标准生产构建不含这些录音。

舰况立绘以稳定 ID 匹配。圣乔治角与通道行动的 18 艘具名舰使用原手游的对应原图；弗莱彻、克利夫兰、阳炎、川内的通用演习舰另用标明身份的舰型代表。原路径、ID、哈希和本地内测范围见[立绘台账](../client/src/assets/portraits/ledger.json)。

新局默认由 `cas-realtime-v7` 的炮座状态决定能否开火和何时开火。炮弹飞行、横转和装填属于 RTS 改编。火力仍用 CAS 射程、穿深、命中与伤害表裁决，已取得资料的炮座有历史参考射速。存档按各自版本重演。鱼雷速度、航程和命中由核验表裁决，尾迹只显示本席已观测到的航段。[实时主炮登记](rules/realtime-gunnery-sources.md) · [覆盖台账](rules/coverage.md)

独立[免费内测服务](../server/README.md)已有账号、双池双券、保底、邮箱、签到、免费商店和圣乔治角双线权威 PvE；浏览器已验账号重登后恢复同局，服务测试另验战果入账。线上舰库目前只承诺收藏，未接完整个人舰队出航和竞技。两个平台的试玩包默认离线，联机浏览器只在测试服务启用时开放。
