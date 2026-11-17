# 新 WASM 真实浏览器冒烟

2026-11-12。仅补充原核迁移验收门，主交付仍为 Godot。没有修改网页产品、原始参考或历史数据。

使用 Playwright 持久交互会话，启动 Microsoft Edge 157.0.4341.46 有头窗口和独立临时浏览器上下文，在本任务自建的 127.0.0.1:5179 Vite 服务访问当前 client/public。复用了既有 `client/tests/browser-esperance.mjs` 的真实历史目录、编成与 worker 观察路径，按当前可见控件完成操作。未使用原玩家浏览器资料或存档。

**9/9 通过：**从历史目录进入埃斯佩兰斯角 `CAMP-ALLIES-02`，默认同盟历史借舰为 9 舰、1 编队；夜间、能见度 10、海况 3。点击“推进一秒”使 0→1，点击“保存进度”并重复保存，完整核心状态摘要保持不变。整页重载后经主菜单“继续演习”恢复到同战役第 1 秒，保持暂停，完整核心保存摘要前后一致。

- 完整核心保存 SHA256：`c361acebe9b43ab7e748f96d1e75356e9987aff8b518a666d0fa47d65d995322`。
- 当前 WASM 为 3,979,917 bytes，浏览器 HTTP 200 响应的 SHA256 与 `client/public/cas_core.wasm` 一致：`8a4eca1ec1e1edc259c4d920c8afaff7e3b7a707079e28e54dca441a7a1efc1f`。
- 页面运行错误为零。重复保存、暂停后重载两条额外路径均验证。旧验收文本的两处定位超时已按实际控件更新，不是产品运行错误。
- 截图为真实浏览器玩家视角，**不是 Godot 截图**：`artifacts/browser-new-wasm-smoke/01-browser-historical-saved.png`、`02-browser-historical-restored.png`。已检查可见战役侧栏、00:01 时钟、暂停、范围圈和保存入口。
- 详细回执和覆盖清单：`artifacts/browser-new-wasm-smoke/receipt.json`、`qa-inventory.json`。

原网页地图仍有固定“白昼接敌”标题，侧栏和权威环境为埃斯佩兰斯夜战；这是旧网页展示差异，本次未以浏览器冒烟为由变更产品，也未把浏览器美术当作 Godot 美术验收。

结束后已关闭本任务的隔离 Edge 会话和 5179 服务。
