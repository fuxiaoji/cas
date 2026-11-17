# CAS 海图指挥台

> **专有源码 / Proprietary Source — All Rights Reserved.** 本仓库仅允许在 GitHub 上浏览；禁止运行、复制、下载、修改、分发、商用或用于训练。详见 [LICENSE](LICENSE)。
>
> 为控制仓库体积与素材版权，本仓库不包含 `godot/assets/`（约 1.2 GB 二进制美术资源）、`docs/art/`、`output/`、`packages/` 与构建目录。

陆地三维重构第二轮可独立查看：双击 `CAS-Land-Art-Demo.cmd` 运行海岸样区，`CAS-Coast-Review.cmd` 打开实际截图和动态海浪图册。新增废土工业/遗迹、围墙工事、八类3D载具，以及沼泽河谷/山脊/海崖。它是隔离美术样区；正式家园、搜打撤和海战地图统一仍按[接入计划](docs/design/coastal-wasteland-followup-20261116.md)推进。[本轮说明](docs/development/coastal-wasteland-demo-20261116.md)。

当前开发主线是 Godot 4.7.2 原生客户端与单人搜打撤，使用同一 Rust CAS 裁决内核。Windows 本机双击 `CAS-Godot.cmd` 启动，不依赖 PowerShell 脚本权限。Godot 项目、操作流程、验证方式与交付边界见 [Godot 试玩说明](godot/README.md)；总体任务见 [迁移计划](docs/development/godot-migration-plan.md)。本次 Godot 版尚未交付 Android 安装包。

新增母港「返航灯岛」：原创教学与两张CG、程序海岛生产/建设/驻防、三座本地人机岛及海陆空协同行动。二十名战术人格完成原创轻装动漫立绘，首五支可实战，支持真实运输/弹药取舍、舰炮支援、机降、搜索和撤收。每个机器人身体都有女性化外表，同一部队共享一个“她”。十一首原创BGM及横向蹦跳转场已接入；入口、编辑路径和边界见[家园与两栖试玩说明](docs/development/home-littoral-20261113.md)。

本轮新增母港「竞技」入口：10000分人机排位、最多四支自有编队，以及双方各三席的3v3团战（玩家3400分、两名AI队友各3300分）。所有对手和队友均为本地人机，真实对战、积分、七档段位与一次性奖励会保存。新搜打撤默认全自动接任务、搜索装货、评估风险并撤离，可随时接管；全屏动漫云浪转场每次随机三名放大小人，标题与母港跟随现实时间显示晨昼昏夜。海伦娜改用本人原创SD，六个进阶战术AI各有独立新立绘。详细入口与实际证据见 [本轮整合回执](docs/development/arena-autonomy-story-integration.md)。

三章剧情已长篇重写为101节点、1877页、18场真实实战，保留关键CG并补自然日常、分歧、调查和人工表情转折。最短路线按400汉字/分钟加实际战斗的内容预算约64/62/65分钟，允许快进和跳过；旧进度兼容、回访不重领奖。[剧情专项](docs/development/story-longform-receipt.md)记录GitHub写作技能、计时口径和完整实际验证。

本轮进一步重做灯塔晨光标题、接回迁移前六名AI角色立绘，货舱支持直接拖放、R旋转与完整落位预览。新的剧情/搜打撤采用独立冒险规则：10倍航行、更丰富程序海域、可见怪物血量与攻击预警；历史战役和旧航次保留原规则。入口、实际试玩与兼容证据见 [本轮交付](docs/development/adventure-polish-receipt.md)。

追加的新搜打撤行动系统：五场景、三项可选任务、预告后出现的Boss、按编队分数预算的遥控敌舰、七种俯视六姿态海怪、16种可售/可拆包物资，以及三类炮弹/三类鱼雷/有限备雷。航前“弹种与备雷”配置，战场“行动”“自动打捞”进入任务与谨慎/均衡/大胆自动指挥。设计依据和取舍见 [行动系统设计](docs/design/extraction-operations-v2.md)。

现行视觉为动漫云海：角色主导的明亮母港、图像编队、全屏战斗与剧情、独立征募演出。后续设计遵循 [统一设计原则](docs/design/anime-ui-reconstruction.md)，本轮运行证据见 [UI 重构验收](docs/development/ui-redesign-receipt.md)。

最新功能：全程序水云地形与天气、自由多编队、舰娘详情/舰装/四组水手、元词/银币/体力、礼包直购、资源海域与每周天梯。入口及本机实际验证见 [自由舰队与成长交付](docs/development/fleets-growth-pve-receipt.md)。历史借用与自有舰演练分开；新增竞技为本地人机，线上PvP和实际支付服务尚未开放。

CAS 是独立的二次元海战游戏项目。本机试玩复用铁底湾手游母港和序章，战斗改用 CAS 实时内核。可玩内容包括白昼、夜航、1943 年雷达演习、昼间及夜战教学和 3 对 5 挑战。历史战役档案可查；其出击条件与其他尚缺规则见 [开发路线](plan.md)。

## 迁移前客户端试玩资料

- Windows：完整解压发行 ZIP，在包内运行 `CAS.exe`。先登录；首次使用可离线建立本机指挥官账号。进入母港后选「序章」或「教学复习」，主菜单可继续演习。
- Android：安装 CAS 单机 APK，横屏运行，使用独立本机账号和存档。当前是模拟器验证的调试版，实体机验收尚未完成。见 [验收记录](havedone.md)。
- 选编队和机动方式，点海图添加途经点，预览后确认。舰上「炮」「雷」是可操作标记。按住拖向接触；雷击锁定后可以保持按住并微调射向，拖向取消区松开则不会下令。
- 「战术 AI」设置协同、炮战或雷击，选择建议或分别托管机动、炮击、鱼雷。想观看自动对战，打开己方三项托管，开始演习。接受命令后，实际开火按战术窗口记录在战报。
- 规则计时使用模拟时间；加速不会改变命中结果。暂停可规划或检查战局。保存后可继续或进入只读重演。

## 开发与核验

在 Windows 安装 Rust（含 `wasm32-unknown-unknown`）、Node、.NET 和 Python 3.11 或更新版本后：

```powershell
cargo test --release --locked
python data/check_stage0.py
.\scripts\build.ps1
```

桌面打包见 [Windows](desktop/README.md)，手机打包见 [Android](android/README.md)。[规则台账](docs/rules/stage0-sources.md) 记录舰卡、表格与改编的出处；[未覆盖项](docs/rules/open_questions.md) 记录暂未实现或尚不能裁决的机制。原始规则书和用户的旧项目不随代码或试玩包分发。

游戏只显示当前一方的观察与战报。开发测试可从命令行复跑完整对局：`cargo run --release --locked --bin cas-sim -- demo 6106 allies`；将最后一个参数换成 `axis` 可以查看同一对局的另一方战报。
