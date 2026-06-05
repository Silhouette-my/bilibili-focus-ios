package org.bilibilifocus.core.service

data class HttpRequest(
    val url: String,
    val headers: Map<String, String> = emptyMap(),
)

data class HttpResponse(
    val statusCode: Int,
    val body: String,
)

interface HttpClient {
    suspend fun get(url: String, headers: Map<String, String> = emptyMap()): HttpResponse
    suspend fun post(url: String, body: String = "", headers: Map<String, String> = emptyMap()): HttpResponse
}
