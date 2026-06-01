# Bilibili Focus iOS v3

这一版不再把 `t.bilibili.com` 和空白搜索首页硬修成主界面，而是改成：

- `动态`：原生 SwiftUI 卡片流，数据源是登录用户的关注动态
- `搜索`：原生关键词输入，提交后直接打开官方移动端结果页
- `浏览`：继续复用 `WKWebView`，承接搜索结果、动态详情和视频播放

## 结构

- `Sources/FocusCore`
  - 设置、入口路由、搜索 URL 生成
  - Bilibili 页面拦截与去干扰规则
  - 动态卡片模型、Cookie 协议、动态拉取服务
- `App/BilibiliFocus`
  - 原生动态页、原生搜索入口、浏览容器
  - `WKWebsiteDataStore.default().httpCookieStore` 到原生请求的 Cookie 桥接

## 当前行为

- 默认入口仍然支持 `动态` / `搜索`
  - `动态`：进入原生动态流
  - `搜索`：启动后直接弹原生搜索输入
- 首页重定向不再跳网页 URL，而是回到原生入口语义
- JS 注入层只保留搜索结果页、动态详情页、播放页的去干扰
- 动态卡片第一版只保：
  - 正文
  - 封面
  - 点击跳详情 / 播放

## 在 Xcode 里运行

1. 打开 `BilibiliFocus.xcodeproj`
2. 选择 `BilibiliFocus` scheme
3. 在 `Signing & Capabilities` 里填你的个人开发 Team
4. 选择真机或 iPhone Simulator 运行

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

## 验证

动态 / 搜索 / 路由逻辑的 core 校验：

```bash
FOCUS_INCLUDE_TESTS=1 swift test --scratch-path .build-tests
```

运行时注入校验：

```bash
swift run --scratch-path .build FocusVerifier
```

## 已知取舍

- 动态接口使用 Bilibili 当前网页关注流接口；未登录或 Cookie 失效时直接报登录失效，不降级热门流
- 搜索第一版只有关键词提交，没有搜索历史、联想和原生结果列表
- 动态详情仍然走官方网页 DOM，只做最小去干扰

## 旧脚本

根目录的 `bilibili-FOCUS.js` 只作为原型参考，当前实现不再依赖 `GM_*` 运行时。
