import Foundation

public struct FocusFeature: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable {
        case prune
        case repair
    }

    public enum SettingKey: String, Codable, Sendable {
        case redirectEnabled
        case playerMaskEnabled
        case searchMaskEnabled
        case dynamicMaskEnabled
        case debugMode
    }

    public let featureId: String
    public let requiredSelectors: [String]
    public let optionalSelectors: [String]
    public let action: Action
    public let css: String
    public let script: String?
    public let settingKey: SettingKey?

    public init(
        featureId: String,
        requiredSelectors: [String] = [],
        optionalSelectors: [String] = [],
        action: Action,
        css: String,
        script: String? = nil,
        settingKey: SettingKey? = nil
    ) {
        self.featureId = featureId
        self.requiredSelectors = requiredSelectors
        self.optionalSelectors = optionalSelectors
        self.action = action
        self.css = css
        self.script = script
        self.settingKey = settingKey
    }
}
