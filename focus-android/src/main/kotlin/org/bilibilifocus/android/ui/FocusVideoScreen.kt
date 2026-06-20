package org.bilibilifocus.android.ui

import android.content.res.Configuration
import android.content.pm.ActivityInfo
import android.view.View
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.res.painterResource
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.OpenInFull
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Speed
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import coil.compose.AsyncImage
import coil.request.ImageRequest
import org.bilibilifocus.android.AndroidCookieProvider
import org.bilibilifocus.android.FocusVideoViewModel
import org.bilibilifocus.android.R
import org.bilibilifocus.android.VideoUiState
import org.bilibilifocus.core.model.VideoComment
import org.bilibilifocus.core.model.VideoEpisode
import org.bilibilifocus.core.model.VideoEpisodeGroup
import org.bilibilifocus.core.model.VideoInfo
import org.bilibilifocus.core.model.VideoInteractionState
import org.bilibilifocus.core.model.VideoPage
import org.bilibilifocus.core.service.KtorHttpClient
import org.bilibilifocus.core.service.PlayUrlService
import org.bilibilifocus.core.service.VideoActionService
import org.bilibilifocus.core.service.VideoInfoService

private val SPEEDS = floatArrayOf(1f, 1.25f, 1.5f, 2f)

@OptIn(ExperimentalMaterial3Api::class, UnstableApi::class)
@Composable
fun FocusVideoScreen(
    url: String,
    onBack: () -> Unit,
    onOpenUser: (Long) -> Unit = {},
    onOpenVideo: (String) -> Unit = {},
    viewModel: FocusVideoViewModel? = null,
    scrollState: ScrollState = rememberScrollState(),
) {
    val bvid = remember(url) { VideoInfoService.extractBvid(url) }
    val initialPageNumber = remember(url) { parseRequestedPage(url) }
    val context = LocalContext.current

    val resolvedViewModel = viewModel ?: remember(url) {
        FocusVideoViewModel(
            service = VideoInfoService(
                cookieProvider = AndroidCookieProvider(),
                httpClient = KtorHttpClient(),
            ),
            actionService = VideoActionService(
                cookieProvider = AndroidCookieProvider(),
                httpClient = KtorHttpClient(),
            ),
        )
    }

    if (bvid != null) {
        LaunchedEffect(bvid) { resolvedViewModel.loadIfNeeded(bvid) }
    }

    val state by resolvedViewModel.state.collectAsState()
    val comments by resolvedViewModel.comments.collectAsState()
    val interactionState by resolvedViewModel.interactionState.collectAsState()
    val loaded = state as? VideoUiState.Loaded
    val info = loaded?.info
    val configuration = LocalConfiguration.current
    val isPhoneLayout = configuration.smallestScreenWidthDp < 600

    val exoPlayer = remember { ExoPlayer.Builder(context).build() }
    val playUrlService = remember {
        PlayUrlService(cookieProvider = AndroidCookieProvider(), httpClient = KtorHttpClient())
    }
    var playerError by remember { mutableStateOf<String?>(null) }
    var isFullscreen by remember { mutableStateOf(false) }
    var isPlaying by remember { mutableStateOf(false) }
    var playbackSpeed by remember { mutableStateOf(1f) }
    var selectedPageCid by remember(url) { mutableStateOf<Long?>(null) }
    var videoAspectRatio by remember { mutableStateOf(16f / 9f) }

    LaunchedEffect(info, initialPageNumber) {
        val resolvedInfo = info ?: return@LaunchedEffect
        if (selectedPageCid != null && resolvedInfo.pages.any { it.cid == selectedPageCid }) return@LaunchedEffect
        selectedPageCid = resolvedInfo.pages
            .firstOrNull { it.pageNumber == initialPageNumber }
            ?.cid
            ?: resolvedInfo.pages.firstOrNull()?.cid
            ?: resolvedInfo.cid
    }

    val activePage = resolveActivePage(info, selectedPageCid)

    LaunchedEffect(configuration.orientation, isPhoneLayout, state is VideoUiState.Loaded) {
        if (!isPhoneLayout) return@LaunchedEffect

        when (configuration.orientation) {
            Configuration.ORIENTATION_LANDSCAPE -> {
                if (!isFullscreen && state is VideoUiState.Loaded) {
                    isFullscreen = true
                }
            }
            Configuration.ORIENTATION_PORTRAIT -> {
                if (isFullscreen) {
                    isFullscreen = false
                }
            }
        }
    }

    LaunchedEffect(info?.bvid, activePage?.cid) {
        val resolvedInfo = info ?: return@LaunchedEffect
        val resolvedPage = activePage ?: return@LaunchedEffect
        playerError = null
        try {
            val result = playUrlService.fetchPlayUrl(resolvedInfo.bvid, resolvedPage.cid)
            val headers = buildMap {
                put("Referer", result.referer)
                if (result.cookie.isNotEmpty()) put("Cookie", result.cookie)
            }
            val httpFactory = DefaultHttpDataSource.Factory()
                .setUserAgent(result.userAgent)
                .setAllowCrossProtocolRedirects(true)
                .setDefaultRequestProperties(headers)
            val videoSource = ProgressiveMediaSource.Factory(httpFactory)
                .createMediaSource(MediaItem.fromUri(result.videoUrl))
            val source = result.audioUrl?.let { audioUrl ->
                val audioSource = ProgressiveMediaSource.Factory(httpFactory)
                    .createMediaSource(MediaItem.fromUri(audioUrl))
                MergingMediaSource(videoSource, audioSource)
            } ?: videoSource
            exoPlayer.setMediaSource(source)
            exoPlayer.prepare()
            exoPlayer.playWhenReady = true
            exoPlayer.playbackParameters = PlaybackParameters(playbackSpeed)
        } catch (e: Exception) {
            playerError = e.message ?: "视频加载失败"
        }
    }

    DisposableEffect(exoPlayer) {
        val listener = object : Player.Listener {
            override fun onIsPlayingChanged(playing: Boolean) {
                isPlaying = playing
            }

            override fun onPlaybackParametersChanged(playbackParameters: PlaybackParameters) {
                playbackSpeed = playbackParameters.speed
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                val width = videoSize.width
                val height = videoSize.height
                if (width > 0 && height > 0) {
                    val ratio = (width * videoSize.pixelWidthHeightRatio) / height.toFloat()
                    if (ratio.isFinite() && ratio > 0f) {
                        videoAspectRatio = ratio
                    }
                }
            }
        }
        exoPlayer.addListener(listener)
        onDispose {
            exoPlayer.removeListener(listener)
            exoPlayer.release()
        }
    }

    BackHandler(enabled = isFullscreen) { isFullscreen = false }
    DisposableEffect(isFullscreen, isPhoneLayout) {
        val activity = context.findActivity()
        if (isFullscreen) {
            activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            setSystemBarsHidden(activity, true)
        } else {
            activity?.requestedOrientation = if (isPhoneLayout) {
                ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            } else {
                ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            }
            setSystemBarsHidden(activity, false)
        }
        onDispose { }
    }
    DisposableEffect(Unit) {
        onDispose {
            val activity = context.findActivity()
            activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            setSystemBarsHidden(activity, false)
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Scaffold(
            topBar = {
                CenterAlignedTopAppBar(
                    title = {
                        Text(
                            info?.title ?: "视频",
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            style = MaterialTheme.typography.titleMedium,
                        )
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
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("无法识别视频链接", style = MaterialTheme.typography.bodyMedium)
                        Text(url, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            } else when (val currentState = state) {
                VideoUiState.Loading -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(innerPadding),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                    }
                }

                is VideoUiState.Error -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(innerPadding),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(currentState.message, style = MaterialTheme.typography.bodyMedium)
                    }
                }

                is VideoUiState.Loaded -> {
                    BoxWithConstraints(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(innerPadding),
                    ) {
                        val resolvedAspectRatio = when {
                            videoAspectRatio.isFinite() && videoAspectRatio > 0f -> videoAspectRatio
                            else -> 16f / 9f
                        }
                        val portraitCandidate = resolvedAspectRatio < 1f
                        val playerHeight = when {
                            portraitCandidate -> {
                                minOf(maxWidth / resolvedAspectRatio, maxHeight * 0.74f)
                            }
                            else -> {
                                minOf(maxWidth / resolvedAspectRatio, maxHeight * if (isPhoneLayout) 0.46f else 0.58f)
                            }
                        }
                        Column(
                            modifier = Modifier
                                .fillMaxSize()
                                .verticalScroll(scrollState),
                        ) {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(playerHeight)
                                    .background(Color.Black),
                                contentAlignment = Alignment.Center,
                            ) {
                                if (!isFullscreen) {
                                    PlayerSurface(
                                        player = exoPlayer,
                                        showController = false,
                                        onToggleFullscreen = { isFullscreen = true },
                                        modifier = Modifier.fillMaxSize(),
                                    )
                                }
                                playerError?.let { message ->
                                    if (!isFullscreen) {
                                        Text(message, color = Color.White, style = MaterialTheme.typography.bodySmall)
                                    }
                                }
                            }

                            Column(
                                modifier = Modifier.padding(horizontal = 16.dp),
                                verticalArrangement = Arrangement.spacedBy(16.dp),
                            ) {
                                Spacer(modifier = Modifier.height(14.dp))
                                Text(text = currentState.info.title, style = MaterialTheme.typography.titleMedium)

                                if (currentState.info.tags.isNotEmpty()) {
                                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        items(currentState.info.tags, key = { it }) { tag ->
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

                                VideoActionBar(
                                    interactionState = interactionState,
                                    info = currentState.info,
                                    onToggleLike = { resolvedViewModel.toggleLike() },
                                    onCoin = { resolvedViewModel.coin() },
                                    onToggleFavorite = { resolvedViewModel.toggleFavorite() },
                                )

                                if (currentState.info.pages.size > 1) {
                                    VideoPageSection(
                                        pages = currentState.info.pages,
                                        selectedCid = activePage?.cid,
                                        onSelect = { page -> selectedPageCid = page.cid },
                                    )
                                }

                                if (currentState.info.episodeGroups.isNotEmpty()) {
                                    VideoEpisodeSections(
                                        groups = currentState.info.episodeGroups,
                                        currentBvid = currentState.info.bvid,
                                        onOpenVideo = onOpenVideo,
                                    )
                                }

                                if (currentState.info.description.isNotBlank()) {
                                    ExpandableDescription(currentState.info.description)
                                }

                                if (comments.isNotEmpty()) {
                                    Text(
                                        "评论 (${comments.size})",
                                        style = MaterialTheme.typography.titleMedium,
                                    )
                                    comments.forEach { comment ->
                                        CommentItem(comment)
                                    }
                                }
                            }

                            Spacer(modifier = Modifier.height(104.dp))
                        }
                    }
                }
            }
        }

        if (!isFullscreen && state is VideoUiState.Loaded) {
            VideoControlDock(
                isPlaying = isPlaying,
                playbackSpeed = playbackSpeed,
                onTogglePlay = {
                    if (exoPlayer.isPlaying) exoPlayer.pause() else exoPlayer.play()
                },
                onChangeSpeed = {
                    val next = nextSpeed(playbackSpeed)
                    exoPlayer.playbackParameters = PlaybackParameters(next)
                },
                onToggleFullscreen = { isFullscreen = true },
                modifier = Modifier.align(Alignment.BottomCenter),
            )
        }

        if (isFullscreen) {
            Dialog(
                onDismissRequest = { isFullscreen = false },
                properties = DialogProperties(
                    usePlatformDefaultWidth = false,
                    dismissOnBackPress = true,
                    dismissOnClickOutside = false,
                    decorFitsSystemWindows = false,
                ),
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black),
                ) {
                    PlayerSurface(
                        player = exoPlayer,
                        showController = true,
                        onToggleFullscreen = { isFullscreen = false },
                        modifier = Modifier.fillMaxSize(),
                    )
                }
            }
        }
    }
}

@Composable
private fun VideoControlDock(
    isPlaying: Boolean,
    playbackSpeed: Float,
    onTogglePlay: () -> Unit,
    onChangeSpeed: () -> Unit,
    onToggleFullscreen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isDarkTheme = isSystemInDarkTheme()
    Box(
        modifier = modifier
            .fillMaxWidth()
            .background(
                brush = Brush.verticalGradient(
                    colors = if (isDarkTheme) {
                        listOf(
                            Color.Transparent,
                            Color.Black.copy(alpha = 0.10f),
                            Color.Black.copy(alpha = 0.22f),
                            Color.Black.copy(alpha = 0.34f),
                        )
                    } else {
                        listOf(
                            Color.Transparent,
                            Color.White.copy(alpha = 0.08f),
                            Color.White.copy(alpha = 0.20f),
                            Color.White.copy(alpha = 0.34f),
                        )
                    },
                ),
            )
            .navigationBarsPadding()
            .padding(start = 16.dp, end = 16.dp, top = 2.dp, bottom = 2.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(24.dp))
                .background(
                    if (isDarkTheme) {
                        Color(0xC8262C36)
                    } else {
                        Color.White.copy(alpha = 0.72f)
                    }
                )
                .border(
                    width = 1.dp,
                    color = if (isDarkTheme) {
                        Color.White.copy(alpha = 0.10f)
                    } else {
                        Color(0x241A1D24)
                    },
                    shape = RoundedCornerShape(24.dp),
                )
                .padding(horizontal = 10.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            DockButton(
                icon = if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                text = if (isPlaying) "暂停" else "播放",
                onClick = onTogglePlay,
                modifier = Modifier.weight(1f),
            )
            DockButton(
                icon = Icons.Outlined.Speed,
                text = "${trimSpeed(playbackSpeed)}x",
                onClick = onChangeSpeed,
                modifier = Modifier.weight(1f),
            )
            DockButton(
                icon = Icons.Filled.OpenInFull,
                text = "全屏",
                onClick = onToggleFullscreen,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun VideoActionBar(
    interactionState: VideoInteractionState,
    info: VideoInfo,
    onToggleLike: () -> Unit,
    onCoin: () -> Unit,
    onToggleFavorite: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = if (isSystemInDarkTheme()) 0.72f else 0.86f))
            .padding(horizontal = 6.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ActionMetricButton(
            painter = painterResource(R.drawable.ic_bili_like),
            value = formatCount(info.stats.likes),
            active = interactionState.liked,
            onClick = onToggleLike,
            enabled = !interactionState.loading,
            modifier = Modifier.weight(1f),
        )
        VerticalDivider()
        ActionMetricButton(
            painter = painterResource(R.drawable.ic_bili_coin),
            value = formatCount(info.stats.coins),
            active = interactionState.coined,
            onClick = onCoin,
            enabled = !interactionState.loading && !interactionState.coined,
            modifier = Modifier.weight(1f),
        )
        VerticalDivider()
        ActionMetricButton(
            painter = painterResource(R.drawable.ic_bili_fav),
            value = formatCount(info.stats.favorites),
            active = interactionState.favorited,
            onClick = onToggleFavorite,
            enabled = !interactionState.loading,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun DockButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    TextButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .background(Color.White.copy(alpha = if (isSystemInDarkTheme()) 0.94f else 0.90f)),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 10.dp),
        colors = ButtonDefaults.textButtonColors(
            contentColor = Color(0xFF2E3138),
            disabledContentColor = Color(0xFF8E95A1),
        ),
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp))
            Text(
                text,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

@Composable
private fun ActionMetricButton(
    painter: Painter,
    value: String,
    active: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    TextButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier,
        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 8.dp),
        colors = ButtonDefaults.textButtonColors(
            contentColor = if (active) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            disabledContentColor = MaterialTheme.colorScheme.outline,
        ),
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                painter = painter,
                contentDescription = null,
                modifier = Modifier.size(22.dp),
            )
            Text(
                value,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

@Composable
private fun VerticalDivider() {
    Box(
        modifier = Modifier
            .width(1.dp)
            .height(20.dp)
            .background(MaterialTheme.colorScheme.outlineVariant),
    )
}

@Composable
private fun VideoPageSection(
    pages: List<VideoPage>,
    selectedCid: Long?,
    onSelect: (VideoPage) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("分 P", style = MaterialTheme.typography.titleMedium)
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(pages, key = { it.cid }) { page ->
                FilterChip(
                    selected = page.cid == selectedCid,
                    onClick = { onSelect(page) },
                    label = {
                        val label = buildString {
                            append("P${page.pageNumber}")
                            if (page.title.isNotBlank()) append(" ${page.title}")
                        }
                        Text(
                            label,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            textAlign = TextAlign.Center,
                        )
                    },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                        selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer,
                    ),
                )
            }
        }
    }
}

@Composable
private fun VideoEpisodeSections(
    groups: List<VideoEpisodeGroup>,
    currentBvid: String,
    onOpenVideo: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        groups.forEach { group ->
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(group.title, style = MaterialTheme.typography.titleMedium)
                LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    items(group.episodes, key = { "${group.title}-${it.bvid}-${it.cid}" }) { episode ->
                        EpisodeCard(
                            episode = episode,
                            selected = episode.bvid == currentBvid,
                            onClick = {
                                if (episode.bvid != currentBvid) {
                                    onOpenVideo("https://www.bilibili.com/video/${episode.bvid}")
                                }
                            },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun EpisodeCard(
    episode: VideoEpisode,
    selected: Boolean,
    onClick: () -> Unit,
) {
    ElevatedCard(
        onClick = onClick,
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.elevatedCardColors(
            containerColor = if (selected) {
                MaterialTheme.colorScheme.primaryContainer
            } else {
                MaterialTheme.colorScheme.surface
            }
        ),
        elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
        modifier = Modifier.size(width = 156.dp, height = 88.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(12.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                episode.title,
                style = MaterialTheme.typography.labelLarge,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
            )
            if (episode.badgeText.isNotBlank()) {
                Text(
                    episode.badgeText,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

@OptIn(UnstableApi::class)
@Composable
private fun PlayerSurface(
    player: ExoPlayer,
    showController: Boolean,
    onToggleFullscreen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    AndroidView(
        factory = { ctx ->
            PlayerView(ctx).apply {
                useController = showController
                resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                setShowNextButton(false)
                setShowPreviousButton(false)
                setBackgroundColor(android.graphics.Color.BLACK)
                setFullscreenButtonClickListener { onToggleFullscreen() }
            }
        },
        update = { view ->
            view.useController = showController
            view.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            view.player = player
            view.setFullscreenButtonClickListener { onToggleFullscreen() }
        },
        modifier = modifier,
    )
}

private fun android.content.Context.findActivity(): android.app.Activity? {
    var ctx: android.content.Context? = this
    while (ctx is android.content.ContextWrapper) {
        if (ctx is android.app.Activity) return ctx
        ctx = ctx.baseContext
    }
    return null
}

private fun setSystemBarsHidden(activity: android.app.Activity?, hidden: Boolean) {
    val window = activity?.window ?: return
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
        val controller = window.insetsController
        val bars = android.view.WindowInsets.Type.statusBars() or android.view.WindowInsets.Type.navigationBars()
        if (hidden) {
            controller?.hide(bars)
            controller?.systemBarsBehavior = android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        } else {
            controller?.show(bars)
        }
    } else {
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = if (hidden) {
            View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
        } else {
            View.SYSTEM_UI_FLAG_VISIBLE
        }
    }
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
    val contentStyle = MaterialTheme.typography.bodyMedium.let {
        it.copy(fontSize = it.fontSize * 1.15f)
    }
    val replyStyle = MaterialTheme.typography.bodySmall.let {
        it.copy(fontSize = it.fontSize * 1.15f)
    }
    val authorStyle = MaterialTheme.typography.labelMedium.let {
        it.copy(fontSize = it.fontSize * 1.15f)
    }
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
            Text(comment.authorName, style = authorStyle, color = MaterialTheme.colorScheme.primary)
            Spacer(modifier = Modifier.weight(1f))
            Text(
                formatTimeAgo(comment.publishTime),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text("${comment.likeCount}赞", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(comment.content, style = contentStyle)

        comment.replies.take(3).forEach { reply ->
            Row(modifier = Modifier.padding(start = 36.dp, top = 4.dp)) {
                Text(
                    "${reply.authorName}: ${reply.content}",
                    style = replyStyle,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

private fun resolveActivePage(info: VideoInfo?, selectedCid: Long?): VideoPage? {
    if (info == null) return null
    return info.pages.firstOrNull { it.cid == selectedCid }
        ?: info.pages.firstOrNull()
        ?: VideoPage(
            pageNumber = 1,
            cid = info.cid,
            title = "正片",
            duration = info.duration,
        )
}

private fun parseRequestedPage(url: String): Int? {
    return Regex("""[?&]p=(\d+)""").find(url)?.groupValues?.getOrNull(1)?.toIntOrNull()
}

private fun nextSpeed(current: Float): Float {
    val currentIndex = SPEEDS.indexOfFirst { kotlin.math.abs(it - current) < 0.01f }
    return if (currentIndex == -1 || currentIndex == SPEEDS.lastIndex) SPEEDS.first() else SPEEDS[currentIndex + 1]
}

private fun trimSpeed(speed: Float): String {
    return if (speed % 1f == 0f) speed.toInt().toString() else speed.toString()
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
        diff < 2592000 -> "${diff / 86400}天前"
        else -> java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault())
            .format(java.util.Date(ts * 1000))
    }
}
