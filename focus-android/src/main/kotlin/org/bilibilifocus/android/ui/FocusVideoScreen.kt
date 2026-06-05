package org.bilibilifocus.android.ui

import android.annotation.SuppressLint
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import coil.compose.AsyncImage
import coil.request.ImageRequest
import org.bilibilifocus.android.AndroidCookieProvider
import org.bilibilifocus.android.FocusVideoViewModel
import org.bilibilifocus.android.VideoUiState
import org.bilibilifocus.core.model.VideoComment
import org.bilibilifocus.core.model.VideoInfo
import org.bilibilifocus.core.service.KtorHttpClient
import org.bilibilifocus.core.service.VideoInfoService
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FocusVideoScreen(
    url: String,
    onBack: () -> Unit,
    onOpenUser: (Long) -> Unit = {},
    onOpenVideo: (String) -> Unit = {},
) {
    val bvid = remember(url) { VideoInfoService.extractBvid(url) }

    val viewModel = remember(url) {
        FocusVideoViewModel(
            service = VideoInfoService(
                cookieProvider = AndroidCookieProvider(),
                httpClient = KtorHttpClient(),
            )
        )
    }

    if (bvid != null) {
        androidx.compose.runtime.LaunchedEffect(bvid) {
            viewModel.load(bvid)
        }
    }

    val state by viewModel.state.collectAsState()
    val comments by viewModel.comments.collectAsState()
    val screenWidth = LocalConfiguration.current.screenWidthDp.dp
    val playerHeight = screenWidth * 9f / 16f

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = {
                    val title = (state as? VideoUiState.Loaded)?.info?.title ?: "视频"
                    Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis)
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                },
                colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    titleContentColor = MaterialTheme.colorScheme.onSurface,
                ),
            )
        },
    ) { innerPadding ->
        if (bvid == null) {
            Box(
                modifier = Modifier.fillMaxSize().padding(innerPadding),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("无法识别视频链接", style = MaterialTheme.typography.bodyMedium)
                    Text(url, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        } else when (val s = state) {
            VideoUiState.Loading -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(innerPadding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                }
            }

            is VideoUiState.Error -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(innerPadding),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(s.message, style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }

            is VideoUiState.Loaded -> {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding)
                        .verticalScroll(rememberScrollState()),
                ) {
                    WebPlayerView(
                        aid = s.info.aid,
                        bvid = s.info.bvid,
                        cid = s.info.cid,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(playerHeight)
                            .background(Color.Black),
                    )

                    Column(
                        modifier = Modifier.padding(horizontal = 16.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        Spacer(modifier = Modifier.height(4.dp))

                        Text(
                            text = s.info.title,
                            style = MaterialTheme.typography.titleLarge,
                        )

                        if (s.info.tags.isNotEmpty()) {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                s.info.tags.forEach { tag ->
                                    FilterChip(
                                        selected = false,
                                        onClick = {},
                                        label = { Text(tag, style = MaterialTheme.typography.labelSmall) },
                                        shape = RoundedCornerShape(8.dp),
                                        colors = FilterChipDefaults.filterChipColors(
                                            containerColor = MaterialTheme.colorScheme.secondaryContainer,
                                            labelColor = MaterialTheme.colorScheme.onSecondaryContainer,
                                        ),
                                    )
                                }
                            }
                        }

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            StatItem(formatCount(s.info.stats.views), "播放")
                            StatItem(formatCount(s.info.stats.likes), "点赞")
                            StatItem(formatCount(s.info.stats.coins), "硬币")
                            StatItem(formatCount(s.info.stats.favorites), "收藏")
                            StatItem(formatCount(s.info.stats.danmaku), "弹幕")
                        }

                        Spacer(modifier = Modifier.height(4.dp))

                        AuthorCard(s.info, onClick = { onOpenUser(s.info.author.mid) })

                        if (s.info.description.isNotBlank()) {
                            ExpandableDescription(s.info.description)
                        }

                        if (comments.isNotEmpty()) {
                            Text(
                                "评论 (${comments.size})",
                                style = MaterialTheme.typography.titleMedium,
                                modifier = Modifier.padding(top = 8.dp),
                            )
                            comments.forEach { comment ->
                                CommentItem(comment)
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(32.dp))
                }
            }
        }
    }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun WebPlayerView(
    aid: Long,
    bvid: String,
    cid: Long,
    modifier: Modifier = Modifier,
) {
    val isAid = aid > 0
    val playerUrl = if (isAid) {
        "https://player.bilibili.com/player.html?aid=$aid&cid=$cid&page=1&high_quality=1&autoplay=1&as_wide=1"
    } else {
        "https://player.bilibili.com/player.html?bvid=$bvid&cid=$cid&page=1&high_quality=1&autoplay=1&as_wide=1"
    }

    val wrapperHtml = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width,initial-scale=1.0,maximum-scale=1.0,user-scalable=no">
        <style>
          html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:#000}
          iframe{position:fixed;top:0;left:0;width:100%;height:100%;border:0}
        </style>
        </head>
        <body>
        <iframe src="$playerUrl" allow="autoplay;fullscreen" allowfullscreen="true" scrolling="no"></iframe>
        </body>
        </html>
    """.trimIndent()

    val htmlKey = remember(aid, bvid, cid) { wrapperHtml }

    AndroidView(
        factory = { ctx ->
            val container = FrameLayout(ctx)
            container.layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            container.setBackgroundColor(android.graphics.Color.BLACK)

            val webView = WebView(ctx).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                )

                try {
                    val cm = CookieManager.getInstance()
                    cm.setAcceptCookie(true)
                    for (domain in listOf("https://bilibili.com", "https://www.bilibili.com", "https://m.bilibili.com", "https://api.bilibili.com")) {
                        val cookieStr = cm.getCookie(domain) ?: continue
                        for (cookie in cookieStr.split(";")) {
                            val trimmed = cookie.trim()
                            if (trimmed.isNotEmpty()) {
                                cm.setCookie("https://player.bilibili.com", trimmed)
                                cm.setCookie("https://.bilibili.com", trimmed)
                            }
                        }
                    }
                    cm.flush()
                } catch (_: Exception) {}

                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.mediaPlaybackRequiresUserGesture = false
                settings.mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                settings.allowContentAccess = true
                settings.allowFileAccess = true
                settings.setSupportZoom(false)
                settings.loadWithOverviewMode = true
                settings.useWideViewPort = true
                settings.userAgentString = "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

                webChromeClient = object : WebChromeClient() {
                    private var customView: View? = null
                    private var customViewCallback: CustomViewCallback? = null

                    override fun onShowCustomView(view: View?, callback: CustomViewCallback?) {
                        if (customView != null) {
                            callback?.onCustomViewHidden()
                            return
                        }

                        customView = view
                        customViewCallback = callback

                        container.removeAllViews()
                        view?.let {
                            it.layoutParams = FrameLayout.LayoutParams(
                                FrameLayout.LayoutParams.MATCH_PARENT,
                                FrameLayout.LayoutParams.MATCH_PARENT,
                            )
                            container.addView(it)
                        }

                        // 进入全屏：隐藏系统UI
                        val activity = (ctx as? android.app.Activity)
                        activity?.window?.let { window ->
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                                window.insetsController?.let { controller ->
                                    controller.hide(android.view.WindowInsets.Type.statusBars() or android.view.WindowInsets.Type.navigationBars())
                                    controller.systemBarsBehavior = android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                                }
                            } else {
                                @Suppress("DEPRECATION")
                                window.decorView.systemUiVisibility = (
                                    View.SYSTEM_UI_FLAG_FULLSCREEN
                                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                                    or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                                )
                            }
                        }
                    }

                    override fun onHideCustomView() {
                        if (customView == null) return

                        // 退出全屏：恢复系统UI
                        val activity = (ctx as? android.app.Activity)
                        activity?.window?.let { window ->
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                                window.insetsController?.show(android.view.WindowInsets.Type.statusBars() or android.view.WindowInsets.Type.navigationBars())
                            } else {
                                @Suppress("DEPRECATION")
                                window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE
                            }
                        }

                        container.removeAllViews()
                        container.addView(this@apply)

                        customView = null
                        customViewCallback?.onCustomViewHidden()
                        customViewCallback = null
                    }
                }

                webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(
                        view: WebView?,
                        request: WebResourceRequest?,
                    ): Boolean {
                        val scheme = request?.url?.scheme ?: return false
                        if (scheme == "https" || scheme == "http") return false
                        return true
                    }
                }
            }

            container.addView(webView)
            container.tag = webView
            container
        },
        update = { container ->
            val webView = container.tag as? WebView ?: return@AndroidView
            val currentUrl = webView.url ?: ""
            if (currentUrl.isEmpty()) {
                webView.loadDataWithBaseURL("https://www.bilibili.com/", htmlKey, "text/html", "UTF-8", null)
            }
        },
        modifier = modifier,
    )
}

@Composable
private fun StatItem(value: String, label: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurface)
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun AuthorCard(info: VideoInfo, onClick: () -> Unit = {}) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .clickable { onClick() }
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        AsyncImage(
            model = ImageRequest.Builder(LocalContext.current)
                .data(info.author.avatarURL)
                .crossfade(true)
                .build(),
            contentDescription = null,
            modifier = Modifier.size(44.dp).clip(CircleShape),
            contentScale = ContentScale.Crop,
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(info.author.name, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("UID: ${info.author.mid}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ExpandableDescription(desc: String) {
    var expanded by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text("简介", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
        Text(
            text = desc,
            style = MaterialTheme.typography.bodyMedium,
            maxLines = if (expanded) Int.MAX_VALUE else 3,
            overflow = TextOverflow.Ellipsis,
        )
        if (desc.length > 120) {
            Text(
                text = if (expanded) "收起" else "展开",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.clickable { expanded = !expanded },
            )
        }
    }
}

@Composable
private fun CommentItem(comment: VideoComment) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            AsyncImage(
                model = ImageRequest.Builder(LocalContext.current)
                    .data(comment.avatarURL)
                    .crossfade(true)
                    .build(),
                contentDescription = null,
                modifier = Modifier.size(28.dp).clip(CircleShape),
                contentScale = ContentScale.Crop,
            )
            Text(comment.authorName, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
            Spacer(modifier = Modifier.weight(1f))
            Text(
                formatTimeAgo(comment.publishTime),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text("${comment.likeCount}赞", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(comment.content, style = MaterialTheme.typography.bodyMedium)

        comment.replies.take(3).forEach { reply ->
            Row(modifier = Modifier.padding(start = 36.dp, top = 4.dp)) {
                Text(
                    "${reply.authorName}: ${reply.content}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

private fun formatCount(count: Long): String = when {
    count >= 10000L -> {
        val v = count / 1000 / 10.0
        if (v >= 10) "${v.toLong()}万" else "%.1f万".format(v)
    }
    else -> count.toString()
}

private fun formatTimeAgo(ts: Long): String {
    val now = System.currentTimeMillis() / 1000
    val diff = now - ts
    return when {
        diff < 60 -> "刚刚"
        diff < 3600 -> "${diff / 60}分钟前"
        diff < 86400 -> "${diff / 3600}小时前"
        else -> {
            val sdf = SimpleDateFormat("MM-dd", Locale.getDefault())
            sdf.format(Date(ts * 1000))
        }
    }
}
