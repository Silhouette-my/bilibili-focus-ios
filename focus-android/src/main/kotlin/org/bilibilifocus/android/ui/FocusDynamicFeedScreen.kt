package org.bilibilifocus.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import org.bilibilifocus.android.AndroidCookieProvider
import org.bilibilifocus.android.FocusFeedViewModel
import org.bilibilifocus.android.FeedUiState
import org.bilibilifocus.core.model.DynamicCard
import org.bilibilifocus.core.service.DynamicFeedService
import org.bilibilifocus.core.service.KtorHttpClient

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun FocusDynamicFeedScreen(
    onOpenLogin: () -> Unit = {},
    onOpenCard: (DynamicCard) -> Unit = {},
) {
    val viewModel = remember {
        FocusFeedViewModel(
            service = DynamicFeedService(
                cookieProvider = AndroidCookieProvider(),
                httpClient = KtorHttpClient(),
            )
        )
    }

    LaunchedEffect(Unit) {
        viewModel.loadIfNeeded()
    }

    val state by viewModel.state.collectAsState()
    val isLoadingMore by viewModel.isLoadingMore.collectAsState()
    var isRefreshing by remember { mutableStateOf(false) }

    when (val s = state) {
        FeedUiState.Idle, FeedUiState.Loading -> {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
            }
        }

        FeedUiState.LoginRequired -> {
            Box(
                modifier = Modifier.fillMaxSize().padding(32.dp),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Text("需要登录", style = MaterialTheme.typography.headlineSmall)
                    Text(
                        "先在网页登录 Bilibili，再回来刷新",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Button(onClick = onOpenLogin) { Text("去登录") }
                    Button(
                        onClick = { viewModel.reload() },
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.secondaryContainer,
                            contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
                        ),
                    ) {
                        Text("重新检测登录态")
                    }
                }
            }
        }

        is FeedUiState.Failed -> {
            Box(modifier = Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Text("动态加载失败", style = MaterialTheme.typography.headlineSmall)
                    Text(s.message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Button(onClick = { viewModel.reload() }) { Text("重试") }
                }
            }
        }

        is FeedUiState.Empty -> {
            PullToRefreshBox(
                isRefreshing = isRefreshing,
                onRefresh = { viewModel.refresh { isRefreshing = false } },
            ) {
                Box(modifier = Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        Text("暂无可显示的关注动态", style = MaterialTheme.typography.headlineSmall)
                        Text(
                            "当前页面没有拿到内容，稍后可以再刷新一次",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Button(onClick = { viewModel.reload() }) { Text("重新加载") }
                    }
                }
            }
        }

        is FeedUiState.Loaded -> {
            PullToRefreshBox(
                isRefreshing = isRefreshing,
                onRefresh = {
                    viewModel.refresh { isRefreshing = false }
                },
            ) {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    items(s.cards, key = { it.id }) { card ->
                        ElevatedCard(
                            onClick = { onOpenCard(card) },
                            shape = RoundedCornerShape(12.dp),
                            colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surface),
                            elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
                        ) {
                            FocusDynamicCard(card = card)
                        }
                    }

                    if (isLoadingMore) {
                        item {
                            Box(modifier = Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(24.dp),
                                    color = MaterialTheme.colorScheme.primary,
                                    strokeWidth = 2.dp,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun FocusDynamicCard(card: DynamicCard) {
    Column(
        modifier = Modifier.padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            FocusAvatar(
                avatarURL = card.author.avatarURL,
                modifier = Modifier.size(44.dp),
            )

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    text = card.author.name,
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (card.publishTime.isNotEmpty()) {
                        Text(
                            text = card.publishTime,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    FocusKindBadge(kind = card.kind)
                }
            }
        }

        if (card.text.isNotEmpty()) {
            Text(
                text = card.text,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 6,
                overflow = TextOverflow.Ellipsis,
            )
        }

        if (card.coverURLs.isNotEmpty()) {
            val columnCount = if (card.coverURLs.size == 1) 1 else 2
            val rows = card.coverURLs.chunked(columnCount)
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                rows.forEach { rowUrls ->
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        rowUrls.forEach { url ->
                            val height = if (card.coverURLs.size == 1) 220 else 148
                            FocusCoverImage(
                                url = url,
                                modifier = Modifier
                                    .weight(1f)
                                    .height(height.dp)
                                    .clip(RoundedCornerShape(12.dp)),
                            )
                        }
                        repeat(columnCount - rowUrls.size) {
                            Spacer(modifier = Modifier.weight(1f))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun FocusAvatar(avatarURL: String?, modifier: Modifier = Modifier) {
    AsyncImage(
        model = ImageRequest.Builder(LocalContext.current)
            .data(avatarURL)
            .crossfade(true)
            .build(),
        contentDescription = null,
        modifier = modifier.clip(CircleShape),
        contentScale = ContentScale.Crop,
    )
}

@Composable
private fun FocusCoverImage(url: String, modifier: Modifier = Modifier) {
    AsyncImage(
        model = ImageRequest.Builder(LocalContext.current)
            .data(url)
            .crossfade(true)
            .build(),
        contentDescription = null,
        modifier = modifier,
        contentScale = ContentScale.Crop,
    )
}

@Composable
private fun FocusKindBadge(kind: DynamicCard.Kind) {
    val (label, containerColor, contentColor) = when (kind) {
        DynamicCard.Kind.TEXT -> Triple(
            "文字",
            MaterialTheme.colorScheme.tertiaryContainer,
            MaterialTheme.colorScheme.onTertiaryContainer,
        )
        DynamicCard.Kind.IMAGE -> Triple(
            "图片",
            MaterialTheme.colorScheme.secondaryContainer,
            MaterialTheme.colorScheme.onSecondaryContainer,
        )
        DynamicCard.Kind.VIDEO -> Triple(
            "视频",
            MaterialTheme.colorScheme.primaryContainer,
            MaterialTheme.colorScheme.onPrimaryContainer,
        )
        DynamicCard.Kind.ARTICLE_LIKE -> Triple(
            "专栏",
            MaterialTheme.colorScheme.tertiaryContainer,
            MaterialTheme.colorScheme.onTertiaryContainer,
        )
    }

    Text(
        text = label,
        style = MaterialTheme.typography.labelSmall,
        color = contentColor,
        modifier = Modifier
            .background(containerColor, RoundedCornerShape(4.dp))
            .padding(horizontal = 6.dp, vertical = 2.dp),
    )
}
