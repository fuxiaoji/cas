# 启动、加载与存档错误恢复验收 · 2026-11-14

本次独立验收使用真实 `godot/scenes/boot.tscn`，通过 `profile_override` 写入隔离 QA 存档；正常用户主存档与备份均只读。没有以替身菜单、计时器结束或固定进度条代替实际启动成功。

## 结果

- 无显示窗口检查：59 / 59 通过。收据：`artifacts/boot-loading-20261114/headless-48216/receipt.json`。
- NVIDIA OpenGL 实际窗口检查：67 / 67 通过。收据：`artifacts/boot-loading-20261114/gpu-60552/receipt.json`。
- 两次检查均确认正常用户主存档与备份的 SHA-256 在测试前后完全一致。
- 未出现脚本错误。退出时均有 16 个 ObjectDB 实例泄漏警告；它不影响本轮启动和导航结果，尚未归因，本说明不将其记为已修复。

测试脚本：`godot/tests/boot_loading_review.gd`。启动 UI 组件另有 `godot/tests/loading_screen_review.gd` 的 21 项状态/响应式检查。

## 实际覆盖

1. 首次创建的隔离账号：轻量加载控件先出现，此时 Main 尚未实例化。收到 `boot_completed` 成功后，确认 `startup_ready`、真实标题页、Fleet/Progression/Arena/Home 服务与输入释放。
2. 启用真实分段导航，依次经过标题、母港、舰库、设置、返回舰库、直接返回母港。跨页请求不会同步替换尚未覆盖的旧页面，每次均经过全屏覆盖状态，直到 `page_ready` 与转场完成才判定可用。
3. 有效原账号副本：来自 `artifacts/mobile-home-20261113/navigation/isolated-navigation-68676.json`。已拥有舰只身份、已保存编队及进行中航次快照在启动后保留；标题页不会自动开始航次。
4. 主档与备份均为 137498 字节全 NUL 的隔离副本：明确启动失败，保留可读说明、重试与退出按钮；不构造 Fleet/Progression/Arena/Home 服务；空账号不能绕过保护进入母港；主备文件字节不变。
5. 将损坏的 QA 主档替换成有效原账号副本后，通过真实 `retry_requested` 信号重试：创建新的 Main，清除旧错误，成功进入标题，原拥有身份、编队与航次仍保留。

## 画面目检

实际窗口截图目录：`artifacts/boot-loading-20261114/gpu-60552/`。

- `fresh-first-frame.png`：浅青海面、淡云、罗盘、当前阶段和细进度条，未见黑底或文字裁切。
- `fresh-title.png`：加载揭幕后标题背景、操作按钮完整。
- `fresh-harbor-loading.png`：动漫全屏海浪覆盖，三个不同舰娘小人在加载状态下继续运动，阶段文字可见。
- `fresh-harbor.png`、`fresh-roster.png`、`fresh-settings.png`：目标页面已绘制且转场消失。
- `damaged-readable-failure.png`：损坏档案错误可读，重试/退出清晰，未进入无资源的母港。
- `recovered-title.png`：替换 QA 文件后重试成功，旧错误未遮挡标题。

本脚本不声明海陆战斗、真实比例尺或游戏内容验收；这些由对应专项测试覆盖。

## 分段导航依赖的只读审计

以下风险已反馈主代理；本代理未修改 Main、Boot 或剧情/抽卡产品文件。

- `main.gd` 的搜打撤结算“整理带回物资”跨路由到 warehouse 后立即打开 Cargo 弹窗：异步渲染目标页时会关闭旧页弹窗，需在 warehouse 就绪后打开。
- `home_story.gd` 的家园教学结尾未等待 `resume_run()` / `launch_littoral()`：异步入战期间会提前解除 `committing`，需等待启动再决定是否释放剧情输入。
- `main.gd` 的保存返航提示在 `return_to()` 后立即发送：异步路由时提示仍属于离开的战斗页，应在目标页就绪后提示。
- 当前招募按钮在 recruit 页面调用 `RecruitPresentation.draw()`，其相同路由刷新仍同步，因此 `show_page("recruit")` 后 `reveal()` 当前实际使用无新增回归。若以后从其他页面直接调用此方法，应先等待 recruit 就绪再通知/演出，避免演出被目标页刷新关闭。
- 已检查 Boot 与 PageTransition 的 `_input` 屏障：正常加载/等待期间消耗输入，失败视图允许按钮交互。未发现额外键盘导航绕过点；本轮只读审计不是对所有操作的自动化证明。

## 修复后的异步动作专项回归

主代理已加入 `Main.wait_for_page(route)` 并修复上述三个实际问题；家园剧情教学同时改用当前版本登记的多部队贷款。独立脚本 `godot/tests/staged_action_loading_review.gd` 在真实 Boot 与 staged 导航下 **38 / 38** 通过，无脚本错误。收据：`artifacts/boot-loading-20261114/actions/headless-61368/receipt.json`。

- 新档进入真实家园剧情，将 QA 阅读位置设为最后一句后触发实际 `_advance()`：加载期间 `committing` 保持为真，再次推进不会创建第二次航次；实际进入 `cas-littoral-v4`，借用 `MCP-034` 与 `MCP-001`，仿真时间保持 0，运行保持暂停。
- 同一真实教学航次通过 `save_leave()` 返回 home：目标页准备完成后，提示“已保存同一行动，返港期间暂停交易。”出现在新页面，保留相同航次 ID，钱包无额外扣费。
- 另一个隔离新档使用已结算结果的 UI fixture，经真实“整理带回物资”按钮分别测试编队货舱与基地仓库：异步切换结果页时不会抢先打开弹窗，warehouse 就绪后 `CargoHold` 的 scope 正确，后续渲染与转场清理没有关闭弹窗。这部分验证路由与弹窗生命周期，不声明经济结算验证。
- 该专项仅无窗口运行；未启动 GPU、未接管正在使用的游戏窗口。测试期间当前满级正常主备 SHA-256 都为 `a3b0a719421652bd2d3c7e1255417e0cd963b7e9b4511c5448d77a31d8714f46`，前后完全相同。
- 退出仍有相同的 16 个 ObjectDB 实例泄漏警告，未掩盖或视为已解决。
