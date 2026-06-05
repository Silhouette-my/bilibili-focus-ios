package org.bilibilifocus.core.injection

import org.bilibilifocus.core.model.FocusPageRule
import org.bilibilifocus.core.model.FocusSettings
import kotlin.test.Test
import kotlin.test.assertTrue

class FocusScriptBuilderTests {

    @Test
    fun `document start script includes config and phase`() {
        val script = FocusScriptBuilder.makeUserScript(
            phase = FocusPageRule.RunPhase.DOCUMENT_START,
            settings = FocusSettings(debugMode = true),
        )

        // Script should contain the debug flag
        assertTrue("\"debugMode\":true" in script, "Script should contain debugMode setting")
        // Script should contain the phase marker
        assertTrue("documentStart" in script, "Script should contain documentStart phase")
        // Script should contain viewport meta
        assertTrue("width=device-width" in script, "Script should contain viewport meta")
    }

    @Test
    fun `dynamic rule matches expected page`() {
        val dynamicRule = FocusRuleCatalog.defaultRules.firstOrNull { it.id == "dynamic-prune" }

        assertTrue(dynamicRule != null, "Should find dynamic-prune rule")
        assertTrue(dynamicRule!!.match(host = "t.bilibili.com", path = "/"))
        assertTrue(!dynamicRule.match(host = "www.bilibili.com", path = "/"))
    }

    @Test
    fun `global viewport rule matches multiple hosts`() {
        val viewportRule = FocusRuleCatalog.defaultRules.firstOrNull { it.id == "global-viewport" }

        assertTrue(viewportRule != null)
        assertTrue(viewportRule!!.match(host = "www.bilibili.com", path = "/video/BV123"))
        assertTrue(viewportRule.match(host = "t.bilibili.com", path = "/"))
        assertTrue(viewportRule.match(host = "search.bilibili.com", path = "/all"))
    }
}
