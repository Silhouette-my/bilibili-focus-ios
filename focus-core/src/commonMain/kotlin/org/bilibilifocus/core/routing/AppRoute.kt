package org.bilibilifocus.core.routing

sealed interface AppRoute {
    data object DynamicFeed : AppRoute
    data class SearchResults(val query: org.bilibilifocus.core.model.SearchQuery) : AppRoute
    data class Browser(val url: String) : AppRoute
}
