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
import org.bilibilifocus.core.service.VideoInfoService

class FocusVideoViewModel(
    private val service: VideoInfoService,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main + kotlinx.coroutines.CoroutineExceptionHandler { _, e ->
        _state.value = VideoUiState.Error(e.message ?: "加载失败")
    })

    private val _state = MutableStateFlow<VideoUiState>(VideoUiState.Loading)
    val state: StateFlow<VideoUiState> = _state.asStateFlow()

    private val _comments = MutableStateFlow<List<VideoComment>>(emptyList())
    val comments: StateFlow<List<VideoComment>> = _comments.asStateFlow()

    fun load(bvid: String) {
        scope.launch {
            _state.value = VideoUiState.Loading
            _comments.value = emptyList()
            try {
                val info = service.fetchVideoInfo(bvid)
                _state.value = VideoUiState.Loaded(info)
                loadComments(info.aid)
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

    private fun loadComments(oid: Long) {
        scope.launch {
            try {
                val (comments, _) = service.fetchComments(oid)
                _comments.value = comments
            } catch (_: Exception) {
            }
        }
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
