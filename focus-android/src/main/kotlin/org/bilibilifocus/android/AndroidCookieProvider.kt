package org.bilibilifocus.android

import android.webkit.CookieManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider

class AndroidCookieProvider : CookieProvider {
    override suspend fun loadCookies(): List<Cookie> = withContext(Dispatchers.Main) {
        val allCookies = mutableListOf<Cookie>()
        val seen = mutableSetOf<String>()

        val manager = CookieManager.getInstance()
        // Flush to ensure cookies are synced from persistent storage
        manager.flush()

        // Collect from all relevant domains
        val bilibiliDomains = listOf(
            "https://bilibili.com",
            "https://.bilibili.com",
            "https://www.bilibili.com",
            "https://m.bilibili.com",
            "https://t.bilibili.com",
            "https://api.bilibili.com",
            "https://search.bilibili.com",
            "https://passport.bilibili.com",
            "https://player.bilibili.com",
            "https://live.bilibili.com",
            "https://space.bilibili.com",
        )

        for (domain in bilibiliDomains) {
            val cookieStr = manager.getCookie(domain) ?: continue
            for (pair in cookieStr.split(";")) {
                val trimmed = pair.trim()
                val eqIdx = trimmed.indexOf('=')
                if (eqIdx <= 0) continue
                val name = trimmed.substring(0, eqIdx).trim()
                val value = trimmed.substring(eqIdx + 1).trim()
                if (name.isNotEmpty()) {
                    val existing = allCookies.find { it.name == name }
                    if (existing == null) {
                        allCookies.add(Cookie(name = name, value = value, domain = domain))
                        seen.add(name)
                    } else if (existing.value.isEmpty() && value.isNotEmpty()) {
                        // Replace empty-valued cookie with non-empty one
                        allCookies.remove(existing)
                        allCookies.add(Cookie(name = name, value = value, domain = domain))
                    }
                }
            }
        }

        allCookies
    }
}
