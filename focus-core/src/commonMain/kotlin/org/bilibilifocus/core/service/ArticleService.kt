package org.bilibilifocus.core.service

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.ArticleAuthor
import org.bilibilifocus.core.model.ArticleDetail
import org.bilibilifocus.core.model.ArticleStats

class ArticleService(
    private val cookieProvider: CookieProvider,
    private val httpClient: HttpClient,
) {
    sealed class ServiceError(message: String) : Exception(message) {
        data object LoginRequired : ServiceError("需要登录")
        data class Api(val code: Int, override val message: String) : ServiceError(message)
        data object InvalidResponse : ServiceError("接口返回无效数据")
    }

    private val json = Json { ignoreUnknownKeys = true }

    suspend fun fetchArticleInfo(cvid: Long): ArticleDetail {
        val cookies = cookieProvider.loadCookies()
        val headers = mutableMapOf(
            "User-Agent" to "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36",
            "Referer" to "https://www.bilibili.com/",
        )
        if (cookies.isNotEmpty()) {
            headers["Cookie"] = cookies.joinToString("; ") { "${it.name}=${it.value}" }
        }

        val url = "https://api.bilibili.com/x/article/viewinfo?id=$cvid"
        val response = httpClient.get(url, headers)

        val root = json.parseToJsonElement(response.body) as? JsonObject
            ?: throw ServiceError.InvalidResponse

        val code = root["code"]?.jsonPrimitive?.int ?: throw ServiceError.InvalidResponse
        if (code != 0) {
            val message = root["message"]?.jsonPrimitive?.content ?: "未知错误"
            throw ServiceError.Api(code, message)
        }

        val data = root["data"]?.jsonObject ?: throw ServiceError.InvalidResponse

        return parseArticleDetail(cvid, data)
    }

    suspend fun fetchArticleContent(cvid: Long): String {
        val cookies = cookieProvider.loadCookies()
        val headers = mutableMapOf(
            "User-Agent" to "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36",
            "Referer" to "https://www.bilibili.com/",
        )
        if (cookies.isNotEmpty()) {
            headers["Cookie"] = cookies.joinToString("; ") { "${it.name}=${it.value}" }
        }

        val url = "https://api.bilibili.com/x/article/viewinfo?id=$cvid"
        val response = httpClient.get(url, headers)

        val root = json.parseToJsonElement(response.body) as? JsonObject
            ?: throw ServiceError.InvalidResponse

        val code = root["code"]?.jsonPrimitive?.int ?: throw ServiceError.InvalidResponse
        if (code != 0) {
            val message = root["message"]?.jsonPrimitive?.content ?: "未知错误"
            throw ServiceError.Api(code, message)
        }

        val data = root["data"]?.jsonObject ?: throw ServiceError.InvalidResponse
        return data["content"]?.jsonPrimitive?.content ?: ""
    }

    private fun parseArticleDetail(cvid: Long, data: JsonObject): ArticleDetail {
        val authorObj = data["author"]?.jsonObject
        val statsObj = data["stats"]?.jsonObject

        val author = ArticleAuthor(
            mid = authorObj?.get("mid")?.jsonPrimitive?.long ?: 0L,
            name = authorObj?.get("name")?.jsonPrimitive?.content ?: "",
            avatarURL = authorObj?.get("face")?.jsonPrimitive?.content ?: "",
        )

        val stats = ArticleStats(
            views = statsObj?.get("view")?.jsonPrimitive?.long ?: 0L,
            likes = statsObj?.get("like")?.jsonPrimitive?.long ?: 0L,
            coins = statsObj?.get("coin")?.jsonPrimitive?.long ?: 0L,
            favorites = statsObj?.get("favorite")?.jsonPrimitive?.long ?: 0L,
            comments = statsObj?.get("reply")?.jsonPrimitive?.long ?: 0L,
        )

        val tags = data["tags"]?.jsonArray?.mapNotNull {
            it.jsonObject["name"]?.jsonPrimitive?.content
        } ?: emptyList()

        return ArticleDetail(
            cvid = cvid,
            title = data["title"]?.jsonPrimitive?.content ?: "",
            author = author,
            publishTime = data["publish_time"]?.jsonPrimitive?.long ?: 0L,
            stats = stats,
            bannerUrl = data["banner_url"]?.jsonPrimitive?.content ?: "",
            content = emptyList(),
            tags = tags,
        )
    }
}
