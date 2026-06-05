package org.bilibilifocus.core.model

import org.bilibilifocus.core.storage.SettingsRepository
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class FocusSettingsTests {

    @Test
    fun `defaults match expected contract`() {
        val settings = FocusSettings.DEFAULTS

        assertTrue(settings.redirectEnabled)
        assertTrue(settings.playerMaskEnabled)
        assertTrue(settings.searchMaskEnabled)
        assertTrue(settings.dynamicMaskEnabled)
        assertFalse(settings.debugMode)
        assertEquals(FocusEntry.DYNAMIC, settings.defaultEntry)
    }

    @Test
    fun `serialization round-trip preserves values`() {
        val settings = FocusSettings(
            redirectEnabled = false,
            playerMaskEnabled = false,
            searchMaskEnabled = true,
            dynamicMaskEnabled = false,
            debugMode = true,
            defaultEntry = FocusEntry.SEARCH,
        )

        val json = kotlinx.serialization.json.Json.encodeToString(FocusSettings.serializer(), settings)
        val restored = kotlinx.serialization.json.Json.decodeFromString(FocusSettings.serializer(), json)

        assertEquals(settings, restored)
    }
}
