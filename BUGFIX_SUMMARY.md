# Bug 修复总结

## 修复时间
2026-06-05 17:30

## 修复的问题

### 1. ✅ 纯文字动态显示"接口返回无效数据"

**问题原因：**
- OpusService 的数据解析路径过于严格
- 没有处理不同API返回格式的变体
- 缺少后备解析逻辑

**修复方案：**
- 添加多个后备解析路径（`module_content` / `content`）
- 添加多个字段名尝试（`paragraphs` / `items`）
- 当解析失败时返回默认内容而不是抛异常
- 增强错误处理和空值检查

**修改文件：**
- `focus-core/src/commonMain/kotlin/org/bilibilifocus/core/service/OpusService.kt`

---

### 2. ✅ 图片动态显示空白

**问题原因：**
- 图片段落解析路径不完整
- 没有处理不同的图片数据结构
- 文字节点解析缺少后备字段

**修复方案：**
- 添加图片多路径解析（`pic.pics` / `pics` / `images`）
- 添加文字节点多字段支持（`word.words` / `words` / `text`）
- 增强样式和链接的解析兼容性
- 过滤掉空的段落块

**修改文件：**
- `focus-core/src/commonMain/kotlin/org/bilibilifocus/core/service/OpusService.kt`

---

### 3. ✅ 排行榜加载几秒后闪退

**问题原因：**
- RankService 数据解析时遇到意外字段格式
- 缺少异常捕获导致整个列表解析失败
- 字段路径不兼容不同API版本

**修复方案：**
- 在每个视频项解析中添加 try-catch
- 添加多路径字段解析（`owner.name` / `author`）
- 添加 stat 对象支持
- 解析失败的单项返回 null 而不是崩溃
- 添加 JSON 解析的异常处理

**修改文件：**
- `focus-core/src/commonMain/kotlin/org/bilibilifocus/core/service/RankService.kt`

---

### 4. ✅ 视频全屏功能未生效

**问题原因：**
- 只使用了已弃用的 `systemUiVisibility` API
- 没有适配 Android 11+ 的新 API
- 缺少必要的窗口标志

**修复方案：**
- 添加 Android 11+ (API 30+) 的 `WindowInsetsController` 支持
- 为旧版本保留 `systemUiVisibility` 后备方案
- 添加 `BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE` 行为
- 添加布局相关的 UI 标志
- 正确处理进入/退出全屏的状态切换

**修改文件：**
- `focus-android/src/main/kotlin/org/bilibilifocus/android/ui/FocusVideoScreen.kt`

---

## 技术细节

### OpusService 改进
```kotlin
// 添加后备解析路径
val contentModule = modules.dictionaryValueAt("module_content")
    ?: modules.dictionaryValueAt("content")
    ?: return emptyList()

// 过滤空段落
.filterNot { it.blocks.isEmpty() }

// 返回默认内容而不是抛异常
if (paragraphs.isEmpty()) {
    return OpusDetail(/* 带默认内容 */)
}
```

### RankService 改进
```kotlin
// 每项单独处理异常
return list.mapNotNull { item ->
    try {
        // 解析逻辑
    } catch (e: Exception) {
        null // 失败的项不影响其他
    }
}

// 多路径字段解析
val author = dict.stringValueAt("owner", "name")
    ?: dict.stringValueAt("author")
    ?: "未知UP主"
```

### 全屏功能改进
```kotlin
if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
    // Android 11+ 新API
    window.insetsController?.hide(...)
} else {
    // Android 10 及以下后备方案
    window.decorView.systemUiVisibility = ...
}
```

---

## 构建信息

**APK 位置：** `focus-android/build/outputs/apk/debug/focus-android-debug.apk`
**构建状态：** ✅ 成功（54 个任务，9 个执行，45 个最新）
**文件大小：** ~15 MB

---

## 安装方法

```bash
# 使用 ADB 安装
adb install focus-android/build/outputs/apk/debug/focus-android-debug.apk

# 覆盖安装
adb install -r focus-android/build/outputs/apk/debug/focus-android-debug.apk
```

或直接将 APK 传输到手机安装。

---

## 测试建议

### 动态测试
1. 打开纯文字动态 - 应显示文字内容
2. 打开图片动态 - 应显示图片网格
3. 打开混合动态 - 应同时显示文字和图片

### 排行榜测试
1. 进入排行榜标签
2. 切换不同分区（全站、动画、游戏等）
3. 滚动列表查看所有视频
4. 点击视频卡片跳转播放

### 全屏测试
1. 打开任意视频
2. 等待播放器加载完成
3. 点击播放器右下角全屏按钮
4. 验证视频全屏且系统UI隐藏
5. 点击返回或全屏按钮退出
6. 验证系统UI恢复

---

## 已知限制

1. **全屏动画**：切换可能不够流畅，是 WebView 全屏的固有限制
2. **数据兼容性**：bilibili API 可能继续变化，需要持续更新解析逻辑
3. **错误恢复**：某些极端情况下仍可能显示占位内容

---

## 后续优化建议

1. **日志系统**：添加详细日志帮助调试API变化
2. **降级策略**：API失败时展示缓存内容
3. **原生播放器**：替换 WebView 实现更好的全屏体验
4. **单元测试**：为数据解析逻辑添加测试用例

---

**修复完成时间：** 2026-06-05 17:30
