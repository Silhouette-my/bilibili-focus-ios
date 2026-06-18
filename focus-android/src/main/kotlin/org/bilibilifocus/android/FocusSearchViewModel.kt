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
import org.bilibilifocus.core.model.SearchQuery
import org.bilibilifocus.core.model.SearchResultFilter
import org.bilibilifocus.core.model.SearchResultItem
import org.bilibilifocus.core.model.SearchResultSection
import org.bilibilifocus.core.model.SearchVideoSortOption
import org.bilibilifocus.core.service.SearchResultService

class FocusSearchViewModel(
    private val service: SearchResultService,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main + kotlinx.coroutines.CoroutineExceptionHandler { _, e ->
        _state.value = SearchUiState.Failed(e.message ?: "搜索失败")
    })
    private var searchJob: Job? = null
    private var loadMoreJob: Job? = null

    private var currentQuery: SearchQuery? = null
    private var currentPage: Int = 1
    private var hasMorePages: Boolean = false
    var selectedFilter: SearchResultFilter = SearchResultFilter.ALL
        private set
    var selectedVideoSort: SearchVideoSortOption = SearchVideoSortOption.DEFAULT
        private set

    private val _state = MutableStateFlow<SearchUiState>(SearchUiState.Idle)
    val state: StateFlow<SearchUiState> = _state.asStateFlow()

    private val _isLoadingMore = MutableStateFlow(false)
    val isLoadingMore: StateFlow<Boolean> = _isLoadingMore.asStateFlow()

    fun search(keyword: String) {
        val trimmed = keyword.trim()
        if (trimmed.isEmpty()) return

        val query = SearchQuery(trimmed)
        currentQuery = query
        currentPage = 1
        selectedFilter = SearchResultFilter.ALL
        selectedVideoSort = SearchVideoSortOption.DEFAULT

        searchJob?.cancel()
        searchJob = scope.launch {
            _state.value = SearchUiState.Loading
            try {
                val page = service.fetchPage(query)
                val sections = page.sections
                hasMorePages = page.nextPage != null
                _state.value = if (sections.isEmpty()) {
                    SearchUiState.Empty
                } else {
                    SearchUiState.Loaded(sections)
                }
            } catch (e: SearchResultService.ServiceError) {
                if (e == SearchResultService.ServiceError.SigningUnavailable) {
                    _state.value = SearchUiState.LoginRequired
                } else {
                    _state.value = SearchUiState.Failed(e.message ?: "搜索失败")
                }
            } catch (e: Exception) {
                _state.value = SearchUiState.Failed(e.message ?: "搜索失败")
            }
        }
    }

    fun selectFilter(filter: SearchResultFilter) {
        if (filter == selectedFilter) return
        selectedFilter = filter
        currentPage = 1

        val query = currentQuery ?: return
        searchJob?.cancel()
        searchJob = scope.launch {
            _state.value = SearchUiState.Loading
            try {
                val page = service.fetchPage(query, filter, 1, selectedVideoSort)
                hasMorePages = page.nextPage != null
                val sections = page.sections
                _state.value = if (sections.isEmpty()) {
                    SearchUiState.Empty
                } else {
                    SearchUiState.Loaded(sections)
                }
            } catch (e: SearchResultService.ServiceError) {
                if (e == SearchResultService.ServiceError.SigningUnavailable) {
                    _state.value = SearchUiState.LoginRequired
                } else {
                    _state.value = SearchUiState.Failed(e.message ?: "搜索失败")
                }
            } catch (e: Exception) {
                _state.value = SearchUiState.Failed(e.message ?: "搜索失败")
            }
        }
    }

    fun selectVideoSort(sort: SearchVideoSortOption) {
        if (sort == selectedVideoSort) return
        selectedVideoSort = sort

        val query = currentQuery ?: return
        searchJob?.cancel()
        searchJob = scope.launch {
            _state.value = SearchUiState.Loading
            try {
                val page = service.fetchPage(query, selectedFilter, 1, selectedVideoSort)
                hasMorePages = page.nextPage != null
                val sections = page.sections
                _state.value = if (sections.isEmpty()) {
                    SearchUiState.Empty
                } else {
                    SearchUiState.Loaded(sections)
                }
            } catch (e: SearchResultService.ServiceError) {
                if (e == SearchResultService.ServiceError.SigningUnavailable) {
                    _state.value = SearchUiState.LoginRequired
                } else {
                    _state.value = SearchUiState.Failed(e.message ?: "搜索失败")
                }
            } catch (e: Exception) {
                _state.value = SearchUiState.Failed(e.message ?: "搜索失败")
            }
        }
    }

    fun loadMoreIfNeeded(currentItemID: String) {
        val sections = (_state.value as? SearchUiState.Loaded)?.sections ?: return
        if (!hasMorePages) return
        if (_isLoadingMore.value) return

        val videoSection = sections.find { it.filter == SearchResultFilter.VIDEO } ?: return
        val index = videoSection.items.indexOfLast { it.id == currentItemID }
        if (index < 0 || index < videoSection.items.size - 4) return

        currentPage++
        val query = currentQuery ?: return
        val filter = selectedFilter
        val page = currentPage
        val sort = selectedVideoSort

        _isLoadingMore.value = true
        loadMoreJob?.cancel()
        loadMoreJob = scope.launch {
            try {
                val newPage = service.fetchPage(query, filter, page, sort)
                hasMorePages = newPage.nextPage != null
                val mergedVideoItems = videoSection.items + newPage.sections
                    .flatMap { it.items }
                    .filter { it.kind == SearchResultItem.Kind.VIDEO }
                    .distinctBy { it.id }
                val mergedSection = SearchResultSection(
                    filter = SearchResultFilter.VIDEO,
                    items = mergedVideoItems,
                )
                val mergedSections = sections.map {
                    if (it.filter == SearchResultFilter.VIDEO) mergedSection else it
                }
                _state.value = SearchUiState.Loaded(mergedSections)
            } catch (_: Exception) {
                currentPage--
            } finally {
                _isLoadingMore.value = false
            }
        }
    }

    fun onCleared() {
        scope.cancel()
    }
}

sealed class SearchUiState {
    data object Idle : SearchUiState()
    data object Loading : SearchUiState()
    data object Empty : SearchUiState()
    data object LoginRequired : SearchUiState()
    data class Failed(val message: String) : SearchUiState()
    data class Loaded(val sections: List<SearchResultSection>) : SearchUiState()
}
