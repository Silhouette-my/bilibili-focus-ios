package org.bilibilifocus.core.model

import kotlinx.serialization.Serializable

@Serializable
data class ArticleDetail(
    val cvid: Long,
    val title: String,
    val author: ArticleAuthor,
    val publishTime: Long,
    val stats: ArticleStats,
    val bannerUrl: String,
    val content: List<ArticleNode>,
    val tags: List<String>,
)

@Serializable
data class ArticleAuthor(
    val mid: Long,
    val name: String,
    val avatarURL: String,
)

@Serializable
data class ArticleStats(
    val views: Long,
    val likes: Long,
    val coins: Long,
    val favorites: Long,
    val comments: Long,
)

@Serializable
sealed class ArticleNode {
    @Serializable
    data class Paragraph(val text: String, val style: TextStyle = TextStyle.NORMAL) : ArticleNode()

    @Serializable
    data class Heading(val text: String, val level: Int) : ArticleNode()

    @Serializable
    data class Image(val url: String, val width: Int, val height: Int) : ArticleNode()

    @Serializable
    data class CodeBlock(val code: String, val language: String = "") : ArticleNode()

    @Serializable
    data class Link(val text: String, val url: String) : ArticleNode()

    @Serializable
    data class Bold(val text: String) : ArticleNode()

    @Serializable
    data class BlockQuote(val content: List<ArticleNode>) : ArticleNode()

    @Serializable
    data class OrderedList(val items: List<String>) : ArticleNode()

    @Serializable
    data class UnorderedList(val items: List<String>) : ArticleNode()
}

@Serializable
enum class TextStyle {
    NORMAL,
    BOLD,
    ITALIC,
    UNDERLINE,
    STRIKETHROUGH,
}
