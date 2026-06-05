package org.bilibilifocus.core.service

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.crypto.md5Hex
import org.bilibilifocus.core.model.SearchQuery
import org.bilibilifocus.core.model.SearchResultFilter
import org.bilibilifocus.core.model.SearchResultItem
import org.bilibilifocus.core.model.SearchResultPage
import org.bilibilifocus.core.model.SearchResultSection
import org.bilibilifocus.core.model.SearchVideoSortOption
import org.bilibilifocus.core.routing.FocusNavigationPolicy

class SearchResultService(
    private val cookieProvider: CookieProvider,
    private val httpClient: HttpClient,
    private val userAgent: String = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
) {
    sealed class ServiceError(message: String) : Exception(message) {
        data object InvalidResponse : ServiceError("搜索接口返回无效数据")
        data class Api(val code: Int, override val message: String) :
            ServiceError(message)
        data object SigningUnavailable : ServiceError("搜索签名初始化失败")
    }

    private val json = Json { ignoreUnknownKeys = true }
    private val keyCache = WBIKeyCache()

    suspend fun fetchPage(
        query: SearchQuery,
        filter: SearchResultFilter = SearchResultFilter.ALL,
        page: Int = 1,
        videoSort: SearchVideoSortOption = SearchVideoSortOption.DEFAULT,
    ): SearchResultPage {
        val cookies = cookieProvider.loadCookies()
        val mixinKey = keyCache.mixinKey(cookies, userAgent)
        val url = makeSignedSearchURL(query, filter, page, mixinKey, videoSort)
        val headers = buildHeaders(query, cookies)

        val response = httpClient.get(url, headers)
        if (response.statusCode !in 200..299) {
            throw ServiceError.InvalidResponse
        }
        return decodePage(response.body, query, filter, page)
    }

    private fun buildHeaders(query: SearchQuery, cookies: List<org.bilibilifocus.core.cookie.Cookie>): Map<String, String> {
        val headers = mutableMapOf(
            "Accept" to "application/json, text/plain, */*",
            "Referer" to query.resultURL,
            "User-Agent" to userAgent,
        )
        return cookieProvider.attachCookies(headers, cookies)
    }

    fun decodePage(rawJson: String, query: SearchQuery, filter: SearchResultFilter, requestedPage: Int = 1): SearchResultPage {
        val payload = try {
            json.parseToJsonElement(rawJson) as? JsonObject
        } catch (_: Exception) {
            throw ServiceError.InvalidResponse
        } ?: throw ServiceError.InvalidResponse

        val code = payload.intValueAt("code") ?: -1
        val message = payload.stringValueAt("message") ?: "unknown"
        if (code != 0) throw ServiceError.Api(code, message)

        val dataPayload = payload.dictionaryValueAt("data")
            ?: return SearchResultPage(sections = emptyList(), nextPage = null)

        if (filter == SearchResultFilter.ALL) {
            val sections = makeOverviewSections(dataPayload)
            val nextPage = if (sections.any { it.filter == SearchResultFilter.VIDEO && it.items.isNotEmpty() }) 2 else null
            return SearchResultPage(sections = sections, nextPage = nextPage)
        }

        val items = dataPayload.arrayValueAt("result")
            ?.mapNotNull { it as? JsonObject }
            ?: emptyList()
        val section = makeSection(filter, items)
        val currentPage = dataPayload.intValueAt("page") ?: requestedPage
        val totalPages = dataPayload.intValueAt("numPages") ?: currentPage
        val nextPage = if (currentPage < totalPages) currentPage + 1 else null
        return SearchResultPage(
            sections = if (section.items.isEmpty()) emptyList() else listOf(section),
            nextPage = nextPage,
        )
    }

    private fun makeOverviewSections(dataPayload: JsonObject): List<SearchResultSection> {
        val blocks = dataPayload.arrayValueAt("result")?.mapNotNull { it as? JsonObject } ?: emptyList()
        val mappedSections = blocks.mapNotNull { block ->
            val resultType = block.stringValueAt("result_type") ?: return@mapNotNull null
            val filter = filterFor(resultType) ?: return@mapNotNull null
            val items = block.arrayValueAt("data")?.mapNotNull { it as? JsonObject } ?: emptyList()
            makeSection(filter, items)
        }

        val sectionMap = mutableMapOf<SearchResultFilter, SearchResultSection>()
        for (section in mappedSections) {
            if (section.items.isNotEmpty()) {
                sectionMap[section.filter] = section
            }
        }

        return SearchResultFilter.defaultOrder
            .filter { it != SearchResultFilter.ALL }
            .mapNotNull { sectionMap[it] }
    }

    private fun filterFor(rawResultType: String): SearchResultFilter? = when (rawResultType) {
        "video" -> SearchResultFilter.VIDEO
        "bili_user" -> SearchResultFilter.USERS
        "live_room" -> SearchResultFilter.LIVE
        "media_bangumi" -> SearchResultFilter.BANGUMI
        "media_ft" -> SearchResultFilter.FILM
        else -> null
    }

    private fun makeSection(filter: SearchResultFilter, items: List<JsonObject>): SearchResultSection {
        val mappedItems = items.mapNotNull { item ->
            when (filter) {
                SearchResultFilter.ALL -> null
                SearchResultFilter.VIDEO -> makeVideoItem(item)
                SearchResultFilter.USERS -> makeUserItem(item)
                SearchResultFilter.LIVE -> makeLiveItem(item)
                SearchResultFilter.BANGUMI, SearchResultFilter.FILM -> makeMediaItem(item, filter)
            }
        }
        return SearchResultSection(filter, mappedItems)
    }

    // Item builders...

    private fun makeVideoItem(item: JsonObject): SearchResultItem? {
        val targetURL = normalizedNavigationURL(
            item.stringValueAt("arcurl") ?: item.stringValueAt("url")
        ) ?: return null

        val title = cleanText(item.stringValueAt("title") ?: item.stringValueAt("typename"))
        val subtitle = cleanText(
            item.stringValueAt("author") ?: item.stringValueAt("up_name") ?: item.stringValueAt("uname")
        )
        val playText = formattedCount(item.stringValueAt("play") ?: item.stringValueAt("stat", "view"))
        val durationText = durationLabel(item.stringValueAt("duration") ?: item.stringValueAt("length"))
        val badgeText = durationText
        val metadataText = if (playText.isEmpty()) cleanText(item.stringValueAt("pubdate")) else "${playText}播放"
        val descriptionText = cleanText(item.stringValueAt("description") ?: item.stringValueAt("desc"))
        val coverURL = normalizedImageURL(item.stringValueAt("pic") ?: item.stringValueAt("cover"))
        val id = item.stringValueAt("bvid") ?: item.stringValueAt("id") ?: targetURL

        return SearchResultItem(
            id = id, kind = SearchResultItem.Kind.VIDEO,
            title = title.ifEmpty { "视频" }, subtitle = subtitle,
            metadataText = metadataText, badgeText = badgeText,
            descriptionText = descriptionText, coverURL = coverURL,
            targetURL = targetURL,
        )
    }

    private fun makeUserItem(item: JsonObject): SearchResultItem? {
        val id = item.stringValueAt("mid") ?: item.stringValueAt("uid") ?: "0"
        val fallbackSpaceURL = "https://space.bilibili.com/$id"
        val targetURL = normalizedNavigationURL(
            item.stringValueAt("uri") ?: item.stringValueAt("url") ?: item.stringValueAt("space_url") ?: fallbackSpaceURL
        ) ?: fallbackSpaceURL
        val title = cleanText(item.stringValueAt("uname") ?: item.stringValueAt("title"))
        val signature = cleanText(item.stringValueAt("usign") ?: item.stringValueAt("desc"))
        val fansText = formattedCount(item.stringValueAt("fans") ?: item.stringValueAt("fans_count"))
        val videoCount = plainCountString(item.stringValueAt("videos") ?: item.stringValueAt("archive_count"))
        val metadataParts = listOfNotNull(
            fansText.takeIf { it.isNotEmpty() }?.let { "粉丝 $it" },
            videoCount.takeIf { it.isNotEmpty() }?.let { "视频 $it" },
        )
        val metadataText = metadataParts.joinToString(" · ")
        val avatarURL = normalizedImageURL(item.stringValueAt("face") ?: item.stringValueAt("upic"))

        val previews = item.arrayValueAt("res")?.mapNotNull { preview ->
            val dict = preview as? JsonObject ?: return@mapNotNull null
            val previewURL = normalizedNavigationURL(
                dict.stringValueAt("arcurl") ?: dict.stringValueAt("url")
            ) ?: return@mapNotNull null
            val previewID = dict.stringValueAt("bvid") ?: dict.stringValueAt("id") ?: previewURL
            val previewTitle = cleanText(dict.stringValueAt("title") ?: dict.stringValueAt("typename"))
            val previewCover = normalizedImageURL(dict.stringValueAt("pic") ?: dict.stringValueAt("cover"))
            val previewMetadata = formattedCount(dict.stringValueAt("play") ?: dict.stringValueAt("stat", "view"))
            val previewBadge = durationLabel(dict.stringValueAt("duration") ?: dict.stringValueAt("length"))

            SearchResultItem.PreviewVideo(
                id = previewID,
                title = previewTitle.ifEmpty { "视频" },
                coverURL = previewCover,
                targetURL = previewURL,
                metadataText = if (previewMetadata.isEmpty()) "" else "${previewMetadata}播放",
                badgeText = previewBadge,
            )
        } ?: emptyList()

        return SearchResultItem(
            id = id, kind = SearchResultItem.Kind.USER,
            title = title.ifEmpty { "UP主" }, subtitle = signature,
            metadataText = metadataText, avatarURL = avatarURL,
            targetURL = targetURL, previews = previews,
        )
    }

    private fun makeLiveItem(item: JsonObject): SearchResultItem? {
        val roomID = item.stringValueAt("roomid") ?: item.stringValueAt("id")
        val directRoomURL = roomID?.let { "https://live.bilibili.com/$it" }
        val targetURL = directRoomURL?.let { FocusNavigationPolicy.canonicalWebURL(it) }
            ?: normalizedNavigationURL(item.stringValueAt("link") ?: item.stringValueAt("url"))
            ?: return null

        val title = cleanText(item.stringValueAt("title"))
        val uname = cleanText(item.stringValueAt("uname"))
        val areaText = cleanText(item.stringValueAt("area") ?: item.stringValueAt("cate_name"))
        val subtitle = listOf(uname, areaText).filter { it.isNotEmpty() }.joinToString(" · ")
        val onlineText = formattedCount(item.stringValueAt("online") ?: item.stringValueAt("online_total"))
        val badgeText = liveStatusText(item.stringValueAt("live_status"), areaText)
        val descriptionText = cleanText(
            item.stringValueAt("watched_show", "text_large") ?: item.stringValueAt("desc")
        )
        val coverURL = normalizedImageURL(
            item.stringValueAt("cover") ?: item.stringValueAt("user_cover") ?: item.stringValueAt("room_cover")
        )
        val id = roomID ?: targetURL

        return SearchResultItem(
            id = id, kind = SearchResultItem.Kind.LIVE,
            title = title.ifEmpty { "直播" }, subtitle = subtitle,
            metadataText = if (onlineText.isEmpty()) "" else "${onlineText}人气",
            badgeText = badgeText, descriptionText = descriptionText,
            coverURL = coverURL, targetURL = targetURL,
        )
    }

    private fun makeMediaItem(item: JsonObject, filter: SearchResultFilter): SearchResultItem? {
        val rawURL = item.stringValueAt("url") ?: item.stringValueAt("share_url") ?: item.stringValueAt("media_url")
        val targetURL = normalizedNavigationURL(rawURL) ?: return null

        val title = cleanText(item.stringValueAt("title") ?: item.stringValueAt("org_title"))
        val styleText = cleanText(item.stringValueAt("styles") ?: item.stringValueAt("style"))
        val areaText = cleanText(item.stringValueAt("areas"))
        val subtitle = listOf(styleText, areaText).filter { it.isNotEmpty() }.joinToString(" · ")
        val scoreText = mediaScoreText(item)
        val badgeText = cleanText(item.stringValueAt("season_type_name") ?: item.stringValueAt("badge"))
        val descriptionText = cleanText(item.stringValueAt("index_show") ?: item.stringValueAt("desc"))
        val coverURL = normalizedImageURL(
            item.stringValueAt("cover") ?: item.stringValueAt("season_cover") ?: item.stringValueAt("vertical_cover")
        )
        val id = item.stringValueAt("season_id") ?: item.stringValueAt("media_id") ?: targetURL

        return SearchResultItem(
            id = id, kind = SearchResultItem.Kind.MEDIA,
            title = title.ifEmpty { filter.sectionTitle }, subtitle = subtitle,
            metadataText = scoreText, badgeText = badgeText,
            descriptionText = descriptionText, coverURL = coverURL,
            targetURL = targetURL,
        )
    }

    // WBI Signing

    private fun makeSignedSearchURL(
        query: SearchQuery, filter: SearchResultFilter, page: Int,
        mixinKey: String, videoSort: SearchVideoSortOption,
    ): String {
        val params = mutableListOf<Pair<String, String>>()
        params.add("keyword" to query.keyword)

        if (filter != SearchResultFilter.ALL) {
            filter.apiSearchType?.let { params.add("search_type" to it) }
            params.add("page" to maxOf(page, 1).toString())
        }

        if (filter == SearchResultFilter.VIDEO) {
            videoSort.apiOrderValue?.let { params.add("order" to it) }
        }

        val wts = currentEpochSeconds().toString()
        params.add("wts" to wts)

        val filtered = params
            .map { (k, v) -> k to sanitizeWBIValue(v) }
            .sortedBy { it.first }

        val queryString = filtered.joinToString("&") { (k, v) -> "$k=$v" }
        val signature = md5Hex(queryString + mixinKey)

        val path = if (filter == SearchResultFilter.ALL) {
            "/x/web-interface/wbi/search/all/v2"
        } else {
            "/x/web-interface/wbi/search/type"
        }

        return "https://api.bilibili.com$path?$queryString&w_rid=$signature"
    }

    private fun sanitizeWBIValue(value: String): String =
        value.filter { it !in "!'()*" }

    // Helper functions

    private fun cleanText(rawValue: String?): String {
        if (rawValue == null) return ""
        var value = rawValue.trim()
        if (value.isEmpty()) return ""

        value = value.replace(Regex("<[^>]+>"), "")
        val htmlEntities = mapOf(
            "&amp;" to "&", "&lt;" to "<", "&gt;" to ">",
            "&quot;" to "\"", "&#39;" to "'", "&nbsp;" to " ",
        )
        for ((entity, replacement) in htmlEntities) {
            value = value.replace(entity, replacement)
        }

        return value
            .replace("\n", " ")
            .replace("\t", " ")
            .replace(Regex("\\s+"), " ")
            .trim()
    }

    private fun normalizedNavigationURL(rawValue: String?): String? {
        if (rawValue == null) return null
        var value = rawValue.trim()
        if (value.isEmpty()) return null

        value = when {
            value.startsWith("//") -> "https:$value"
            value.startsWith("/") -> "https://www.bilibili.com$value"
            else -> value
        }

        return FocusNavigationPolicy.canonicalWebURL(value)
    }

    private fun normalizedImageURL(rawValue: String?): String? {
        if (rawValue == null) return null
        var value = rawValue.trim()
        if (value.isEmpty()) return null

        if (value.startsWith("//")) value = "https:$value"
        return value.takeIf { it.isNotEmpty() }
    }

    private fun formattedCount(rawValue: String?): String {
        val rawText = cleanText(rawValue)
        if (rawText.isEmpty()) return ""
        if ("万" in rawText || "亿" in rawText) return rawText

        val normalized = rawText.replace(",", "")
        val value = normalized.toDoubleOrNull() ?: return rawText

        return when {
            value >= 100_000_000 -> "%.1f亿".format(value / 100_000_000).replace(".0", "")
            value >= 10_000 -> "%.1f万".format(value / 10_000).replace(".0", "")
            else -> value.toLong().toString()
        }
    }

    private fun plainCountString(rawValue: String?): String {
        val rawText = cleanText(rawValue)
        if (rawText.isEmpty()) return ""
        if ("万" in rawText || "亿" in rawText) return rawText

        val normalized = rawText.replace(",", "")
        return normalized.toIntOrNull()?.toString() ?: rawText
    }

    private fun durationLabel(rawValue: String?): String {
        val rawText = cleanText(rawValue)
        if (rawText.isEmpty()) return ""
        if (":" in rawText) return rawText

        val normalized = rawText.replace(",", "")
        val seconds = normalized.toIntOrNull() ?: return rawText
        if (seconds <= 0) return rawText

        val hours = seconds / 3600
        val minutes = (seconds % 3600) / 60
        val remainingSeconds = seconds % 60

        return if (hours > 0) {
            "%d:%02d:%02d".format(hours, minutes, remainingSeconds)
        } else {
            "%02d:%02d".format(minutes, remainingSeconds)
        }
    }

    private fun mediaScoreText(item: JsonObject): String {
        val rawScore = cleanText(
            item.stringValueAt("media_score", "score") ?: item.stringValueAt("score")
        )
        if (rawScore.isNotEmpty()) {
            return if (rawScore.startsWith("评分")) rawScore else "评分 $rawScore"
        }
        return cleanText(item.stringValueAt("cv") ?: item.stringValueAt("index_show"))
    }

    private fun liveStatusText(rawValue: String?, fallback: String): String = when (cleanText(rawValue)) {
        "1" -> "直播中"
        "0" -> if (fallback.isEmpty()) "未开播" else fallback
        else -> fallback
    }

    // WBI Mixin Key Cache

    private inner class WBIKeyCache {
        private var cachedKey: String? = null
        private var expiresAt: Long = 0

        suspend fun mixinKey(cookies: List<org.bilibilifocus.core.cookie.Cookie>, userAgent: String): String {
            val now = currentEpochSeconds() * 1000
            if (cachedKey != null && now < expiresAt) {
                return cachedKey!!
            }

            val headers = mutableMapOf(
                "Referer" to "https://www.bilibili.com/",
                "Accept" to "application/json, text/plain, */*",
                "User-Agent" to userAgent,
            )
            val finalHeaders = cookieProvider.attachCookies(headers, cookies)
            val response = httpClient.get("https://api.bilibili.com/x/web-interface/nav", finalHeaders)

            if (response.statusCode !in 200..299) {
                throw ServiceError.SigningUnavailable
            }

            val payload = json.parseToJsonElement(response.body) as? JsonObject
                ?: throw ServiceError.SigningUnavailable

            if (payload.intValueAt("code") != 0) throw ServiceError.SigningUnavailable

            val imgURL = payload.stringValueAt("data", "wbi_img", "img_url")
                ?: throw ServiceError.SigningUnavailable
            val subURL = payload.stringValueAt("data", "wbi_img", "sub_url")
                ?: throw ServiceError.SigningUnavailable

            val imgKey = imgURL.substringAfterLast("/").substringBefore(".")
            val subKey = subURL.substringAfterLast("/").substringBefore(".")

            if (imgKey.isEmpty() || subKey.isEmpty()) {
                throw ServiceError.SigningUnavailable
            }

            cachedKey = mixinKey(imgKey, subKey)
            expiresAt = now + 30 * 60 * 1000
            return cachedKey!!
        }
    }

    companion object {
        private val shuffleTable = intArrayOf(
            46, 47, 18, 2, 53, 8, 23, 32,
            15, 50, 10, 31, 58, 3, 45, 35,
            27, 43, 5, 49, 33, 9, 42, 19,
            29, 28, 14, 39, 12, 38, 41, 13,
            37, 48, 7, 16, 24, 55, 40, 61,
            26, 17, 0, 1, 60, 51, 30, 4,
            22, 25, 54, 21, 56, 59, 6, 63,
            57, 62, 11, 36, 20, 34, 44, 52,
        )

        fun mixinKey(imgKey: String, subKey: String): String {
            val combined = imgKey + subKey
            return shuffleTable.filter { it < combined.length }.map { combined[it] }.take(32).joinToString("")
        }
    }
}
