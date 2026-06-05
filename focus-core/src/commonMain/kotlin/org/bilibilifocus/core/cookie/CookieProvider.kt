package org.bilibilifocus.core.cookie

data class Cookie(
    val name: String,
    val value: String,
    val domain: String,
    val path: String = "/",
)

interface CookieProvider {
    suspend fun loadCookies(): List<Cookie>

    fun attachCookies(requestHeaders: Map<String, String>, cookies: List<Cookie>): Map<String, String> {
        if (cookies.isEmpty()) return requestHeaders
        val cookieHeader = cookies.joinToString("; ") { "${it.name}=${it.value}" }
        return requestHeaders + mapOf("Cookie" to cookieHeader)
    }
}
