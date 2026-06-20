# 最新构建结果

更新时间：2026-06-20

## 已完成

- iOS 新增“播放历史”详情页，复用双列视频卡片逻辑
- iOS 与 Android 均替换为新的应用图标资源
- README 已同步到当前双端仓库状态与最新产物路径

## 产物

### iOS

- 已成功生成 unsigned IPA
- 路径：`Build/BilibiliFocus-unsigned.ipa`

### Android

- 本次会话内未能生成新的 APK
- 原因：当前沙箱禁止 Gradle 在本地绑定端口，并且无法直接复用 `~/.gradle` 的守护进程/锁竞争机制
- 你的本机终端可直接执行：

```bash
./gradlew :focus-android:assembleDebug
```

- 预期输出：

```text
focus-android/build/outputs/apk/debug/focus-android-debug.apk
```

## 备注

- iOS 工程已通过命令行构建验证
- Android 代码与资源改动已落盘，但 APK 需要在非沙箱环境下完成最终打包
