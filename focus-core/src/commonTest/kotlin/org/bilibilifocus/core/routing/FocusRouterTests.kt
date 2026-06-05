package org.bilibilifocus.core.routing

import org.bilibilifocus.core.model.FocusEntry
import org.bilibilifocus.core.model.FocusSettings
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class FocusRouterTests {

    @Test
    fun `homepage redirect uses default entry`() {
        val router = FocusRouter(
            FocusSettings(redirectEnabled = true, defaultEntry = FocusEntry.SEARCH)
        )

        val decision = router.decision("https://www.bilibili.com/")
        assertTrue(decision is FocusRouter.Decision.Redirect)
        assertEquals(FocusEntry.SEARCH, (decision as FocusRouter.Decision.Redirect).entry)
    }

    @Test
    fun `homepage redirect disabled allows navigation`() {
        val router = FocusRouter(
            FocusSettings(redirectEnabled = false, defaultEntry = FocusEntry.SEARCH)
        )

        assertTrue(router.decision("https://m.bilibili.com/") is FocusRouter.Decision.Allow)
    }

    @Test
    fun `non-homepage does not redirect`() {
        val router = FocusRouter(FocusSettings.DEFAULTS)
        assertTrue(router.decision("https://t.bilibili.com/") is FocusRouter.Decision.Allow)
    }

    @Test
    fun `entry route uses native dynamic feed`() {
        val router = FocusRouter(
            FocusSettings(redirectEnabled = true, defaultEntry = FocusEntry.SEARCH)
        )

        assertEquals(AppRoute.DynamicFeed, router.entryRoute())
    }
}
