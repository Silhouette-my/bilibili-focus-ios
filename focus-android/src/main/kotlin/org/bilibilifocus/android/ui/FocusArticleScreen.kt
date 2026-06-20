package org.bilibilifocus.android.ui

import android.annotation.SuppressLint
import android.graphics.Color as AndroidColor
import android.webkit.WebView
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
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
import androidx.compose.foundation.ScrollState
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import coil.compose.AsyncImage
import coil.request.ImageRequest
import org.bilibilifocus.android.AndroidCookieProvider
import org.bilibilifocus.android.ArticleUiState
import org.bilibilifocus.android.FocusArticleViewModel
import org.bilibilifocus.core.model.ArticleDetail
import org.bilibilifocus.core.service.ArticleService
import org.bilibilifocus.core.service.KtorHttpClient
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FocusArticleScreen(
    cvid: Long,
    onBack: () -> Unit,
    onOpenUser: (Long) -> Unit = {},
    viewModel: FocusArticleViewModel? = null,
    scrollState: ScrollState = rememberScrollState(),
) {
    val resolvedViewModel = viewModel ?: remember(cvid) {
        FocusArticleViewModel(
            service = ArticleService(
                cookieProvider = AndroidCookieProvider(),
                httpClient = KtorHttpClient(),
            )
        )
    }

    LaunchedEffect(cvid) {
        resolvedViewModel.loadIfNeeded(cvid)
    }

    val state by resolvedViewModel.state.collectAsState()
    val htmlContent by resolvedViewModel.htmlContent.collectAsState()

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = {
                    val title = (state as? ArticleUiState.Loaded)?.detail?.title ?: "专栏"
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
        when (val s = state) {
            ArticleUiState.Idle, ArticleUiState.Loading -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(innerPadding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                }
            }

            is ArticleUiState.Failed -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(innerPadding),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(s.message, style = MaterialTheme.typography.bodyMedium)
                }
            }

            ArticleUiState.LoginRequired -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(innerPadding),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("需要登录才能查看", style = MaterialTheme.typography.bodyMedium)
                }
            }

            is ArticleUiState.Loaded -> {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding)
                        .verticalScroll(scrollState),
                ) {
                    // Banner image
                    if (s.detail.bannerUrl.isNotBlank()) {
                        AsyncImage(
                            model = ImageRequest.Builder(LocalContext.current)
                                .data(s.detail.bannerUrl)
                                .crossfade(true)
                                .build(),
                            contentDescription = null,
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(200.dp),
                            contentScale = ContentScale.Crop,
                        )
                    }

                    Column(
                        modifier = Modifier.padding(horizontal = 16.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        Spacer(modifier = Modifier.height(4.dp))

                        Text(
                            text = s.detail.title,
                            style = MaterialTheme.typography.titleLarge,
                        )

                        ArticleAuthorCard(s.detail, onClick = { onOpenUser(s.detail.author.mid) })

                        if (s.detail.tags.isNotEmpty()) {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                s.detail.tags.take(5).forEach { tag ->
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
                            ArticleStatItem(formatCount(s.detail.stats.views), "阅读")
                            ArticleStatItem(formatCount(s.detail.stats.likes), "点赞")
                            ArticleStatItem(formatCount(s.detail.stats.coins), "硬币")
                            ArticleStatItem(formatCount(s.detail.stats.favorites), "收藏")
                            ArticleStatItem(formatCount(s.detail.stats.comments), "评论")
                        }

                        Spacer(modifier = Modifier.height(4.dp))

                        // 文章内容 - 使用 WebView 渲染
                        if (htmlContent.isNotBlank()) {
                            ArticleContentView(htmlContent = htmlContent)
                        }
                    }

                    Spacer(modifier = Modifier.height(32.dp))
                }
            }
        }
    }
}

@Composable
private fun ArticleAuthorCard(detail: ArticleDetail, onClick: () -> Unit = {}) {
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
                .data(detail.author.avatarURL)
                .crossfade(true)
                .build(),
            contentDescription = null,
            modifier = Modifier.size(44.dp).clip(CircleShape),
            contentScale = ContentScale.Crop,
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(detail.author.name, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
            val dateStr = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date(detail.publishTime * 1000))
            Text(dateStr, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ArticleStatItem(value: String, label: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurface)
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun ArticleContentView(htmlContent: String) {
    val isDarkTheme = isSystemInDarkTheme()
    val bodyTextColor = if (isDarkTheme) "#E7EAF0" else "#18191C"
    val bodyBackground = if (isDarkTheme) "#11151B" else "#FFFFFF"
    val linkColor = if (isDarkTheme) "#FF97B4" else "#00A1D6"
    val quoteTextColor = if (isDarkTheme) "#B7BFCC" else "#61666D"
    val codeBackground = if (isDarkTheme) "#1E2530" else "#F6F6F6"
    val dividerColor = if (isDarkTheme) "#303947" else "#E3E5E7"
    val tableHeaderColor = if (isDarkTheme) "#1A2028" else "#F6F6F6"
    val styledHtml = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width,initial-scale=1.0,maximum-scale=3.0,user-scalable=yes">
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            font-size: 17px;
            line-height: 1.8;
            color: $bodyTextColor;
            padding: 16px;
            background: $bodyBackground;
            word-wrap: break-word;
          }
          p { margin: 12px 0; }
          span, strong, em, li { color: inherit; }
          h1, h2, h3, h4, h5, h6 { margin: 20px 0 12px; font-weight: 600; line-height: 1.4; }
          h1 { font-size: 28px; }
          h2 { font-size: 24px; }
          h3 { font-size: 20px; }
          img {
            max-width: 100%;
            height: auto;
            display: block;
            margin: 16px 0;
            border-radius: 8px;
          }
          a { color: $linkColor; text-decoration: none; }
          blockquote {
            border-left: 4px solid $linkColor;
            padding-left: 16px;
            margin: 16px 0;
            color: $quoteTextColor;
          }
          pre, code {
            background: $codeBackground;
            border-radius: 4px;
            padding: 2px 6px;
            font-family: 'Courier New', monospace;
            font-size: 14px;
          }
          pre {
            padding: 12px;
            overflow-x: auto;
            margin: 16px 0;
          }
          pre code { padding: 0; background: transparent; }
          ul, ol { padding-left: 24px; margin: 12px 0; }
          li { margin: 8px 0; }
          table { border-collapse: collapse; width: 100%; margin: 16px 0; }
          th, td { border: 1px solid $dividerColor; padding: 8px 12px; text-align: left; color: $bodyTextColor; }
          th { background: $tableHeaderColor; font-weight: 600; }
          .video-wrap, .aid, figure { margin: 16px 0; }
        </style>
        </head>
        <body>
        $htmlContent
        </body>
        </html>
    """.trimIndent()

    AndroidView(
        factory = { context ->
            WebView(context).apply {
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.loadWithOverviewMode = true
                settings.useWideViewPort = true
                settings.setSupportZoom(true)
                settings.builtInZoomControls = true
                settings.displayZoomControls = false
                setBackgroundColor(AndroidColor.TRANSPARENT)
                loadDataWithBaseURL("https://www.bilibili.com/", styledHtml, "text/html", "UTF-8", null)
            }
        },
        modifier = Modifier
            .fillMaxWidth()
            .height(600.dp),
    )
}

private fun formatCount(count: Long): String = when {
    count >= 10000L -> {
        val v = count / 1000 / 10.0
        if (v >= 10) "${v.toLong()}万" else "%.1f万".format(v)
    }
    else -> count.toString()
}
