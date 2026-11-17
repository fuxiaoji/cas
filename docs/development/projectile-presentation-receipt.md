# 2026-11-12｜主副炮可选表现数据与兼容验收

用户要求三联装按实际三根炮管显示炮弹，并显示有区别的副炮弹体。Godot 渲染由 Root 和独立窗口验收代理负责；本回执只登记 Rust 数据及新旧内核兼容，不把协议测试称为美术验收。

## 实际实现

新增显式只读请求 `{"op":"presentation"}`，返回 `projectile-fx-v1`：

```json
{
  "version": "projectile-fx-v1",
  "tick": 344,
  "shots": [{
    "id": "secondary:18",
    "tick": 344,
    "own_ship": 1,
    "battery": "secondary",
    "caliber_mm": 127.0,
    "barrels": 2,
    "from": {"x": 4992.438599, "y": 6829.211788},
    "to": {"x": 17862.961718, "y": 7336.453695}
  }]
}
```

以上坐标为协议示意；实际每轮坐标以该轮公开观察为准。

- 主炮记录以 `main:<shell_id>` 唯一标识，另给 `shell_id` 严格关联已有本席 `shells[].id`。口径来自发射舰实际 `gun.caliber_mm`；管数就是原有 Shell 的真实聚合发射管数。单座三联为 3，同秒两座三联为 6，不伪造炮座归属。
- 仍在飞行的全部本方主炮提供元数据；`from/to/tick` 与已经公开的原 Shell 完全相同。敌方已有可见弹道仍走旧接口，不额外提供敌舰身份或口径。v10 弹道原本已使用本席 Contact 解算；旧版本保留原本已公开的旧弹道，不重算、不替换。
- 副炮原本在发射秒立即结算，没有 Shell，而且旧 `secondary` 事件只在命中时产生。本轮仅在真实发射处记录表现数据，包含未命中；不另掷骰、不新发命令、不改事件、重装、命中、伤害或结算顺序。`to` 只取该席现有对应 `Contact.p()`，不输出真实敌舰位置、编号、名字或命中结果。前端短暂飞行动画是视觉表现，不能推迟真实伤害。
- 副炮 ID 按本席独立递增，另一席发射不会影响本席编号；只返回最近 4 模拟秒。该缓存、主炮元数据均不进入 `Saved`，旧 `observe/step/save/load/replay` 默认字段不增加。反复查询保持纯读；首次观察、恢复或跳时由客户端重置消费基线，避免重播旧表现。
- 独立 Tide 模式已有自己的活动弹体，统一返回同版本空 `shots`，不向该模式强行接入历史舰炮。

实现：`src/projectile_presentation.rs`、`src/projectile.rs`、`src/combat.rs`、`src/world.rs`、`src/lib.rs`。没有修改原始 PDF、参考项目、历史舰表、舰队或阵位。

## 已完成核验

1. Rust 全库 **224/224**（既有 219 加本轮 5）。新测试包含真实未命中副炮仍有记录、刻意偏离真位置的 Contact 只输出公开 plot、真实单三联装 3 发、主炮旧 Shell 精确关联、两席隔离、4 秒保留、稳定 ID、重复查询不改变时钟/三组 RNG/观察/存档/命令记录，以及活动空接口。
2. 新协议 **4 组、2077 请求** native/WASM 一致，同时剔除可选请求后，每一条旧请求输出仍与之前实际部署核逐字节相同。真实自动华盛顿样本 620 秒，406mm 每轮 6 发，455 次仍飞行弹道字段逐项对应；真实副炮样本 346 请求至 344 秒，**18 轮 127mm/每轮2管发射，旧命中事件只有1轮**，17轮未命中现在也具备表现记录。保存/恢复和纯查询边界通过。
3. 旧实战记录与历史/旧版本保存判例没有被新 fixture 替换。前一轮完整 **59 组、3828 请求、85,224,076 原始输出字节**，实际旧部署 `0821f592…` 与新审计核 `d019fa1f…` 全部逐字节一致；同组新 native/WASM 也一致。包含原 expedition frozen 判例、两三章实际终局、燃油/物资/活动、自动撤离等旧记录。
4. 按默认启动器使用的 `target/godot-core-build` 再构建，标准核 `1d9ab5e1…` 与审计核 `d019fa1f…` 在全部新 2077 请求的 **17,514,910 原始字节**完全相同。没有覆盖用户正运行的旧哈希 exe。本代理未修改 `core-current.json`；由 Root 在整合后发布。
5. 真 headed Edge **13/13**，零页面错误：通过可见控件进入埃斯佩兰斯标准战役，原9舰、历史夜间与非冒险规则保持；点击推进一秒、保存、刷新后继续，精确存档 SHA 保持且仍暂停；1360×768海图/顶部/侧栏在窗口内；新 API 纯读及 replay 不替换当前状态通过。临时浏览器请求精确拦截注入新 release WASM，两个实际 worker 均记录同一 SHA；原 `client/public/cas_core.wasm` 未改。临时 Edge、非持久上下文与 Vite 5192 已关闭。

证据：

- [协议与全部冻结对拍](../../artifacts/projectile-presentation/receipt.json)，复现脚本 [verify-projectile-presentation.mjs](../../scripts/verify-projectile-presentation.mjs)
- [标准构建一致性](../../artifacts/projectile-presentation/standard-build.json)、[Rust全库日志](../../artifacts/projectile-fx-tests.log)
- [真实浏览器回执](../../artifacts/projectile-presentation/browser-receipt.json)、[保存截图](../../artifacts/projectile-presentation/browser-historical-saved.png)、[恢复截图](../../artifacts/projectile-presentation/browser-historical-restored.png)

构建 SHA：审计 native `d019fa1f5ff29bc3c9b98d81f95e2bd3120978e5c0dbd2b16a3db46b188f6466`；标准 native `1d9ab5e1bf99aab1167a80f3ec38c3b3a54cf02f814a58f0cb0b458be27f2cbc`；新 WASM `3edd5f7157f0069191b944f1e118a80fcc0fc4f25772c4393a155c640815d80b`。

## 明确保留边界

副炮是短期视觉记录；推进跨度超过4秒时，不补播早已过去的全部副炮，不把表现缓存当战报或存档。主炮真实数值按一轮聚合发射保留，视觉拆为每管一发不会增加伤害判定。旧 Web 海图标题仍固定显示白昼演习，截图中可见；实际历史环境是夜间，此为既有表现 blocker，本轮没有改变旧前端。完整 Godot 弹体美术和最新默认启动核窗口验收另由 Root 汇总。
