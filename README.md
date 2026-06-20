# Bilibili Focus

自用的 Bilibili 手机端容器，当前仓库同时包含 iOS 和 Android 两条主线。

核心方向：

- `动态`、`搜索`、`我的/历史` 优先走原生页与 API
- `播放页`、`部分详情页` 继续复用官方网页播放器与详情 DOM
- 页面注入只做去干扰、导流拦截和小范围布局修复
- `WKWebView / Android WebView` 与原生请求共用登录 Cookie

## 当前能力

- 原生关注动态流
- 原生搜索入口与结果页卡片流
- 原生我的页、播放历史预览与历史详情页
- 原生 UP 主空间、合集页、专栏页、图文动态详情
- 视频播放页的移动化裁剪与原生底部控制栏
- iOS unsigned IPA 与 Android APK 本地打包

## 仓库结构

- `App/BilibiliFocus`
  - iOS SwiftUI 应用入口、原生页面、WebView 容器
- `Sources/FocusCore`
  - iOS 侧共享核心：导航策略、页面规则、注入运行时
- `focus-core`
  - Android / Kotlin Multiplatform 共享模型与 API service
- `focus-android`
  - Android 应用、Compose UI、ExoPlayer 播放与原生页面
- `Scripts`
  - iOS unsigned IPA 打包脚本
- `Tests/FocusCoreTests`
  - iOS 规则、路由、配置与 fixture 测试

## 本地运行

### iOS

1. 打开 `BilibiliFocus.xcodeproj`
2. 选择 `BilibiliFocus` scheme
3. 在 `Signing & Capabilities` 中设置个人开发 Team
4. 选择真机或模拟器运行

命令行构建：

```bash
xcodebuild -project BilibiliFocus.xcodeproj \
  -scheme BilibiliFocus \
  -destination 'generic/platform=iOS' \
  -derivedDataPath .tmp-derived \
  CODE_SIGNING_ALLOWED=NO build
```

### Android

```bash
./gradlew :focus-android:assembleDebug
```

## 打包产物

### iOS unsigned IPA

```bash
./Scripts/build_unsigned_ipa.sh
```

默认输出：

```text
Build/BilibiliFocus-unsigned.ipa
```

### Android APK

```bash
./gradlew :focus-android:assembleDebug
```

默认输出：

```text
focus-android/build/outputs/apk/debug/focus-android-debug.apk
```

## 测试

### iOS 核心测试

```bash
FOCUS_INCLUDE_TESTS=1 swift test
```

### Web 注入验证

```bash
swift run FocusVerifier
```

## 当前取舍

- 默认按自用侧载方案设计，不以 App Store / 应用商店审核兼容为目标
- 播放页与部分详情页仍然依赖 Bilibili 当前网页结构，网页改动后需要继续维护规则
- `localonly/userscript-archive` 只作为本地归档，不是当前主线分发方案
