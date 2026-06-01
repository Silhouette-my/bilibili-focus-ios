import FocusCore
import Foundation
import Testing

struct FocusRouterTests {
    @Test
    func homepageRedirectUsesDefaultEntry() {
        let router = FocusRouter(
            settings: FocusSettings(
                redirectEnabled: true,
                defaultEntry: .search
            )
        )

        let decision = router.decision(for: URL(string: "https://www.bilibili.com/")!)
        #expect(decision == .redirect(FocusEntry.search))
    }

    @Test
    func homepageRedirectDisabledAllowsNavigation() {
        let router = FocusRouter(
            settings: FocusSettings(
                redirectEnabled: false,
                defaultEntry: .search
            )
        )

        #expect(router.decision(for: URL(string: "https://m.bilibili.com/")!) == .allow)
    }

    @Test
    func nonHomepageDoesNotRedirect() {
        let router = FocusRouter(settings: .defaults)
        #expect(router.decision(for: URL(string: "https://t.bilibili.com/")!) == .allow)
    }

    @Test
    func entryRouteUsesNativeDynamicFeed() {
        let router = FocusRouter(
            settings: FocusSettings(
                redirectEnabled: true,
                defaultEntry: .search
            )
        )

        #expect(router.entryRoute() == .dynamicFeed)
    }
}
