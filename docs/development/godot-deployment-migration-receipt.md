# Godot 历史换舰、特混与预设迁移

2026-11-11。将旧 `DeploymentScreen.tsx`、`TaskForceBuilder.tsx`、`draft.ts` 的本地关卡前编成移至 `godot/scripts/campaign_deployment.gd`。入口仍在战役航图按当前席位出航；故事难度先打开编成，标准/挑战直接使用原史实编成。`port_presentation.gd` 仅增加故事分支，主客户端无额外修改。

## 已接范围

- 调用 `campaign_fleet{id,difficulty}` 读取真实预算、逐行历史舰位、107/95个本席单舰候选、原初设位置及特混支持标记。每个历史舰/identity独立保留，不按舰级去重。同一身份的时期历史点价优先，旧class pick仍可读取。
- 历史舰位不可增减；可按舰种/舰名/舰级/identity搜索，按点价/舰名/舰种排序。超过预算的候选禁用，原核在 `new_campaign` 再次核验。换舰只传identity/class数组，UI不计算或改变原阵位、航向、航速、领舰。
- 特混仅原核已支持的02/11双方想定及故事难度开放。每个编队选原页初设位置，可单舰、空置位置、继续编入、移除或清空；位置/列内间距全部由原核生成。`groups:[{position,ships}]` 真实出航，敌方编制不变。冻结context明确 `deployment:taskforce`，模式服务不登记历史星数/首通或经济奖励。
- 草稿按关卡及难度持久化，预设沿旧版24条上限，保留名称/ID/stageId/difficulty/picks/profile/updatedAt，增加特混groups。支持保存、载入、重命名、删除与导出。
- 导入弹窗接收旧浏览器原 `FleetPreset[]` JSON或当前导出记录，不改写旧class/identity。载入时验证舰位与候选，出航仍走原核。不会自动读取浏览器的其他存储；旧localStorage现存记录需导出其JSON后导入，未冒称已经自动迁移。
- 独立记录在当前经济档案路径旁 `.deployment.json`，原子临时写入及备份恢复；损坏且无可用备份的旧文件保留，不自动覆盖。不改变经济钱包、私人舰况或历史原始文件。source_only及未接入本席始终阻断，并显示原核原因。

## 可见窗口实测

运行 `Godot_v4.7.2-stable_win64_console.exe --path godot --script tests/deployment_integration_test.gd`：**68/68**检查、68个应用内部 `Input.parse_input_event` 事件、4张真实截图，无脚本/运行时错误。不是OS鼠标自动化。独立测试档案结束后仅清理自己的记录。

验证了9个原舰位、116候选（9历史+107注册）及至少5个独立Fletcher身份；历史预算6850及时期价格一致。实际点选第9舰位更换Fletcher后，真实出航每舰x/y/heading/speed/fleet与原开局逐项完全相同，characterId仍是所选身份。超预算选项禁用，同时原核直接请求也拒绝。

命名保存/载入/恢复史实/重命名、旧JSON导入、导出、删除均经按钮；重新创建控制器从磁盘还原草稿与原格式预设，经济状态不变。真实单Fletcher特混从原坐标/航向/航速出航并推进到原核终局；回执fictional_taskforce=true、stars=0、所有币种与历史进度不变。标准难度舰位/特混禁用；轴心95个身份保留。

凭证 `artifacts/godot/deployment/receipt.json` 与 `01-historical-slots.png`、`02-identity-picker.png`、`03-taskforce-anchors.png`、`04-taskforce-result.png`。本次无Rust、舰卡、历史想定或资料更改，沿用已有原生/WASM与原页验收范围，不将客户端换舰功能当作新想定核验。
