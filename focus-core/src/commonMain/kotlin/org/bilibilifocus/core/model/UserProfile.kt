package org.bilibilifocus.core.model

data class UserProfile(
    val mid: Long,
    val name: String,
    val avatarURL: String,
    val sign: String,
    val level: Int,
    val following: Long,
    val followers: Long,
)

data class UserVideo(
    val aid: Long,
    val bvid: String,
    val title: String,
    val coverURL: String,
    val playCount: Long,
    val danmakuCount: Long,
    val duration: String,
    val created: Long,
    val author: String = "",
)
