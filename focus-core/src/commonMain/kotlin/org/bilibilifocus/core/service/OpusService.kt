package org.bilibilifocus.core.service

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.OpusAuthor
import org.bilibilifocus.core.model.OpusBlock
import org.bilibilifocus.core.model.OpusDetail
import org.bilibilifocus.core.model.OpusImage
import org.bilibilifocus.core.model.OpusTextNode

class OpusService(
    private val cookieProvider: CookieProvider,
    private val httpClient: HttpClient,
    private val userAgent: String = "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
) {
    sealed class ServiceError(message: String) : Exception(message) {
        data object LoginRequired : ServiceError("需要登录")
        data object InvalidResponse : ServiceError("接口返回无效数据")
        data class Api(val code: Int, override val message: String) : ServiceError(message)
    }

    private val json = Json { ignoreUnknownKeys = true }

    suspend fun fetchOpusDetail(id: String): OpusDetail {
        val url = "https://api.bilibili.com/x/polymer/web-dynamic/v1/opus/detail" +
            "?id=$id&timezone_offset=-480" +
            "&features=onlyfansVote,onlyfansAssetsV2,decorationCard,htmlNewStyle,ugcDelete,editable,opusPrivateVisible"

        val response = httpClient.get(url, buildHeaders())
        if (response.statusCode !in 200..299) throw ServiceError.InvalidResponse

        val payload = try {
            json.parseToJsonElement(response.body) as? JsonObject
        } catch (_: Exception) {
            throw ServiceError.InvalidResponse
        } ?: throw ServiceError.InvalidResponse

        val code = payload.intValueAt("code") ?: -1
        if (code == -101) throw ServiceError.LoginRequired
        if (code != 0) {
            val msg = payload.stringValueAt("message") ?: "未知错误"
            throw ServiceError.Api(code, msg)
        }

        val data = payload.dictionaryValueAt("data")
            ?: throw ServiceError.InvalidResponse

        val item = data.dictionaryValueAt("item")

        // 如果没有 item，尝试直接从 data 解析
        if (item == null) {
            val directParagraphs = parseParagraphs(data)
            if (directParagraphs.isNotEmpty()) {
                return OpusDetail(
                    id = id,
                    author = OpusAuthor(name = "用户", mid = 0, avatarURL = ""),
                    publishTime = "",
                    paragraphs = directParagraphs,
                )
            }
            throw ServiceError.InvalidResponse
        }

        val basic = item.dictionaryValueAt("basic") ?: JsonObject(emptyMap())
        val modules = item.dictionaryValueAt("modules") ?: JsonObject(emptyMap())

        val opusId = basic.stringValueAt("comment_id_str")
            ?: basic.stringValueAt("rid_str")
            ?: id

        val authorModule = modules.dictionaryValueAt("module_author")
        val authorName = authorModule?.stringValueAt("name")?.ifEmpty { null } ?: "用户"
        val authorMid = authorModule?.intValueAt("mid")?.toLong() ?: 0L
        val authorAvatar = authorModule?.stringValueAt("face") ?: ""
        val publishTime = authorModule?.stringValueAt("pub_time")
            ?: authorModule?.stringValueAt("pub_time_text")
            ?: authorModule?.intValueAt("pub_ts")?.toString()
            ?: ""

        val paragraphs = parseParagraphs(modules)

        // 如果解析不到段落，至少返回一个空的结果而不是抛异常
        if (paragraphs.isEmpty()) {
            return OpusDetail(
                id = opusId,
                author = OpusAuthor(name = authorName, mid = authorMid, avatarURL = authorAvatar),
                publishTime = publishTime,
                paragraphs = listOf(
                    OpusDetail.Paragraph(
                        listOf(OpusBlock.Text(listOf(OpusTextNode(text = "暂无内容", bold = false))))
                    )
                ),
            )
        }

        return OpusDetail(
            id = opusId,
            author = OpusAuthor(name = authorName, mid = authorMid, avatarURL = authorAvatar),
            publishTime = publishTime,
            paragraphs = paragraphs,
        )
    }

    private fun parseParagraphs(modules: JsonObject): List<OpusDetail.Paragraph> {
        val contentModule = modules.dictionaryValueAt("module_content")
            ?: modules.dictionaryValueAt("content")
            ?: return emptyList()

        val paragraphsJson = contentModule.arrayValueAt("paragraphs")
            ?: contentModule.arrayValueAt("items")
            ?: return emptyList()

        return paragraphsJson.mapNotNull { para ->
            val dict = para as? JsonObject ?: return@mapNotNull null
            val paraType = dict.intValueAt("para_type")
                ?: dict.intValueAt("type")
                ?: return@mapNotNull null
            val blocks = parseBlocks(dict, paraType)
            if (blocks.isEmpty()) null else OpusDetail.Paragraph(blocks)
        }.filterNot { it.blocks.isEmpty() }
    }

    private fun parseBlocks(para: JsonObject, paraType: Int): List<OpusBlock> {
        return when (paraType) {
            1 -> {
                // 纯文字段落
                val nodesArray = para.arrayValueAt("text", "nodes")
                    ?: para.arrayValueAt("nodes")
                    ?: return emptyList()

                val nodes = nodesArray.mapNotNull { node ->
                    val dict = node as? JsonObject ?: return@mapNotNull null
                    val words = dict.stringValueAt("word", "words")
                        ?: dict.stringValueAt("words")
                        ?: dict.stringValueAt("text")
                        ?: ""
                    val bold = dict.dictionaryValueAt("word", "style")?.intValueAt("bold") == 1
                        || dict.dictionaryValueAt("style")?.intValueAt("bold") == 1
                    val linkUrl = dict.stringValueAt("rich", "jump_url")
                        ?: dict.stringValueAt("jump_url")
                    val emojiUrl = dict.stringValueAt("rich", "emoji", "icon_url")
                        ?: dict.stringValueAt("emoji", "icon_url")
                        ?: dict.stringValueAt("icon_url")

                    if (words.isEmpty() && emojiUrl == null && linkUrl == null) null
                    else OpusTextNode(text = words, bold = bold, linkUrl = linkUrl, emojiUrl = emojiUrl)
                }
                if (nodes.isEmpty()) emptyList() else listOf(OpusBlock.Text(nodes))
            }
            2 -> {
                // 图片段落
                val picsArray = para.arrayValueAt("pic", "pics")
                    ?: para.arrayValueAt("pics")
                    ?: para.arrayValueAt("images")
                    ?: return emptyList()

                val pics = picsArray.mapNotNull { pic ->
                    val dict = pic as? JsonObject ?: return@mapNotNull null
                    val url = dict.stringValueAt("url")
                        ?: dict.stringValueAt("src")
                        ?: return@mapNotNull null
                    OpusImage(
                        url = url,
                        width = dict.intValueAt("width") ?: 0,
                        height = dict.intValueAt("height") ?: 0
                    )
                }
                if (pics.isEmpty()) emptyList() else listOf(OpusBlock.Image(pics))
            }
            7 -> {
                // 代码块
                val lang = para.stringValueAt("code", "lang")
                    ?: para.stringValueAt("lang")
                    ?: ""
                val content = para.stringValueAt("code", "content")
                    ?: para.stringValueAt("content")
                    ?: ""
                if (content.isEmpty()) emptyList() else listOf(OpusBlock.Code(lang = lang, content = content))
            }
            else -> emptyList()
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
