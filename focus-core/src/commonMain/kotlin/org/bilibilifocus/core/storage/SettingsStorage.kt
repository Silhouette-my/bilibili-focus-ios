package org.bilibilifocus.core.storage

expect class SettingsStorage {
    fun getString(key: String): String?
    fun putString(key: String, value: String)
}
