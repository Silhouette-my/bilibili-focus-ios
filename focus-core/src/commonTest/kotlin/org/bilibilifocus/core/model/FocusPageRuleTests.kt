package org.bilibilifocus.core.model

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class FocusPageRuleTests {

    @Test
    fun `match returns true when hosts and pathPrefixes are empty`() {
        val rule = FocusPageRule(
            id = "test",
            runPhase = FocusPageRule.RunPhase.DOCUMENT_END,
            features = emptyList(),
            hosts = emptyList(),
            pathPrefixes = emptyList(),
        )
        assertTrue(rule.match("any.host.com", "/any/path"))
    }

    @Test
    fun `match returns true when host matches and pathPrefixes empty`() {
        val rule = FocusPageRule(
            id = "test",
            hosts = listOf("example.com"),
            runPhase = FocusPageRule.RunPhase.DOCUMENT_END,
            features = emptyList(),
        )
        assertTrue(rule.match("example.com", "/any/path"))
        assertFalse(rule.match("other.com", "/any/path"))
    }

    @Test
    fun `match returns true when path prefix matches and hosts empty`() {
        val rule = FocusPageRule(
            id = "test",
            pathPrefixes = listOf("/video/"),
            runPhase = FocusPageRule.RunPhase.DOCUMENT_END,
            features = emptyList(),
        )
        assertTrue(rule.match("any.host", "/video/BV123"))
        assertFalse(rule.match("any.host", "/search"))
    }

    @Test
    fun `empty path is normalized to slash`() {
        val rule = FocusPageRule(
            id = "test",
            pathPrefixes = listOf("/"),
            runPhase = FocusPageRule.RunPhase.DOCUMENT_START,
            features = emptyList(),
        )
        assertTrue(rule.match("bilibili.com", ""))
    }
}
