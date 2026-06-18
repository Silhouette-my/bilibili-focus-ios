package org.bilibilifocus.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class FocusFeature(
    val featureId: String,
    val requiredSelectors: List<String> = emptyList(),
    val optionalSelectors: List<String> = emptyList(),
    val action: Action,
    val css: String,
    val script: String? = null,
    val settingKey: SettingKey? = null,
) {
    @Serializable
    enum class Action {
        @SerialName("prune") PRUNE,
        @SerialName("repair") REPAIR,
    }

    @Serializable
    enum class SettingKey {
        @SerialName("redirectEnabled") REDIRECT_ENABLED,
        @SerialName("playerMaskEnabled") PLAYER_MASK_ENABLED,
        @SerialName("searchMaskEnabled") SEARCH_MASK_ENABLED,
        @SerialName("dynamicMaskEnabled") DYNAMIC_MASK_ENABLED,
        @SerialName("debugMode") DEBUG_MODE,
    }
}
