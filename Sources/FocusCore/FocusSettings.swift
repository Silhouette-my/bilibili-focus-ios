import Foundation

public struct FocusSettings: Codable, Equatable, Sendable {
    public static let storageKey = "focus.settings"
    public static let defaults = FocusSettings()

    public var redirectEnabled: Bool
    public var playerMaskEnabled: Bool
    public var searchMaskEnabled: Bool
    public var dynamicMaskEnabled: Bool
    public var debugMode: Bool
    public var defaultEntry: FocusEntry
    public var themeMode: FocusThemeMode
    public var dynamicVisibleKinds: Set<FocusDynamicFilterKind>
    public var perAuthorDynamicFilters: [String: Set<FocusDynamicFilterKind>]

    public init(
        redirectEnabled: Bool = true,
        playerMaskEnabled: Bool = true,
        searchMaskEnabled: Bool = true,
        dynamicMaskEnabled: Bool = true,
        debugMode: Bool = false,
        defaultEntry: FocusEntry = .dynamic,
        themeMode: FocusThemeMode = .system,
        dynamicVisibleKinds: Set<FocusDynamicFilterKind> = Set(FocusDynamicFilterKind.allCases),
        perAuthorDynamicFilters: [String: Set<FocusDynamicFilterKind>] = [:]
    ) {
        self.redirectEnabled = redirectEnabled
        self.playerMaskEnabled = playerMaskEnabled
        self.searchMaskEnabled = searchMaskEnabled
        self.dynamicMaskEnabled = dynamicMaskEnabled
        self.debugMode = debugMode
        self.defaultEntry = defaultEntry
        self.themeMode = themeMode
        self.dynamicVisibleKinds = dynamicVisibleKinds
        self.perAuthorDynamicFilters = perAuthorDynamicFilters
    }

    public static func load(from userDefaults: UserDefaults) -> FocusSettings {
        guard
            let data = userDefaults.data(forKey: storageKey),
            let settings = try? JSONDecoder().decode(FocusSettings.self, from: data)
        else {
            return .defaults
        }

        return settings
    }

    public func save(to userDefaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else {
            return
        }

        userDefaults.set(data, forKey: Self.storageKey)
    }
}

public enum FocusDynamicFilterKind: String, Codable, CaseIterable, Hashable, Sendable {
    case all
    case video
    case articleLike

    public var title: String {
        switch self {
        case .all:
            return "综合"
        case .video:
            return "视频"
        case .articleLike:
            return "图文"
        }
    }
}

public enum FocusThemeMode: String, Codable, CaseIterable, Hashable, Sendable {
    case system
    case light
    case dark

    public var title: String {
        switch self {
        case .system:
            return "跟随系统"
        case .light:
            return "浅色"
        case .dark:
            return "深色"
        }
    }
}
