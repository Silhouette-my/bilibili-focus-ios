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
import org.bilibilifocus.core.model.HistoryItem
import org.bilibilifocus.core.service.HistoryService

class FocusHistoryViewModel(
    private val service: HistoryService,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main + kotlinx.coroutines.CoroutineExceptionHandler { _, e ->
        _state.value = HistoryUiState.Failed(e.message ?: "加载失败")
    })
    private var loadJob: Job? = null
    private var loadMoreJob: Job? = null

    private var nextMax: Long = 0L
    private var nextViewAt: Long = 0L
    private var nextBusiness: String = ""
    private var hasMore: Boolean = true

    private val _state = MutableStateFlow<HistoryUiState>(HistoryUiState.Idle)
    val state: StateFlow<HistoryUiState> = _state.asStateFlow()

    private val _isLoadingMore = MutableStateFlow(false)
    val isLoadingMore: StateFlow<Boolean> = _isLoadingMore.asStateFlow()

    fun loadIfNeeded() {
        if (_state.value is HistoryUiState.Loaded) return
        reload()
    }

    fun reload() {
        loadJob?.cancel()
        loadJob = scope.launch {
            _state.value = HistoryUiState.Loading
            hasMore = true
            nextMax = 0L
            nextViewAt = 0L
            nextBusiness = ""
            try {
                val page = service.fetchHistory()
                val items = page.items.filter { it.bvid.isNotEmpty() }
                nextMax = page.nextMax
                nextViewAt = page.nextViewAt
                nextBusiness = page.nextBusiness
                hasMore = page.items.isNotEmpty() && (page.nextMax > 0 || page.nextViewAt > 0 || page.nextBusiness.isNotEmpty())
                _state.value = HistoryUiState.Loaded(items, hasMore)
            } catch (e: Exception) {
                _state.value = HistoryUiState.Failed(e.message ?: "加载失败")
            }
        }
    }

    fun loadMoreIfNeeded(anchorKey: String) {
        val current = _state.value as? HistoryUiState.Loaded ?: return
        if (!current.hasMore) return
        if (_isLoadingMore.value) return

        val anchorIndex = current.items.indexOfLast { it.stableKey == anchorKey }
        if (anchorIndex < 0 || anchorIndex < current.items.size - 6) return

        _isLoadingMore.value = true
        loadMoreJob?.cancel()
        loadMoreJob = scope.launch {
            try {
                val page = service.fetchHistory(
                    max = nextMax,
                    viewAt = nextViewAt,
                    business = nextBusiness,
                )
                nextMax = page.nextMax
                nextViewAt = page.nextViewAt
                nextBusiness = page.nextBusiness
                hasMore = page.items.isNotEmpty() && (page.nextMax > 0 || page.nextViewAt > 0 || page.nextBusiness.isNotEmpty())
                val merged = (current.items + page.items.filter { it.bvid.isNotEmpty() })
                    .distinctBy { it.stableKey }
                _state.value = HistoryUiState.Loaded(merged, hasMore)
            } catch (_: Exception) {
                // 保持当前列表，等待下一次滚动触发或手工重试。
            } finally {
                _isLoadingMore.value = false
            }
        }
    }

    fun onCleared() {
        scope.cancel()
    }
}

sealed class HistoryUiState {
    data object Idle : HistoryUiState()
    data object Loading : HistoryUiState()
    data class Failed(val message: String) : HistoryUiState()
    data class Loaded(
        val items: List<HistoryItem>,
        val hasMore: Boolean,
    ) : HistoryUiState()
}

val HistoryItem.stableKey: String
    get() = "$bvid-$viewAt"
