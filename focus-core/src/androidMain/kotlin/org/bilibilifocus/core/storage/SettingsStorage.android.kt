package org.bilibilifocus.core.storage

import android.content.Context
import android.content.SharedPreferences

actual class SettingsStorage(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("focus", Context.MODE_PRIVATE)

    actual fun getString(key: String): String? = prefs.getString(key, null)

    actual fun putString(key: String, value: String) {
        prefs.edit().putString(key, value).apply()
    }
}
