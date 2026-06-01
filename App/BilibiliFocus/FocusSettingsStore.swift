#if canImport(UIKit)
import Combine
import FocusCore
import Foundation

@MainActor
final class FocusSettingsStore: ObservableObject {
    @Published var settings: FocusSettings {
        didSet {
            settings.save(to: userDefaults)
        }
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.settings = FocusSettings.load(from: userDefaults)
    }

    func reset() {
        settings = .defaults
    }
}
#endif
