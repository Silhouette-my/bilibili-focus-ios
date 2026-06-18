package org.bilibilifocus.core.service

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.crypto.md5Hex
import org.bilibilifocus.core.model.UserProfile
import org.bilibilifocus.core.model.UserVideo

class UserService(
    private val cookieProvider: CookieProvider,
    private val httpClient: HttpClient,
    private val userAgent: String = "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
) {
    sealed class ServiceError(message: String) : Exception(message) {
        data object InvalidResponse : ServiceError("接口返回无效数据")
        data class Api(val code: Int, override val message: String) : ServiceError(message)
        data object SigningUnavailable : ServiceError("签名初始化失败")
    }

    private val json = Json { ignoreUnknownKeys = true }
    private val keyCache = WBIKeyCache()

    suspend fun fetchUserInfo(mid: Long): UserProfile {
        val mixinKey = keyCache.mixinKey()
        val wts = currentEpochSeconds().toString()
        val queryString = "mid=$mid&w_webid=&wts=$wts"
        val wrid = md5Hex(queryString + mixinKey)
        val url = "https://api.bilibili.com/x/space/wbi/acc/info?$queryString&w_rid=$wrid"

        val response = httpClient.get(url, buildHeaders())
        if (response.statusCode !in 200..299) throw ServiceError.InvalidResponse

        val payload = json.parseToJsonElement(response.body) as? JsonObject
            ?: throw ServiceError.InvalidResponse
        val code = payload.intValueAt("code") ?: -1
        if (code != 0) {
            val msg = payload.stringValueAt("message") ?: "未知错误"
            throw ServiceError.Api(code, msg)
        }

        val data = payload.dictionaryValueAt("data") ?: throw ServiceError.InvalidResponse
        return UserProfile(
            mid = data.intValueAt("mid")?.toLong() ?: mid,
            name = data.stringValueAt("name") ?: "",
            avatarURL = data.stringValueAt("face") ?: "",
            sign = data.stringValueAt("sign") ?: "",
            level = data.intValueAt("level") ?: 0,
            following = 0, // filled separately
            followers = 0,
        )
    }

    suspend fun fetchRelationInfo(mid: Long): Pair<Long, Long> {
        val url = "https://api.bilibili.com/x/relation/stat?vmid=$mid"
        val response = httpClient.get(url, buildHeaders())
        if (response.statusCode !in 200..299) return 0L to 0L

        val payload = json.parseToJsonElement(response.body) as? JsonObject ?: return 0L to 0L
        val data = payload.dictionaryValueAt("data") ?: return 0L to 0L
        val following = data.intValueAt("following")?.toLong() ?: 0L
        val follower = data.intValueAt("follower")?.toLong() ?: 0L
        return following to follower
    }

    suspend fun fetchUserVideos(mid: Long, page: Int = 1, pageSize: Int = 30): List<UserVideo> {
        val mixinKey = keyCache.mixinKey()
        val ps = pageSize.coerceIn(1, 50)
        val pn = page.coerceAtLeast(1)
        val wts = currentEpochSeconds().toString()
        val queryString = "mid=$mid&ps=$ps&pn=$pn&tid=0&keyword=&order=pubdate&order_avoided=true&platform=web&wts=$wts"
        val wrid = md5Hex(queryString + mixinKey)
        val url = "https://api.bilibili.com/x/space/wbi/arc/search?$queryString&w_rid=$wrid"

        val response = httpClient.get(url, buildHeaders())
        if (response.statusCode !in 200..299) return emptyList()

        val payload = json.parseToJsonElement(response.body) as? JsonObject ?: return emptyList()
        val code = payload.intValueAt("code") ?: -1
        if (code != 0) return emptyList()

        val vlist = payload.arrayValueAt("data", "list", "vlist") ?: return emptyList()
        return vlist.mapNotNull { item ->
            val dict = item as? JsonObject ?: return@mapNotNull null
            val length = dict.stringValueAt("length") ?: ""
            UserVideo(
                aid = dict.intValueAt("aid")?.toLong() ?: 0L,
                bvid = dict.stringValueAt("bvid") ?: "",
                title = dict.stringValueAt("title") ?: "",
                coverURL = dict.stringValueAt("pic") ?: "",
                playCount = dict.intValueAt("play")?.toLong() ?: 0L,
                danmakuCount = dict.intValueAt("video_review")?.toLong() ?: 0L,
                duration = formatDuration(length),
                created = dict.intValueAt("created")?.toLong() ?: 0L,
                author = dict.stringValueAt("author") ?: "",
            )
        }
    }

    private fun formatDuration(raw: String): String {
        val parts = raw.split(":")
        if (parts.size < 2) return raw
        return when (parts.size) {
            2 -> "${parts[0].toIntOrNull() ?: 0}:${parts[1].padStart(2, '0')}"
            3 -> {
                val h = parts[0].toIntOrNull() ?: 0
                val m = parts[1].padStart(2, '0')
                val s = parts[2].padStart(2, '0')
                "$h:$m:$s"
            }
            else -> raw
        }
    }

    private suspend fun buildHeaders(): Map<String, String> {
        val cookies = cookieProvider.loadCookies()
        val headers = mutableMapOf(
            "User-Agent" to userAgent,
            "Referer" to "https://space.bilibili.com/",
            "Accept" to "application/json, text/plain, */*",
        )
        return cookieProvider.attachCookies(headers, cookies)
    }

    private inner class WBIKeyCache {
        private var cachedKey: String? = null
        private var expiresAt: Long = 0

        suspend fun mixinKey(): String {
            val now = currentEpochSeconds() * 1000
            if (cachedKey != null && now < expiresAt) return cachedKey!!

            val headers = buildHeaders()
            val response = httpClient.get("https://api.bilibili.com/x/web-interface/nav", headers)
            if (response.statusCode !in 200..299) throw ServiceError.SigningUnavailable

            val payload = json.parseToJsonElement(response.body) as? JsonObject
                ?: throw ServiceError.SigningUnavailable
            if (payload.intValueAt("code") != 0) throw ServiceError.SigningUnavailable

            val imgURL = payload.stringValueAt("data", "wbi_img", "img_url")
                ?: throw ServiceError.SigningUnavailable
            val subURL = payload.stringValueAt("data", "wbi_img", "sub_url")
                ?: throw ServiceError.SigningUnavailable

            val imgKey = imgURL.substringAfterLast("/").substringBefore(".")
            val subKey = subURL.substringAfterLast("/").substringBefore(".")
            if (imgKey.isEmpty() || subKey.isEmpty()) throw ServiceError.SigningUnavailable

            cachedKey = buildString {
                for (idx in WBI_SHUFFLE_TABLE) {
                    if (idx < (imgKey + subKey).length) append((imgKey + subKey)[idx])
                }
            }.take(32)
            expiresAt = now + 30 * 60 * 1000
            return cachedKey!!
        }
    }

    companion object {
        private val WBI_SHUFFLE_TABLE = intArrayOf(
            46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
            27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
            37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
            22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 52, 34, 44,
        )
    }
}
