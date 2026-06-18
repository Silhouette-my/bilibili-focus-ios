package org.bilibilifocus.core.model

import kotlinx.serialization.Serializable

@Serializable
data class FocusSettings(
    val redirectEnabled: Boolean = true,
    val playerMaskEnabled: Boolean = true,
    val searchMaskEnabled: Boolean = true,
    val dynamicMaskEnabled: Boolean = true,
    val debugMode: Boolean = false,
    val defaultEntry: FocusEntry = FocusEntry.DYNAMIC,
) {
    companion object {
        const val STORAGE_KEY = "focus.settings"
        val DEFAULTS = FocusSettings()
    }
}
