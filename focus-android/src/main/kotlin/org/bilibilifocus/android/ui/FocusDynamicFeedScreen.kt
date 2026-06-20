package org.bilibilifocus.android.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.SearchBar
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.SmallFloatingActionButton
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
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
import androidx.compose.ui.layout.ContentScale.Companion.Crop
import androidx.compose.ui.layout.ContentScale.Companion.Fit
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.geometry.Size
import coil.compose.AsyncImage
import coil.compose.AsyncImagePainter
import coil.compose.rememberAsyncImagePainter
import coil.request.ImageRequest
import org.bilibilifocus.android.AndroidCookieProvider
import org.bilibilifocus.android.FocusFeedViewModel
import org.bilibilifocus.android.FeedUiState
import org.bilibilifocus.core.model.DynamicCard
import org.bilibilifocus.core.service.DynamicFeedService
import org.bilibilifocus.core.service.KtorHttpClient

private val DynamicCoverCornerRadius = RoundedCornerShape(6.dp)

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun FocusDynamicFeedScreen(
    viewModel: FocusFeedViewModel,
    listState: LazyListState,
    onOpenLogin: () -> Unit = {},
    onOpenCard: (DynamicCard) -> Unit = {},
    onOpenSearch: (String) -> Unit = {},
    contentPadding: PaddingValues = PaddingValues(),
) {
    LaunchedEffect(Unit) {
        viewModel.loadIfNeeded()
    }

    val state by viewModel.state.collectAsState()
    val isLoadingMore by viewModel.isLoadingMore.collectAsState()
    var isRefreshing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    var searchQuery by remember { mutableStateOf("") }
    val showScrollTop by remember { derivedStateOf { listState.firstVisibleItemIndex > 3 } }

    Column(modifier = Modifier.fillMaxSize().padding(top = contentPadding.calculateTopPadding())) {
        // 顶部搜索框：提交后跳到搜索 tab 执行查询
        SearchBar(
            inputField = {
                SearchBarDefaults.InputField(
                    query = searchQuery,
                    onQueryChange = { searchQuery = it },
                    onSearch = { if (searchQuery.isNotBlank()) onOpenSearch(searchQuery.trim()) },
                    expanded = false,
                    onExpandedChange = {},
                    placeholder = { Text("搜索视频、UP主、番剧…") },
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = "搜索") },
                )
            },
            expanded = false,
            onExpandedChange = {},
            shape = RoundedCornerShape(28.dp),
            colors = SearchBarDefaults.colors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
            windowInsets = WindowInsets(0, 0, 0, 0),
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
        ) {}

        Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
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
                            state = listState,
                            modifier = Modifier.fillMaxSize(),
                            contentPadding = PaddingValues(
                                start = 16.dp,
                                end = 16.dp,
                                top = 12.dp,
                                bottom = 12.dp + contentPadding.calculateBottomPadding(),
                            ),
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            items(s.cards, key = { it.id }) { card ->
                                LaunchedEffect(card.id) {
                                    viewModel.loadMoreIfNeeded(card.id)
                                }
                                ElevatedCard(
                                    onClick = { onOpenCard(card) },
                                    shape = RoundedCornerShape(16.dp),
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

            // 回到顶部
            if (state is FeedUiState.Loaded && showScrollTop) {
                SmallFloatingActionButton(
                    onClick = { scope.launch { listState.animateScrollToItem(0) } },
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(16.dp)
                        .padding(bottom = contentPadding.calculateBottomPadding()),
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                    contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                ) {
                    Icon(Icons.Filled.KeyboardArrowUp, contentDescription = "回到顶部")
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
                style = MaterialTheme.typography.bodyLarge,
                maxLines = 6,
                overflow = TextOverflow.Ellipsis,
            )
        }

        if (card.coverURLs.isNotEmpty()) {
            FocusDynamicCardCovers(card = card)
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
private fun FocusDynamicCardCovers(card: DynamicCard) {
    if (card.coverURLs.size == 1) {
        val url = card.coverURLs.first()
        when (card.kind) {
            DynamicCard.Kind.VIDEO, DynamicCard.Kind.ARTICLE_LIKE -> {
                FocusCoverImage(
                    url = url,
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(16f / 9f),
                    contentScale = Crop,
                    showBackground = false,
                )
            }

            DynamicCard.Kind.IMAGE, DynamicCard.Kind.TEXT -> {
                FocusSingleImageCover(
                    url = url,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
        return
    }

    val rows = card.coverURLs.chunked(2)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        rows.forEach { rowUrls ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                rowUrls.forEach { url ->
                    FocusCoverImage(
                        url = url,
                        modifier = Modifier
                            .weight(1f)
                            .aspectRatio(1f),
                        contentScale = Crop,
                        showBackground = false,
                    )
                }
                repeat(2 - rowUrls.size) {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun FocusSingleImageCover(url: String, modifier: Modifier = Modifier) {
    val painter = rememberAsyncImagePainter(
        model = ImageRequest.Builder(LocalContext.current)
            .data(url)
            .crossfade(true)
            .build()
    )
    val intrinsicSize = (painter.state as? AsyncImagePainter.State.Success)
        ?.painter
        ?.intrinsicSize
    val ratio = normalizedIntrinsicRatio(intrinsicSize)
    val widthFraction = when {
        ratio >= 1.15f -> 1f
        ratio >= 0.95f -> 0.82f
        else -> 0.68f
    }

    Image(
        painter = painter,
        contentDescription = null,
        modifier = modifier
            .fillMaxWidth(widthFraction)
            .aspectRatio(ratio)
            .clip(DynamicCoverCornerRadius)
            .background(MaterialTheme.colorScheme.surfaceVariant),
        contentScale = Fit,
    )
}

@Composable
private fun FocusCoverImage(
    url: String,
    modifier: Modifier = Modifier,
    contentScale: ContentScale,
    showBackground: Boolean,
) {
    AsyncImage(
        model = ImageRequest.Builder(LocalContext.current)
            .data(url)
            .crossfade(true)
            .build(),
        contentDescription = null,
        modifier = modifier
            .clip(DynamicCoverCornerRadius)
            .then(
                if (showBackground) {
                    Modifier.background(MaterialTheme.colorScheme.surfaceVariant, DynamicCoverCornerRadius)
                } else {
                    Modifier
                }
            ),
        contentScale = contentScale,
    )
}

private fun normalizedIntrinsicRatio(size: Size?): Float {
    if (size == null || size.width <= 0f || size.height <= 0f) {
        return 4f / 3f
    }
    return (size.width / size.height).coerceIn(0.75f, 2f)
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
