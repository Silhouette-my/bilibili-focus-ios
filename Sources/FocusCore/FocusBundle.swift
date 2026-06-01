import Foundation

enum FocusBundle {
    static let module: Bundle = {
        #if SWIFT_PACKAGE
        return .module
        #else
        let candidates: [Bundle] = [
            Bundle(for: BundleToken.self),
            .main,
        ]

        for bundle in candidates {
            if bundle.url(forResource: "focus-runtime", withExtension: "js") != nil {
                return bundle
            }
        }

        return Bundle(for: BundleToken.self)
        #endif
    }()
}

private final class BundleToken: NSObject {}
