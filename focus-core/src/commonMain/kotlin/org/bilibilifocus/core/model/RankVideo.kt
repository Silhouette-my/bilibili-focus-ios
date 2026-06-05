package org.bilibilifocus.core.model

data class RankVideo(
    val aid: Long,
    val bvid: String,
    val title: String,
    val coverURL: String,
    val playCount: Long,
    val danmakuCount: Long,
    val author: String,
    val mid: Long,
    val duration: String,
)

data class RankCategory(
    val label: String,
    val rid: Int,
    val type: String = "all",
)
