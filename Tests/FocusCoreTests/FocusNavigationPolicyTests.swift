import FocusCore
import Foundation
import Testing

struct FocusNavigationPolicyTests {
    @Test
    func canonicalizesDynamicDetailToDesktopOpusPage() {
        let url = URL(string: "https://t.bilibili.com/123456789")!

        #expect(
            FocusNavigationPolicy.canonicalWebURL(for: url).absoluteString
                == "https://www.bilibili.com/opus/123456789"
        )
    }

    @Test
    func canonicalizesMobileOpusPageToDesktopHost() {
        let url = URL(string: "https://m.bilibili.com/opus/987654321")!

        #expect(
            FocusNavigationPolicy.canonicalWebURL(for: url).absoluteString
                == "https://www.bilibili.com/opus/987654321"
        )
    }
}
