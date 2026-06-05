package org.bilibilifocus.core.storage

import platform.Foundation.NSUserDefaults

actual class SettingsStorage {
    private val defaults = NSUserDefaults.standardUserDefaults

    actual fun getString(key: String): String? = defaults.stringForKey(key)

    actual fun putString(key: String, value: String) {
        defaults.setObject(value, forKey = key)
        defaults.synchronize()
    }
}
