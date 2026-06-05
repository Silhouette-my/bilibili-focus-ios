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
import org.bilibilifocus.core.model.RankCategory
import org.bilibilifocus.core.model.RankVideo
import org.bilibilifocus.core.service.RankService

class FocusRankViewModel(
    private val service: RankService,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main + kotlinx.coroutines.CoroutineExceptionHandler { _, e ->
        _state.value = RankUiState.Failed(e.message ?: "加载失败")
    })
    private var loadJob: Job? = null

    private val _state = MutableStateFlow<RankUiState>(RankUiState.Idle)
    val state: StateFlow<RankUiState> = _state.asStateFlow()

    private val _selectedCategory = MutableStateFlow(service.categories.first())
    val selectedCategory: StateFlow<RankCategory> = _selectedCategory.asStateFlow()

    val categories: List<RankCategory> = service.categories

    fun loadIfNeeded() {
        if (_state.value !is RankUiState.Idle) return
        load(service.categories.first())
    }

    fun selectCategory(category: RankCategory) {
        if (category == _selectedCategory.value) return
        _selectedCategory.value = category
        load(category)
    }

    fun refresh() {
        load(_selectedCategory.value)
    }

    private fun load(category: RankCategory) {
        loadJob?.cancel()
        loadJob = scope.launch {
            _state.value = RankUiState.Loading
            try {
                val videos = service.fetchRank(category.rid, category.type)
                _state.value = if (videos.isEmpty()) {
                    RankUiState.Empty
                } else {
                    RankUiState.Loaded(videos)
                }
            } catch (e: RankService.ServiceError) {
                when (e) {
                    is RankService.ServiceError.Api ->
                        _state.value = RankUiState.Failed("API错误 ${e.code}: ${e.message}")
                    RankService.ServiceError.InvalidResponse ->
                        _state.value = RankUiState.Failed("接口数据异常")
                }
            } catch (e: Exception) {
                _state.value = RankUiState.Failed(e.message ?: "加载失败")
            }
        }
    }

    fun onCleared() {
        scope.cancel()
    }
}

sealed class RankUiState {
    data object Idle : RankUiState()
    data object Loading : RankUiState()
    data object Empty : RankUiState()
    data class Failed(val message: String) : RankUiState()
    data class Loaded(val videos: List<RankVideo>) : RankUiState()
}
