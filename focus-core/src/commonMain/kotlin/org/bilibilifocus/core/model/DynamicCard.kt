package org.bilibilifocus.core.model

import kotlinx.serialization.Serializable

@Serializable
data class DynamicCard(
    val id: String,
    val kind: Kind,
    val author: Author,
    val publishTime: String,
    val text: String,
    val coverURLs: List<String>,
    val targetURL: String,
    val videoURL: String? = null,
) {
    @Serializable
    enum class Kind {
        TEXT,
        IMAGE,
        VIDEO,
        ARTICLE_LIKE,
    }

    @Serializable
    data class Author(
        val name: String,
        val mid: Long = 0,
        val avatarURL: String? = null,
    )
}
