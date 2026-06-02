import Foundation

public enum AppRoute: Equatable, Sendable {
    case dynamicFeed
    case searchResults(SearchQuery)
    case browser(URL)
}
