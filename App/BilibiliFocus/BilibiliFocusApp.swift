#if canImport(UIKit)
import SwiftUI
import UIKit

@main
struct BilibiliFocusApp: App {
    init() {
        configureNavigationBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            FocusBrowserView()
                .tint(Color(red: 0.984, green: 0.447, blue: 0.600)) // Bilibili pink
        }
    }

    private func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemThinMaterial)
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.14)
        appearance.shadowColor = UIColor.black.withAlphaComponent(0.05)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]

        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        if #available(iOS 15.0, *) {
            navigationBar.compactScrollEdgeAppearance = appearance
        }
    }
}
#endif
