#if canImport(UIKit)
import FocusCore
import SwiftUI
import UIKit
import WebKit

struct FocusWebView: UIViewRepresentable {
    @ObservedObject var viewModel: FocusBrowserViewModel
    @ObservedObject var settingsStore: FocusSettingsStore

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = FocusUserAgent.mobileSafari()
        webView.allowsBackForwardNavigationGestures = false
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.installScripts(on: webView, settings: settingsStore.settings)
        viewModel.attach(
            webView: webView,
            reconfigureScripts: { [weak coordinator = context.coordinator] webView, settings in
                coordinator?.installScripts(on: webView, settings: settings)
            },
            prepareForURL: { [weak coordinator = context.coordinator] webView, url in
                coordinator?.prepare(webView: webView, for: url)
            }
        )
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastAppliedSettings != settingsStore.settings {
            context.coordinator.installScripts(on: webView, settings: settingsStore.settings)
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let viewModel: FocusBrowserViewModel
        fileprivate var lastAppliedSettings: FocusSettings?
        private var lastPreparedUsesDesktopMode = false

        init(viewModel: FocusBrowserViewModel) {
            self.viewModel = viewModel
        }

        func prepare(webView: WKWebView, for url: URL) {
            let useDesktopMode = FocusUserAgent.shouldUseDesktopMode(for: url)
            lastPreparedUsesDesktopMode = useDesktopMode
            webView.customUserAgent = useDesktopMode ? FocusUserAgent.desktopSafari() : FocusUserAgent.mobileSafari()
            webView.configuration.defaultWebpagePreferences.preferredContentMode = useDesktopMode ? .desktop : .mobile
        }

        func installScripts(on webView: WKWebView, settings: FocusSettings) {
            let controller = webView.configuration.userContentController
            controller.removeAllUserScripts()
            controller.removeScriptMessageHandler(forName: "getConfig")
            controller.removeScriptMessageHandler(forName: "logDebug")
            controller.add(self, name: "getConfig")
            controller.add(self, name: "logDebug")

            if let documentStart = try? FocusScriptBuilder.makeUserScript(for: .documentStart, settings: settings) {
                controller.addUserScript(
                    WKUserScript(
                        source: documentStart,
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: true
                    )
                )
            }

            if let documentEnd = try? FocusScriptBuilder.makeUserScript(for: .documentEnd, settings: settings) {
                controller.addUserScript(
                    WKUserScript(
                        source: documentEnd,
                        injectionTime: .atDocumentEnd,
                        forMainFrameOnly: true
                    )
                )
            }

            lastAppliedSettings = settings
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "getConfig":
                guard let webView = viewModel.webView else { return }
                let data = try? JSONEncoder().encode(viewModel.settingsStore.settings)
                let configJSON = data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
                webView.evaluateJavaScript("window.__FOCUS_CONFIG__ = \(configJSON);")
            case "logDebug":
                print("[Focus Debug]", message.body)
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            viewModel.updateNavigationState(from: webView)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            viewModel.beginNavigation(to: webView.url)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            viewModel.updateNavigationState(from: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            viewModel.handleNavigationFailure(failingURL: webView.url)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            viewModel.handleNavigationFailure(failingURL: webView.url)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            viewModel.updateNavigationState(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard
                navigationAction.targetFrame?.isMainFrame != false,
                let url = navigationAction.request.url
            else {
                decisionHandler(.allow)
                return
            }

            if let entry = viewModel.entryRedirect(for: url) {
                decisionHandler(.cancel)
                viewModel.requestNativeEntry(entry)
                return
            }

            switch viewModel.navigationDecision(for: url, currentURL: webView.url) {
            case .allow:
                viewModel.logNavigationDecision(
                    url: url,
                    currentURL: webView.url,
                    navigationType: navigationAction.navigationType,
                    decision: "allow"
                )
                viewModel.noteUpcomingNavigation(
                    to: url,
                    from: webView.url,
                    navigationType: navigationAction.navigationType
                )
                let desiredDesktopMode = FocusUserAgent.shouldUseDesktopMode(for: url)
                if desiredDesktopMode != lastPreparedUsesDesktopMode {
                    decisionHandler(.cancel)
                    prepare(webView: webView, for: url)
                    webView.load(URLRequest(url: url))
                    return
                }

                decisionHandler(.allow)
            case .cancel:
                viewModel.logNavigationDecision(
                    url: url,
                    currentURL: webView.url,
                    navigationType: navigationAction.navigationType,
                    decision: "cancel"
                )
                decisionHandler(.cancel)
            case let .redirect(target):
                if target == url {
                    viewModel.logNavigationDecision(
                        url: url,
                        currentURL: webView.url,
                        navigationType: navigationAction.navigationType,
                        decision: "allow-same-as-target"
                    )
                    decisionHandler(.allow)
                    return
                }

                viewModel.logNavigationDecision(
                    url: url,
                    currentURL: webView.url,
                    navigationType: navigationAction.navigationType,
                    decision: "redirect:\(target.absoluteString)"
                )
                viewModel.noteUpcomingNavigation(
                    to: target,
                    from: webView.url,
                    navigationType: navigationAction.navigationType
                )
                decisionHandler(.cancel)
                prepare(webView: webView, for: target)
                webView.load(URLRequest(url: target))
            }
        }
    }
}
#endif
