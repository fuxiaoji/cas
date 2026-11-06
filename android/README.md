# Android 离线预览

独立包名 `org.casnaval.exercise`，不读写铁底湾的应用数据。固定横屏。APK 内含与 Windows 相同的界面、Worker 和 WebAssembly 内核，无网络权限。

开发预览需要 Android 8 或以上和可用的 Android System WebView。当前脚本生成调试签名 APK，供本机和内测验证。

## 构建

需要 JDK 17、Gradle 8.11.1、Android SDK 35，以及 Windows 构建的 Rust／Node.js 依赖。将 `JAVA_HOME`、`ANDROID_HOME` 和 Gradle 设置到可用位置后运行：

```powershell
.\scripts\build-android.ps1
```

如果使用已有本机工具目录，可加 `-Toolchain`（目录下含 `jdk-zulu`、`gradle`、`sdk`）。已有 Gradle 缓存时可指定 `-GradleCache`；依赖齐全可加 `-Offline`。输出 APK 与 SHA-256 文件位于 `release/`。

## 预览包验证

安装到专用 Android 测试机，开启飞行模式并关 Wi-Fi。调试 APK 允许测试连接到 WebView，检查实际渲染、离线启动、读档重演和后台重启后的持久化：

```powershell
node .\scripts\build-android-smoke.mjs '<adb.exe>' '<设备序号>' '.\artifacts\android-smoke.json'
```

此检查会启动、退出再重新打开 CAS；请在专用测试机运行。模拟器通过不能代替实体机验证。
