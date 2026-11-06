# Windows 离线试玩

解压整个 Windows ZIP，再双击 `CAS.exe`。不要只移出 EXE。包内含 Windows x64 .NET 运行时，系统需要有 Microsoft Edge WebView2 Runtime。

桌面窗口将包内的 `web` 文件夹映射到专用的本地来源；不运行网络服务，不从网上下载游戏内容。战斗内核由页面的独立 Worker 加载。存档数据位于 `%LOCALAPPDATA%\CASNaval\Stage0\WebView2`，与铁底湾分开。

## 从源码构建

需要 Rust/Cargo、`wasm32-unknown-unknown` 目标、Node.js 22.12 以上、.NET 10 SDK。初次构建会下载构建依赖。

```powershell
rustup target add wasm32-unknown-unknown
.\scripts\build.ps1
```

每次构建写入 `release/` 下独立的目录、ZIP 与 SHA-256 文件。调试 Web 时可用 `-WebOnly`；已有 Node 依赖时可加 `-ReuseNodeModules`。

从发行目录验证真实桌面窗口（验证存档保存在临时测试配置，不会改变日常试玩档）：

```powershell
.\scripts\build-smoke.ps1 -Executable '<试玩目录>\CAS.exe'
```

同一引擎的原生与 WebAssembly 全局结果核对：

```powershell
cargo build --locked --release --bin cas-sim
cargo build --locked --release --lib --target wasm32-unknown-unknown
node .\scripts\build-parity.mjs
```
