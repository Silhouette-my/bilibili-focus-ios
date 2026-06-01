import Foundation

public enum AppRoute: Equatable, Sendable {
    case dynamicFeed
    case browser(URL)
}
