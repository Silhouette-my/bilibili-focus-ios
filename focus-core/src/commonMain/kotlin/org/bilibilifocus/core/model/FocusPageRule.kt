package org.bilibilifocus.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class FocusPageRule(
    val id: String,
    val hosts: List<String> = emptyList(),
    val pathPrefixes: List<String> = emptyList(),
    val runPhase: RunPhase,
    val metaViewport: String? = null,
    val features: List<FocusFeature>,
) {
    @Serializable
    enum class RunPhase {
        @SerialName("documentStart")
        DOCUMENT_START,

        @SerialName("documentEnd")
        DOCUMENT_END;
    }

    fun match(host: String, path: String): Boolean {
        val matchesHost = hosts.isEmpty() || host in hosts
        val normalizedPath = if (path.isEmpty()) "/" else path
        val matchesPath = pathPrefixes.isEmpty() || pathPrefixes.any { normalizedPath.startsWith(it) }
        return matchesHost && matchesPath
    }
}
