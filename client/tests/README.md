# CAS 浏览器验收

1. 用项目根目录的 Windows 构建脚本生成客户端的 WebAssembly 内核。
2. 在客户端目录安装 Playwright（`npm install --no-save playwright`）并执行 `npx playwright install chromium ffmpeg`。已有的 Playwright 也可通过环境变量 `CAS_PLAYWRIGHT_MODULE` 指向。要使用系统浏览器，可设置 `CAS_BROWSER_PATH`。
3. 在客户端目录运行 `npm run dev -- --port 5175`，再从另一终端运行 `node tests/browser-offline.mjs`。用 `CAS_TEST_URL` 可以覆盖默认地址。
4. 运行 `node tests/browser-visuals.mjs` 验收炮弹飞行与鱼雷航迹、命中提醒的手势遮让、己方炮座转向、射程显示、舰艇状态和四种舰娘立绘、只读历史档案和虚构夜航演习。脚本以真实内核状态检查命中时点、投射坐标、未发现目标和关卡可玩状态，截图与凭证默认保存在 `artifacts/client/visuals/`。
5. 运行 `node tests/browser-story.mjs` 验收本机注册、序章开场的真实战斗、失忆分支与恢复、选领舰、三段海图实操、一次性见面礼，以及夜战教学的照明、炮击、雷击和全部十项检查。截图与凭证默认保存在 `artifacts/client/story/`。只查序章时可设 `CAS_STORY_ONLY=1`。
6. 运行 `node tests/browser-realtime.mjs` 验收实时主炮的预计首炮、拖动瞄准不提前转炮、取消待发、真实转向和装填、弹道飞行和可见的鱼雷长尾迹。截图与凭证默认保存在 `artifacts/client/realtime/`。
7. 在开发服务器运行 `node tests/browser-radio.mjs` 验收本席战情触发、跨暂停续播、重演不重播及双方原版舰队电台。标准构建不包含旧音频；仅内部试玩构建可显式设置 `VITE_CAS_LOCAL_VOICE=1`。音频路径、原始 SHA-256 和试用范围见 `client/src/audio/assets/ledger.json`。
8. 运行 `node tests/browser-campaign.mjs` 验收圣乔治角和通道行动双线出航、三档难度、锁定其他关卡、具名借舰、任务栏、同席重演和重启存档。逐舰打开舰况，核对十八个角色 ID、原图解码和登记的 SHA-256。使用 `CAS_CAMPAIGN_REWARD=1` 附加运行圣乔治角真实胜利、评级、领奖防重和本机账号隔离。凭证默认写入 `artifacts/client/campaign/`。
9. 按 [服务运行说明](../../server/README.md) 在回环地址启动账号服务，设置 `CAS_SIM_PATH` 启用权威战役，并将 `CAS_ACCOUNT_DB` 指向 `artifacts/` 下独立的 `*qa*.sqlite3` 测试库。给脚本的 `CAS_ONLINE_TEST_DB` 设置同一测试库；如服务依赖不在默认 Python，可设 `CAS_ONLINE_TEST_PYTHON`。运行 `node tests/browser-online.mjs` 验收联机注册、云签到和重登防重、邮件领取、常驻征募、商店兑换、真实权威战役和重登续战。夹具只向当次新建账号投递邮件；商店使用活动中心实际发放的签到补给币。默认使用 `http://127.0.0.1:8021`；如改服务地址，同时配置客户端的 `VITE_CAS_ACCOUNT_URL` 和脚本的 `CAS_ONLINE_TEST_API`。脚本限制在本机回环，截图和凭证默认写入 `artifacts/client/online/`。

验收走真实海图、舰船标记、触屏和母港控件。为缩短等待时间，脚本通过页面正在使用的 Worker 推进模拟秒并读回权威观察，不注入战果或资产。默认在 `artifacts/client/port/` 写入截图、录屏和 JSON 凭证；可用 `CAS_ARTIFACTS` 更换位置。740×360 项是浏览器触屏模拟，实体安卓需另测。
