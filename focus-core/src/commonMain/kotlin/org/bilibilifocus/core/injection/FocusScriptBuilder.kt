package org.bilibilifocus.core.injection

import kotlinx.serialization.json.Json
import org.bilibilifocus.core.model.FocusPageRule
import org.bilibilifocus.core.model.FocusSettings

object FocusScriptBuilder {
    private val json = Json {
        prettyPrint = false
        encodeDefaults = true
    }

    private val runtimeTemplate: String by lazy {
        readBundleResource("focus-runtime.js")
    }

    fun makeUserScript(
        phase: FocusPageRule.RunPhase,
        settings: FocusSettings,
        rules: List<FocusPageRule> = FocusRuleCatalog.defaultRules,
    ): String {
        val configJSON = json.encodeToString(FocusSettings.serializer(), settings)
        val rulesJSON = json.encodeToString(
            kotlinx.serialization.builtins.ListSerializer(FocusPageRule.serializer()),
            rules,
        )

        return runtimeTemplate
            .replace("__FOCUS_CONFIG_JSON__", configJSON)
            .replace("__FOCUS_RULES_JSON__", rulesJSON)
            .replace(
                "__FOCUS_PHASE__",
                when (phase) {
                    FocusPageRule.RunPhase.DOCUMENT_START -> "documentStart"
                    FocusPageRule.RunPhase.DOCUMENT_END -> "documentEnd"
                },
            )
    }
}
