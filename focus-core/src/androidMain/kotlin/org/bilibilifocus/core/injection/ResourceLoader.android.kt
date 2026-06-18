package org.bilibilifocus.core.injection

import java.io.InputStreamReader

actual fun readBundleResource(name: String): String {
    val classLoader = ResourceLoader::class.java.classLoader
    val stream = classLoader.getResourceAsStream(name)
        ?: error("Resource not found: $name")
    return InputStreamReader(stream, Charsets.UTF_8).use { it.readText() }
}

private object ResourceLoader
