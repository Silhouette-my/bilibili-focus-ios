package org.bilibilifocus.core.service

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.RankCategory
import org.bilibilifocus.core.model.RankVideo

class RankService(
    private val cookieProvider: CookieProvider,
    private val httpClient: HttpClient,
    private val userAgent: String = "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
) {
    sealed class ServiceError(message: String) : Exception(message) {
        data object InvalidResponse : ServiceError("接口返回无效数据")
        data class Api(val code: Int, override val message: String) : ServiceError(message)
    }

    private val json = Json { ignoreUnknownKeys = true }

    val categories: List<RankCategory> = listOf(
        RankCategory("全站", 0),
        RankCategory("动画", 1005),
        RankCategory("音乐", 1003),
        RankCategory("舞蹈", 1004),
        RankCategory("游戏", 1008),
        RankCategory("知识", 1010),
        RankCategory("科技", 1012),
        RankCategory("运动", 1018),
        RankCategory("汽车", 1013),
        RankCategory("生活", 160),
        RankCategory("美食", 1020),
        RankCategory("动物圈", 1024),
        RankCategory("鬼畜", 1007),
        RankCategory("时尚", 1014),
        RankCategory("娱乐", 1002),
        RankCategory("影视", 1001),
        RankCategory("国创", 168),
        RankCategory("原创", 0, "origin"),
        RankCategory("新人", 0, "rookie"),
    )

    suspend fun fetchRank(rid: Int = 0, type: String = "all"): List<RankVideo> {
        val url = "https://api.bilibili.com/x/web-interface/ranking/v2?rid=$rid&type=$type"
        val response = httpClient.get(url, buildHeaders())
        if (response.statusCode !in 200..299) throw ServiceError.InvalidResponse

        val payload = try {
            json.parseToJsonElement(response.body) as? JsonObject
        } catch (e: Exception) {
            throw ServiceError.InvalidResponse
        } ?: throw ServiceError.InvalidResponse

        val code = payload.intValueAt("code") ?: -1
        if (code != 0) {
            val msg = payload.stringValueAt("message") ?: "未知错误"
            throw ServiceError.Api(code, msg)
        }

        val list = payload.arrayValueAt("data", "list") ?: return emptyList()
        return list.mapNotNull { item ->
            try {
                val dict = item as? JsonObject ?: return@mapNotNull null
                val aid = dict.intValueAt("aid")?.toLong() ?: return@mapNotNull null
                val bvid = dict.stringValueAt("bvid") ?: return@mapNotNull null
                val title = dict.stringValueAt("title") ?: return@mapNotNull null
                val coverURL = dict.stringValueAt("pic") ?: ""
                val author = dict.stringValueAt("owner", "name")
                    ?: dict.stringValueAt("author")
                    ?: "未知UP主"
                val mid = dict.intValueAt("owner", "mid")?.toLong()
                    ?: dict.intValueAt("mid")?.toLong()
                    ?: 0L

                val stat = dict.dictionaryValueAt("stat")
                val playCount = stat?.intValueAt("view")?.toLong()
                    ?: dict.intValueAt("play")?.toLong()
                    ?: dict.intValueAt("view")?.toLong()
                    ?: 0L
                val danmakuCount = stat?.intValueAt("danmaku")?.toLong()
                    ?: dict.intValueAt("danmaku")?.toLong()
                    ?: 0L

                val durationStr = dict.stringValueAt("duration") ?: ""
                val duration = formatDuration(durationStr)

                RankVideo(
                    aid = aid,
                    bvid = bvid,
                    title = title,
                    coverURL = coverURL,
                    playCount = playCount,
                    danmakuCount = danmakuCount,
                    author = author,
                    mid = mid,
                    duration = duration,
                )
            } catch (e: Exception) {
                null
            }
        }
    }

    private fun formatDuration(seconds: String): String {
        val secs = seconds.toIntOrNull() ?: return seconds
        if (secs <= 0) return ""
        val hours = secs / 3600
        val minutes = (secs % 3600) / 60
        val remainingSeconds = secs % 60
        return if (hours > 0) {
            "%d:%02d:%02d".format(hours, minutes, remainingSeconds)
        } else {
            "%02d:%02d".format(minutes, remainingSeconds)
        }
    }

    private suspend fun buildHeaders(): Map<String, String> {
        val cookies = cookieProvider.loadCookies()
        val headers = mutableMapOf(
            "User-Agent" to userAgent,
            "Referer" to "https://www.bilibili.com/",
            "Accept" to "application/json, text/plain, */*",
        )
        return cookieProvider.attachCookies(headers, cookies)
    }
}
