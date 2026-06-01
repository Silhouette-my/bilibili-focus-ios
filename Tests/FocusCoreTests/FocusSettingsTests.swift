import FocusCore
import Foundation
import Testing

struct FocusSettingsTests {
    @Test
    func defaultsMatchExpectedContract() {
        let settings = FocusSettings.defaults

        #expect(settings.redirectEnabled)
        #expect(settings.playerMaskEnabled)
        #expect(settings.searchMaskEnabled)
        #expect(settings.dynamicMaskEnabled)
        #expect(!settings.debugMode)
        #expect(settings.defaultEntry == .dynamic)
    }

    @Test
    func settingsPersistAndReload() {
        let suiteName = "FocusSettingsTests.settingsPersistAndReload"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = FocusSettings(
            redirectEnabled: false,
            playerMaskEnabled: false,
            searchMaskEnabled: true,
            dynamicMaskEnabled: false,
            debugMode: true,
            defaultEntry: .search
        )

        settings.save(to: defaults)

        #expect(FocusSettings.load(from: defaults) == settings)
    }
}
