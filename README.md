# Bilibili Focus iOS

自用的 iOS 版 Bilibili 容器，核心思路是：

- `动态` 使用原生 SwiftUI 关注流
- `搜索` 使用原生关键词入口
- `播放 / 详情 / 结果页` 继续由 `WKWebView` 承接
- JS 注入只做去干扰、导流拦截和小范围布局修复

这个公开仓库只保留 iOS 主线，不包含 Safari userscript 版。

## 当前范围

- 原生动态流，数据源为已登录用户的关注动态
- 原生搜索入口，提交后进入官方结果页
- 视频页、动态详情页、搜索结果页的页面裁剪与重排
- Cookie 桥接，保证 `WKWebView` 登录态与原生请求共用
- 原生底栏、顶栏和基础导航路由

当前不包含：

- Safari / Userscripts 分发版本
- 评论区恢复
- `space.bilibili.com` 个人主页移动化

## 目录结构

- `App/BilibiliFocus`
  - SwiftUI 应用入口
  - 浏览容器、原生动态页、原生搜索入口
  - Cookie 持久化与 WebView 宿主逻辑
- `Sources/FocusCore`
  - 路由、设置、导航策略
  - 动态数据模型与服务
  - 页面规则、注入脚本和运行时
- `Scripts`
  - 本地构建和 unsigned IPA 打包脚本
- `Tests/FocusCoreTests`
  - 规则、路由、配置和 fixture 测试

## 本地运行

1. 打开 `BilibiliFocus.xcodeproj`
2. 选择 `BilibiliFocus` scheme
3. 在 `Signing & Capabilities` 中设置个人开发 Team
4. 选择真机或模拟器运行

命令行构建：

```bash
xcodebuild -project BilibiliFocus.xcodeproj \
  -scheme BilibiliFocus \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

## 打包 unsigned IPA

仓库内置脚本会先构建 `iphoneos` 产物，再导出未签名 IPA：

```bash
./Scripts/build_unsigned_ipa.sh
```

默认输出在：

```text
build/BilibiliFocus-unsigned.ipa
```

后续可自行配合 AltStore、SideStore 或重签名工具安装。

## 测试

规则与核心逻辑测试：

```bash
FOCUS_INCLUDE_TESTS=1 swift test
```

Web 注入验证：

```bash
swift run FocusVerifier
```

## 已知取舍

- 动态流只服务关注动态，不做热门流兜底
- 搜索目前仍落到官方结果页，首版不做完整原生结果列表
- 播放页和详情页仍依赖 Bilibili 当前网页结构，规则需要随网页变动维护
- 默认按自用侧载方案设计，不以 App Store 审核兼容为目标
