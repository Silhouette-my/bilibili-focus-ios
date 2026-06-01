import Foundation

public struct FocusRouter: Sendable {
    public enum Decision: Equatable, Sendable {
        case allow
        case redirect(FocusEntry)
    }

    private let settings: FocusSettings
    private static let homepageHosts = Set([
        "bilibili.com",
        "www.bilibili.com",
        "m.bilibili.com",
    ])
    private static let homepagePaths = Set([
        "",
        "/",
        "/index.html",
    ])

    public init(settings: FocusSettings = .defaults) {
        self.settings = settings
    }

    public func entry(for entry: FocusEntry? = nil) -> FocusEntry {
        entry ?? settings.defaultEntry
    }

    public func entryRoute(for entry: FocusEntry? = nil) -> AppRoute {
        switch self.entry(for: entry) {
        case .dynamic, .search:
            return .dynamicFeed
        }
    }

    public func decision(for url: URL) -> Decision {
        guard settings.redirectEnabled else {
            return .allow
        }

        guard
            let host = url.host?.lowercased(),
            Self.homepageHosts.contains(host),
            Self.homepagePaths.contains(url.path)
        else {
            return .allow
        }

        return .redirect(entry())
    }

    public func redirectTarget(for url: URL) -> FocusEntry? {
        guard case let .redirect(target) = decision(for: url) else {
            return nil
        }

        return target
    }
}
