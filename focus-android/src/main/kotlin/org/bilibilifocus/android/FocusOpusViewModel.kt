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
import org.bilibilifocus.core.model.OpusDetail
import org.bilibilifocus.core.service.OpusService

class FocusOpusViewModel(
    private val service: OpusService,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main + kotlinx.coroutines.CoroutineExceptionHandler { _, e ->
        _state.value = OpusUiState.Failed(e.message ?: "加载失败")
    })
    private var loadJob: Job? = null

    private val _state = MutableStateFlow<OpusUiState>(OpusUiState.Idle)
    val state: StateFlow<OpusUiState> = _state.asStateFlow()

    fun load(id: String) {
        loadJob?.cancel()
        loadJob = scope.launch {
            _state.value = OpusUiState.Loading
            try {
                val detail = service.fetchOpusDetail(id)
                _state.value = OpusUiState.Loaded(detail)
            } catch (e: OpusService.ServiceError) {
                if (e == OpusService.ServiceError.LoginRequired) {
                    _state.value = OpusUiState.LoginRequired
                } else {
                    _state.value = OpusUiState.Failed(e.message ?: "加载失败")
                }
            } catch (e: Exception) {
                _state.value = OpusUiState.Failed(e.message ?: "加载失败")
            }
        }
    }

    fun onCleared() {
        scope.cancel()
    }
}

sealed class OpusUiState {
    data object Idle : OpusUiState()
    data object Loading : OpusUiState()
    data object LoginRequired : OpusUiState()
    data class Failed(val message: String) : OpusUiState()
    data class Loaded(val detail: OpusDetail) : OpusUiState()
}
