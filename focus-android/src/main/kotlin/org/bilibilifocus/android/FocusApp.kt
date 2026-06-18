package org.bilibilifocus.android

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import org.bilibilifocus.android.ui.FocusArticleScreen
import org.bilibilifocus.android.ui.FocusDynamicFeedScreen
import org.bilibilifocus.android.ui.FocusLoginScreen
import org.bilibilifocus.android.ui.FocusOpusScreen
import org.bilibilifocus.android.ui.FocusRankScreen
import org.bilibilifocus.android.ui.FocusSearchScreen
import org.bilibilifocus.android.ui.FocusUserScreen
import org.bilibilifocus.android.ui.FocusVideoScreen
import org.bilibilifocus.android.ui.FocusWebView
import org.bilibilifocus.core.model.SearchResultItem
import org.bilibilifocus.core.service.VideoInfoService

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FocusApp() {
    var selectedTab by remember { mutableIntStateOf(0) }
    var showLogin by remember { mutableStateOf(false) }
    var videoUrl by remember { mutableStateOf<String?>(null) }
    var opusId by remember { mutableStateOf<String?>(null) }
    var articleCvid by remember { mutableStateOf<Long?>(null) }
    var userId by remember { mutableStateOf<Long?>(null) }
    var webViewUrl by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current

    val openInBrowser: (String) -> Unit = { url ->
        when {
            VideoInfoService.extractBvid(url) != null -> videoUrl = url
            else -> {
                val opusIdExtracted = extractOpusId(url)
                val cvid = extractArticleCvid(url)
                when {
                    opusIdExtracted != null -> opusId = opusIdExtracted
                    cvid != null -> articleCvid = cvid
                    else -> webViewUrl = url
                }
            }
        }
    }

    val openUser: (Long) -> Unit = { mid -> userId = mid }

    val openSearchItem: (SearchResultItem) -> Unit = { item ->
        openInBrowser(item.targetURL)
    }

    BackHandler(enabled = videoUrl != null) { videoUrl = null }
    BackHandler(enabled = opusId != null) { opusId = null }
    BackHandler(enabled = articleCvid != null) { articleCvid = null }
    BackHandler(enabled = userId != null) { userId = null }
    BackHandler(enabled = webViewUrl != null) { webViewUrl = null }
    BackHandler(enabled = showLogin) { showLogin = false }

    Box(modifier = Modifier.fillMaxSize()) {
        if (videoUrl != null) {
            videoUrl?.let { url ->
                FocusVideoScreen(
                    url = url,
                    onBack = { videoUrl = null },
                    onOpenUser = openUser,
                    onOpenVideo = { videoUrl = it },
                )
            }
        } else if (opusId != null) {
            opusId?.let { id ->
                FocusOpusScreen(
                    opusId = id,
                    onBack = { opusId = null },
                    onOpenUser = openUser,
                    onOpenVideo = { videoUrl = it },
                )
            }
        } else if (articleCvid != null) {
            articleCvid?.let { cvid ->
                FocusArticleScreen(
                    cvid = cvid,
                    onBack = { articleCvid = null },
                    onOpenUser = openUser,
                )
            }
        } else if (userId != null) {
            userId?.let { mid ->
                FocusUserScreen(
                    userId = mid,
                    onBack = { userId = null },
                    onOpenVideo = { videoUrl = it },
                )
            }
        } else if (webViewUrl != null) {
            webViewUrl?.let { url ->
                Scaffold(
                    topBar = {
                        CenterAlignedTopAppBar(
                            title = { Text("浏览", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                            navigationIcon = {
                                IconButton(onClick = { webViewUrl = null }) {
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
                    Box(modifier = Modifier.fillMaxSize().padding(innerPadding)) {
                        FocusWebView(
                            url = url,
                            onUrlChanged = {},
                            onPageStarted = {},
                            onPageFinished = {},
                            onError = {},
                        )
                    }
                }
            }
        } else {
            Scaffold(
                topBar = {
                    CenterAlignedTopAppBar(
                        title = { Text("Bilibili Focus") },
                        colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                            containerColor = MaterialTheme.colorScheme.surface,
                            titleContentColor = MaterialTheme.colorScheme.onSurface,
                        ),
                    )
                },
                bottomBar = {
                    NavigationBar(
                        containerColor = MaterialTheme.colorScheme.surface,
                        tonalElevation = 3.dp,
                    ) {
                        NavigationBarItem(
                            icon = {
                                Icon(
                                    imageVector = if (selectedTab == 0) Icons.Filled.Home else Icons.Outlined.Home,
                                    contentDescription = "动态",
                                )
                            },
                            label = { Text("动态") },
                            selected = selectedTab == 0,
                            onClick = { selectedTab = 0 },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = MaterialTheme.colorScheme.primary,
                                selectedTextColor = MaterialTheme.colorScheme.primary,
                                unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                                unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
                                indicatorColor = MaterialTheme.colorScheme.primaryContainer,
                            ),
                        )
                        NavigationBarItem(
                            icon = {
                                Icon(
                                    imageVector = if (selectedTab == 1) Icons.Filled.Search else Icons.Outlined.Search,
                                    contentDescription = "搜索",
                                )
                            },
                            label = { Text("搜索") },
                            selected = selectedTab == 1,
                            onClick = { selectedTab = 1 },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = MaterialTheme.colorScheme.primary,
                                selectedTextColor = MaterialTheme.colorScheme.primary,
                                unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                                unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
                                indicatorColor = MaterialTheme.colorScheme.primaryContainer,
                            ),
                        )
                        NavigationBarItem(
                            icon = {
                                Icon(
                                    imageVector = if (selectedTab == 2) Icons.Filled.Star else Icons.Outlined.Star,
                                    contentDescription = "排行",
                                )
                            },
                            label = { Text("排行") },
                            selected = selectedTab == 2,
                            onClick = { selectedTab = 2 },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = MaterialTheme.colorScheme.primary,
                                selectedTextColor = MaterialTheme.colorScheme.primary,
                                unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                                unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
                                indicatorColor = MaterialTheme.colorScheme.primaryContainer,
                            ),
                        )
                    }
                },
            ) { innerPadding ->
                Box(modifier = Modifier.fillMaxSize().padding(innerPadding)) {
                    when (selectedTab) {
                        0 -> FocusDynamicFeedScreen(
                            onOpenLogin = { showLogin = true },
                            onOpenCard = { card -> openInBrowser(card.targetURL) },
                        )
                        1 -> FocusSearchScreen(
                            onOpenItem = openSearchItem,
                            onOpenLogin = { showLogin = true },
                        )
                        2 -> FocusRankScreen(
                            onOpenVideo = { videoUrl = it },
                        )
                    }
                }
            }
        }

        AnimatedVisibility(
            visible = showLogin,
            enter = fadeIn(),
            exit = fadeOut(),
        ) {
            FocusLoginScreen(
                onBack = { showLogin = false },
                onLoginComplete = { showLogin = false },
            )
        }
    }
}

private fun extractOpusId(url: String): String? {
    // bilibili.com/opus/12345 (new opus detail page)
    Regex("""bilibili\.com/opus/(\d+)""").find(url)?.groupValues?.getOrNull(1)?.let { return it }
    // t.bilibili.com/12345 (old dynamic detail page — same content)
    Regex("""t\.bilibili\.com/(\d+)""").find(url)?.groupValues?.getOrNull(1)?.let { return it }
    // vc.bilibili.com/opus/detail/12345
    Regex("""opus/detail/(\d+)""").find(url)?.groupValues?.getOrNull(1)?.let { return it }
    return null
}

private fun extractArticleCvid(url: String): Long? {
    // bilibili.com/read/cv12345
    Regex("""bilibili\.com/read/cv(\d+)""").find(url)?.groupValues?.getOrNull(1)?.toLongOrNull()?.let { return it }
    // www.bilibili.com/read/cv12345
    Regex("""www\.bilibili\.com/read/cv(\d+)""").find(url)?.groupValues?.getOrNull(1)?.toLongOrNull()?.let { return it }
    return null
}
