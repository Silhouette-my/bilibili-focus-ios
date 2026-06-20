package org.bilibilifocus.core.service

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.crypto.md5Hex
import org.bilibilifocus.core.model.PlayUrlResult

/**
 * 取视频 DASH 流地址，供 ExoPlayer 播放。基于 x/player/wbi/playurl（需 WBI 签名）。
 * 优先选 AVC(H.264, codecid=7) 视频轨以保证设备/模拟器兼容；音频取最高码率。
 * 流地址下载时必须带 Referer + User-Agent。
 */
class PlayUrlService(
    private val cookieProvider: CookieProvider,
    private val httpClient: HttpClient,
    private val userAgent: String = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
) {
    sealed class ServiceError(message: String) : Exception(message) {
        data object InvalidResponse : ServiceError("接口返回无效数据")
        data object NoStream : ServiceError("未获取到可播放的视频流")
        data object SigningUnavailable : ServiceError("签名初始化失败")
        data class Api(val code: Int, override val message: String) : ServiceError(message)
    }

    private val json = Json { ignoreUnknownKeys = true }
    private val keyCache = WBIKeyCache()

    suspend fun fetchPlayUrl(bvid: String, cid: Long): PlayUrlResult {
        val mixinKey = keyCache.mixinKey()
        val wts = currentEpochSeconds().toString()
        // WBI 要求参数按 key 字典序排列后再签名
        val query = "bvid=$bvid&cid=$cid&fnval=4048&fourk=1&otype=json&platform=pc&qn=80&wts=$wts"
        val wrid = md5Hex(query + mixinKey)
        val url = "https://api.bilibili.com/x/player/wbi/playurl?$query&w_rid=$wrid"

        val response = httpClient.get(url, buildHeaders())
        if (response.statusCode !in 200..299) throw ServiceError.InvalidResponse

        val payload = json.parseToJsonElement(response.body) as? JsonObject
            ?: throw ServiceError.InvalidResponse
        val code = payload.intValueAt("code") ?: -1
        if (code != 0) throw ServiceError.Api(code, payload.stringValueAt("message") ?: "未知错误")

        val videos = payload.arrayValueAt("data", "dash", "video") ?: throw ServiceError.NoStream
        val audios = payload.arrayValueAt("data", "dash", "audio") ?: emptyList()

        // 收集 baseUrl + backupUrl，优先非 PCDN(mcdn/szbdyd)地址，规避第三方播放器 403
        fun pickUrl(item: JsonObject): String? {
            val candidates = mutableListOf<String>()
            (item.stringValueAt("baseUrl") ?: item.stringValueAt("base_url"))?.let { candidates.add(it) }
            (item.arrayValueAt("backupUrl") ?: item.arrayValueAt("backup_url"))?.forEach { el ->
                (el as? kotlinx.serialization.json.JsonPrimitive)?.content?.let { candidates.add(it) }
            }
            return candidates.firstOrNull { "mcdn" !in it && "szbdyd" !in it } ?: candidates.firstOrNull()
        }

        val videoObjs = videos.mapNotNull { it as? JsonObject }
        // 优先 AVC(codecid=7)，否则取第一个
        val videoUrl = (videoObjs.firstOrNull { it.intValueAt("codecid") == 7 } ?: videoObjs.firstOrNull())
            ?.let { pickUrl(it) }
            ?: throw ServiceError.NoStream

        val audioUrl = audios.mapNotNull { it as? JsonObject }.firstOrNull()?.let { pickUrl(it) }

        val cookieHeader = cookieProvider.loadCookies().joinToString("; ") { "${it.name}=${it.value}" }
        return PlayUrlResult(videoUrl = videoUrl, audioUrl = audioUrl, cookie = cookieHeader, userAgent = userAgent)
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

    private inner class WBIKeyCache {
        private var cachedKey: String? = null
        private var expiresAt: Long = 0

        suspend fun mixinKey(): String {
            val now = currentEpochSeconds() * 1000
            if (cachedKey != null && now < expiresAt) return cachedKey!!

            val response = httpClient.get("https://api.bilibili.com/x/web-interface/nav", buildHeaders())
            if (response.statusCode !in 200..299) throw ServiceError.SigningUnavailable

            val payload = json.parseToJsonElement(response.body) as? JsonObject
                ?: throw ServiceError.SigningUnavailable

            val imgURL = payload.stringValueAt("data", "wbi_img", "img_url")
                ?: throw ServiceError.SigningUnavailable
            val subURL = payload.stringValueAt("data", "wbi_img", "sub_url")
                ?: throw ServiceError.SigningUnavailable

            val imgKey = imgURL.substringAfterLast("/").substringBefore(".")
            val subKey = subURL.substringAfterLast("/").substringBefore(".")
            if (imgKey.isEmpty() || subKey.isEmpty()) throw ServiceError.SigningUnavailable

            val raw = imgKey + subKey
            cachedKey = buildString {
                for (idx in WBI_SHUFFLE_TABLE) {
                    if (idx < raw.length) append(raw[idx])
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
