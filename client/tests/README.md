# CAS 浏览器验收

1. 用项目根目录的 Windows 构建脚本生成客户端的 WebAssembly 内核。
2. 在客户端目录安装 Playwright（`npm install --no-save playwright`）并执行 `npx playwright install chromium ffmpeg`。已有的 Playwright 也可通过环境变量 `CAS_PLAYWRIGHT_MODULE` 指向。要使用系统浏览器，可设置 `CAS_BROWSER_PATH`。
3. 在客户端目录运行 `npm run dev -- --port 5175`，再从另一终端运行 `node tests/browser-offline.mjs`。用 `CAS_TEST_URL` 可以覆盖默认地址。
4. 运行 `node tests/browser-visuals.mjs` 验收炮弹飞行与鱼雷航迹、命中提醒的手势遮让、己方炮座转向、射程显示、舰艇状态和四种舰娘立绘、只读历史档案和虚构夜航演习。脚本以真实内核状态检查命中时点、投射坐标、未发现目标和关卡可玩状态，截图与凭证默认保存在 `artifacts/client/visuals/`。

验收走真实海图、舰船标记、触屏和母港控件。为缩短等待时间，脚本通过页面正在使用的 Worker 推进模拟秒并读回权威观察，不注入战果或资产。默认在 `artifacts/client/port/` 写入截图、录屏和 JSON 凭证；可用 `CAS_ARTIFACTS` 更换位置。740×360 项是浏览器触屏模拟，实体安卓需另测。
