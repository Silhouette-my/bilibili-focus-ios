# Bilibili Focus Safari Userscript

这个目录用于分发给 iPhone / iPad 上的 Safari `Userscripts` 类工具。

## 生成

在仓库根目录运行：

```bash
swift run FocusUserscriptBuilder
```

默认会产出：

- `Userscript/bilibili-focus.user.js`
- 根目录的 `bilibili-FOCUS.js`

## 部署

1. 在 iPhone 上安装支持 Safari Userscripts 的脚本容器
2. 把 `bilibili-focus.user.js` 导入进去
3. 允许它匹配 `*.bilibili.com`

## 配置方式

由于 Safari userscript 没有原生 popup，这一版会在页面右下角提供一个可折叠的 `Focus` 设置面板，用来切换：

- 首页重定向
- 动态 / 搜索 / 播放页去干扰
- 调试日志
- 默认入口（动态 / 搜索）

## 说明

- 页面规则依然来自 `Sources/FocusCore`
- 修改 `FocusCore` 后，重新运行一次 `swift run FocusUserscriptBuilder` 即可刷新脚本
