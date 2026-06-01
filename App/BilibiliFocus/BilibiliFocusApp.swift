#if canImport(UIKit)
import SwiftUI

@main
struct BilibiliFocusApp: App {
    var body: some Scene {
        WindowGroup {
            FocusBrowserView()
        }
    }
}
#endif
