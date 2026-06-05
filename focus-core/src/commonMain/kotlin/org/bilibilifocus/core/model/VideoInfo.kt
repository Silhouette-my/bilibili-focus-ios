package org.bilibilifocus.core.model

data class VideoInfo(
    val bvid: String,
    val aid: Long,
    val cid: Long,
    val title: String,
    val description: String,
    val coverURL: String,
    val duration: Long,
    val publishDate: Long,
    val author: VideoAuthor,
    val stats: VideoStats,
    val tags: List<String> = emptyList(),
    val playerURL: String? = null,
)

data class VideoAuthor(
    val name: String,
    val mid: Long,
    val avatarURL: String,
)

data class VideoStats(
    val views: Long,
    val likes: Long,
    val coins: Long,
    val favorites: Long,
    val shares: Long,
    val danmaku: Long,
    val comments: Long,
)
