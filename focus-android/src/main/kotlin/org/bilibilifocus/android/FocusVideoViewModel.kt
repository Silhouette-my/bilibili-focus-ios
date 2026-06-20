package org.bilibilifocus.android

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.bilibilifocus.core.model.VideoComment
import org.bilibilifocus.core.model.VideoInfo
import org.bilibilifocus.core.model.VideoInteractionState
import org.bilibilifocus.core.service.VideoActionService
import org.bilibilifocus.core.service.VideoInfoService

class FocusVideoViewModel(
    private val service: VideoInfoService,
    private val actionService: VideoActionService,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main + kotlinx.coroutines.CoroutineExceptionHandler { _, e ->
        _state.value = VideoUiState.Error(e.message ?: "加载失败")
    })

    private val _state = MutableStateFlow<VideoUiState>(VideoUiState.Loading)
    val state: StateFlow<VideoUiState> = _state.asStateFlow()

    private val _comments = MutableStateFlow<List<VideoComment>>(emptyList())
    val comments: StateFlow<List<VideoComment>> = _comments.asStateFlow()
    private val _interactionState = MutableStateFlow(VideoInteractionState())
    val interactionState: StateFlow<VideoInteractionState> = _interactionState.asStateFlow()
    private var loadedBvid: String? = null
    private var loadedInfo: VideoInfo? = null

    fun loadIfNeeded(bvid: String) {
        if (loadedBvid == bvid && _state.value is VideoUiState.Loaded) return
        load(bvid)
    }

    fun load(bvid: String) {
        scope.launch {
            _state.value = VideoUiState.Loading
            _comments.value = emptyList()
            _interactionState.value = VideoInteractionState()
            try {
                val info = service.fetchVideoInfo(bvid)
                loadedBvid = bvid
                loadedInfo = info
                _state.value = VideoUiState.Loaded(info)
                loadComments(info.aid)
                loadInteractions(info.aid)
            } catch (e: VideoInfoService.ServiceError) {
                _state.value = when (e) {
                    VideoInfoService.ServiceError.LoginRequired -> VideoUiState.Error("需要登录")
                    is VideoInfoService.ServiceError.Api -> VideoUiState.Error("API错误 ${e.code}: ${e.message}")
                    VideoInfoService.ServiceError.InvalidResponse -> VideoUiState.Error("接口数据异常")
                }
            } catch (e: Exception) {
                _state.value = VideoUiState.Error(e.message ?: "加载失败")
            }
        }
    }

    fun toggleLike() {
        val info = loadedInfo ?: return
        val current = _interactionState.value
        scope.launch {
            try {
                actionService.toggleLike(info.aid, !current.liked)
                _interactionState.value = current.copy(liked = !current.liked, loading = false)
                updateStats { stats ->
                    stats.copy(likes = (stats.likes + if (!current.liked) 1 else -1).coerceAtLeast(0))
                }
            } catch (_: Exception) {
            }
        }
    }

    fun coin() {
        val info = loadedInfo ?: return
        val current = _interactionState.value
        if (current.coined) return
        scope.launch {
            try {
                actionService.coin(info.aid)
                _interactionState.value = current.copy(coined = true, loading = false)
                updateStats { stats -> stats.copy(coins = stats.coins + 1) }
            } catch (_: Exception) {
            }
        }
    }

    fun toggleFavorite() {
        val info = loadedInfo ?: return
        val current = _interactionState.value
        scope.launch {
            try {
                val folderId = actionService.toggleFavorite(
                    aid = info.aid,
                    favorited = !current.favorited,
                    folderId = current.favoriteFolderId,
                )
                _interactionState.value = current.copy(
                    favorited = !current.favorited,
                    favoriteFolderId = folderId,
                    loading = false,
                )
                updateStats { stats ->
                    stats.copy(favorites = (stats.favorites + if (!current.favorited) 1 else -1).coerceAtLeast(0))
                }
            } catch (_: Exception) {
            }
        }
    }

    private fun loadComments(oid: Long) {
        scope.launch {
            try {
                val (comments, _) = service.fetchComments(oid)
                _comments.value = comments
            } catch (_: Exception) {
            }
        }
    }

    private fun loadInteractions(aid: Long) {
        scope.launch {
            _interactionState.value = _interactionState.value.copy(loading = true)
            try {
                _interactionState.value = actionService.fetchInteractionState(aid)
            } catch (_: Exception) {
                _interactionState.value = _interactionState.value.copy(loading = false)
            }
        }
    }

    private fun updateStats(transform: (org.bilibilifocus.core.model.VideoStats) -> org.bilibilifocus.core.model.VideoStats) {
        val current = _state.value as? VideoUiState.Loaded ?: return
        val updatedInfo = current.info.copy(stats = transform(current.info.stats))
        loadedInfo = updatedInfo
        _state.value = VideoUiState.Loaded(updatedInfo)
    }

    fun onCleared() {
        scope.cancel()
    }
}

sealed class VideoUiState {
    data object Loading : VideoUiState()
    data class Loaded(val info: VideoInfo) : VideoUiState()
    data class Error(val message: String) : VideoUiState()
}
