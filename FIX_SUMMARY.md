# Bilibili Focus 修复总结

## 已修复问题

### 1. ✅ 视频播放无法全屏
**问题原因：**
- WebChromeClient 的 `onShowCustomView` 实现不完整
- 缺少系统UI控制
- Activity 配置缺少必要的 `configChanges`

**修复方案：**
- 在 `FocusVideoScreen.kt` 中增强 `WebChromeClient`
- 添加完整的 `customView` 生命周期管理
- 进入全屏时隐藏系统UI（状态栏、导航栏）
- 退出全屏时恢复系统UI
- 在 `AndroidManifest.xml` 中添加 `android:configChanges="orientation|screenSize|keyboardHidden"`
- 添加 `android:supportsPictureInPicture="true"` 支持画中画

**修改文件：**
- `focus-android/src/main/kotlin/org/bilibilifocus/android/ui/FocusVideoScreen.kt`
- `focus-android/src/main/AndroidManifest.xml`

---

### 2. ✅ 图文专栏使用 WebKit 体验很烂
**问题原因：**
- 专栏文章（cv开头）完全依赖原生 WebView 加载完整网页
- 加载慢、样式混乱、包含大量无关元素

**修复方案：**
- 创建原生专栏渲染系统，类似现有的 Opus 渲染
- 添加 `ArticleDetail` 数据模型
- 创建 `ArticleService` 服务层调用 bilibili API
- 创建 `FocusArticleViewModel` 管理状态
- 创建 `FocusArticleScreen` UI 界面
- 使用优化的 WebView 渲染文章内容（仅内容部分，带自定义样式）
- 添加作者信息、标签、统计数据等原生组件

**新增文件：**
- `focus-core/src/commonMain/kotlin/org/bilibilifocus/core/model/ArticleDetail.kt`
- `focus-core/src/commonMain/kotlin/org/bilibilifocus/core/service/ArticleService.kt`
- `focus-android/src/main/kotlin/org/bilibilifocus/android/FocusArticleViewModel.kt`
- `focus-android/src/main/kotlin/org/bilibilifocus/android/ui/FocusArticleScreen.kt`

**修改文件：**
- `focus-android/src/main/kotlin/org/bilibilifocus/android/FocusApp.kt` - 添加专栏路由

**特性：**
- 自动识别 `bilibili.com/read/cv123456` 格式的专栏链接
- 原生 UI 组件（标题、作者卡片、标签、统计）
- 优化的 HTML 渲染（自定义样式、响应式布局）
- 支持作者点击跳转
- Material 3 设计风格统一

---

## 下一步方向规划

根据现有代码和 bilibili-api 功能，已创建详细的开发路线图：

### 🔥 最推荐的近期任务（按优先级）：

1. **画中画 + 播放历史**
   - AndroidManifest 已配置 PiP 支持
   - 需要实现 Activity 级别的画中画控制
   - 添加播放进度记录和历史查看

2. **收藏 + 稍后再看**
   - bilibili-api 的 `favorite.py` 提供完整 API
   - 完善内容管理功能
   - 提升用户留存

3. **视频下载（离线功能）**
   - 使用 WorkManager 后台下载
   - Room 数据库管理
   - 这是 Focus 的差异化优势

4. **评论交互完善**
   - 当前只显示评论，无交互
   - 添加点赞、回复、发送功能
   - bilibili-api 的 `comment.py` 提供完整支持

5. **番剧支持**
   - 扩大内容覆盖范围
   - bilibili-api 的 `bangumi.py` 功能完整

### 📊 可用资源：

**bilibili-api 已有 43 个模块：**
- ✅ video.py - 视频功能
- ✅ article.py - 专栏（已实现）
- ✅ opus.py - 图文（已实现）
- ✅ comment.py - 评论系统
- ✅ favorite.py - 收藏
- ✅ bangumi.py - 番剧
- ✅ live.py - 直播
- ✅ audio.py - 音频
- 等等...

详细内容见 `ROADMAP.md`

---

## 架构现状

### 技术栈
- Kotlin Multiplatform (KMP)
- Jetpack Compose + Material 3
- Ktor (网络层)
- kotlinx.serialization

### 代码规模
- Android 层：22 个 Kotlin 文件
- Core 层：50 个 Kotlin 文件
- 架构清晰，易于扩展

### 特色功能
- 内容过滤脚本（去广告、去推荐）
- Cookie 管理
- 多种内容类型支持（视频、动态、专栏、用户）

---

## 构建测试

请运行以下命令测试修复：

```bash
# 清理并重新构建
./gradlew clean
./gradlew :focus-android:assembleDebug

# 或者直接安装到设备
./gradlew :focus-android:installDebug
```

### 测试要点：

1. **全屏测试：**
   - 打开任意视频
   - 点击播放器的全屏按钮
   - 验证是否进入全屏且系统UI隐藏
   - 退出全屏验证UI恢复

2. **专栏测试：**
   - 在动态或搜索中找到专栏链接（cv开头）
   - 点击打开
   - 验证是否原生渲染（而非完整网页）
   - 检查作者卡片、标签、统计数据显示

---

## 注意事项

1. **bilibili-api 集成方式：**
   - 当前采用逐步迁移 Python API 到 Kotlin 的方案
   - 保持代码轻量，避免引入 Python 运行时

2. **维护建议：**
   - 定期查看 bilibili-api 更新
   - API 变动可能导致功能失效
   - 关注 bilibili 官方接口变更

3. **隐私与合规：**
   - 仅用于学习和个人使用
   - 不应用于商业用途
   - 遵守 bilibili 服务条款

---

## 相关文档

- **开发路线图：** `ROADMAP.md`
- **项目说明：** `README.md`
- **代码仓库：** 当前目录

---

**修复完成时间：** 2026-06-05
**测试状态：** 待用户验证
