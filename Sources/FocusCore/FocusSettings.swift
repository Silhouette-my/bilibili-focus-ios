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

    public init(
        redirectEnabled: Bool = true,
        playerMaskEnabled: Bool = true,
        searchMaskEnabled: Bool = true,
        dynamicMaskEnabled: Bool = true,
        debugMode: Bool = false,
        defaultEntry: FocusEntry = .dynamic
    ) {
        self.redirectEnabled = redirectEnabled
        self.playerMaskEnabled = playerMaskEnabled
        self.searchMaskEnabled = searchMaskEnabled
        self.dynamicMaskEnabled = dynamicMaskEnabled
        self.debugMode = debugMode
        self.defaultEntry = defaultEntry
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
