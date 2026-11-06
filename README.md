# CAS 海图指挥台

CAS 是独立的二次元海战游戏项目。本机试玩复用铁底湾手游母港和序章，战斗改用 CAS 实时内核。可玩内容包括白昼、夜航、1943 年雷达演习、昼间及夜战教学和 3 对 5 挑战。历史战役档案可查；其出击条件与其他尚缺规则见 [开发路线](plan.md)。

## 试玩

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
