package org.bilibilifocus.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class FocusEntry {
    @SerialName("dynamic") DYNAMIC,
    @SerialName("search") SEARCH;

    val title: String
        get() = when (this) {
            DYNAMIC -> "动态"
            SEARCH -> "搜索"
        }
}
