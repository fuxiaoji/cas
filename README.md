# CAS 海图指挥台

CAS 是独立的二次元海战游戏项目。现有版本是本地试玩：白昼 5 对 5 水面战斗、两种编队机动、舰炮和鱼雷拖拽，以及三种可配置的状态机。首批只使用已经核验的 CAS 舰型和规则；完整战役、夜战、排位及支付另按 [开发路线](plan.md) 推进。

## 试玩

- Windows：完整解压发行 ZIP，在包内运行 `CAS.exe`。首次打开暂停在海图；从「演习设置」可换边、换 AI 或重开。「母港」进入单机成长预览。
- Android：安装 CAS 单机 APK，横屏运行。应用有自己的存档空间，与铁底湾互不覆盖。首个 Android 包为模拟器验证预览，实体机验证见 [验收记录](havedone.md)。
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
