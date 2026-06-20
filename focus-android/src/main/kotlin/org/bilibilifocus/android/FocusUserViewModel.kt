package org.bilibilifocus.android

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.bilibilifocus.core.model.UserProfile
import org.bilibilifocus.core.model.UserVideo
import org.bilibilifocus.core.service.UserService

class FocusUserViewModel(
    private val service: UserService,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main + kotlinx.coroutines.CoroutineExceptionHandler { _, e ->
        _state.value = UserUiState.Failed(e.message ?: "加载失败")
    })
    private var loadJob: Job? = null

    private val _state = MutableStateFlow<UserUiState>(UserUiState.Idle)
    val state: StateFlow<UserUiState> = _state.asStateFlow()
    private var loadedMid: Long? = null

    fun loadIfNeeded(mid: Long) {
        if (loadedMid == mid && _state.value is UserUiState.Loaded) return
        load(mid)
    }

    fun load(mid: Long) {
        loadJob?.cancel()
        loadJob = scope.launch {
            _state.value = UserUiState.Loading
            try {
                val info = service.fetchUserInfo(mid)
                val relation = service.fetchRelationInfo(mid)
                val videos = service.fetchUserVideos(mid)

                val profile = info.copy(following = relation.first, followers = relation.second)
                loadedMid = mid
                _state.value = UserUiState.Loaded(profile, videos)
            } catch (e: UserService.ServiceError) {
                when (e) {
                    UserService.ServiceError.SigningUnavailable ->
                        _state.value = UserUiState.Failed("签名初始化失败，请重试")
                    is UserService.ServiceError.Api ->
                        _state.value = UserUiState.Failed("API错误 ${e.code}: ${e.message}")
                    UserService.ServiceError.InvalidResponse ->
                        _state.value = UserUiState.Failed("接口数据异常")
                }
            } catch (e: Exception) {
                _state.value = UserUiState.Failed(e.message ?: "加载失败")
            }
        }
    }

    fun onCleared() {
        scope.cancel()
    }
}

sealed class UserUiState {
    data object Idle : UserUiState()
    data object Loading : UserUiState()
    data class Failed(val message: String) : UserUiState()
    data class Loaded(val profile: UserProfile, val videos: List<UserVideo>) : UserUiState()
}
