#if canImport(UIKit)
import SwiftUI

@main
struct BilibiliFocusApp: App {
    var body: some Scene {
        WindowGroup {
            FocusBrowserView()
        }
        .tint(Color(red: 0.984, green: 0.447, blue: 0.600)) // Bilibili pink
    }
}
#endif
