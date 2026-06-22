#if canImport(UIKit)
import SwiftUI
import WebKit

struct FocusWebVideoPlayerContainer: UIViewRepresentable {
    let url: URL
    @Binding var isPlaying: Bool
    @Binding var playbackRate: Float
    let onCoordinatorReady: ((Coordinator) -> Void)?

    init(url: URL, isPlaying: Binding<Bool>, playbackRate: Binding<Float>, onCoordinatorReady: ((Coordinator) -> Void)? = nil) {
        self.url = url
        _isPlaying = isPlaying
        _playbackRate = playbackRate
        self.onCoordinatorReady = onCoordinatorReady
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(isPlaying: $isPlaying, playbackRate: $playbackRate)
        onCoordinatorReady?(coordinator)
        return coordinator
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black

        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }

        context.coordinator.webView = webView

        // 加载播放器页面
        let request = URLRequest(url: url)
        webView.load(request)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // 如果 URL 改变了，重新加载
        if webView.url?.absoluteString != url.absoluteString {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }

    @MainActor
    class Coordinator: NSObject {
        @Binding var isPlaying: Bool
        @Binding var playbackRate: Float
        weak var webView: WKWebView?

        init(isPlaying: Binding<Bool>, playbackRate: Binding<Float>) {
            _isPlaying = isPlaying
            _playbackRate = playbackRate
        }

        func togglePlayback() {
            guard let webView else { return }

            let script = """
            (function() {
              var video = document.querySelector('video');
              if (video) {
                if (video.paused) {
                  video.play();
                } else {
                  video.pause();
                }
              }
            })();
            """

            webView.evaluateJavaScript(script) { [weak self] _, error in
                if let error {
                    print("[WebVideoPlayer] togglePlayback error: \(error)")
                } else {
                    self?.isPlaying.toggle()
                }
            }
        }

        func setPlaybackRate(_ rate: Float) {
            guard let webView else { return }

            let script = """
            (function() {
              var video = document.querySelector('video');
              if (video) {
                video.playbackRate = \(rate);
              }
            })();
            """

            webView.evaluateJavaScript(script) { [weak self] _, error in
                if let error {
                    print("[WebVideoPlayer] setPlaybackRate error: \(error)")
                } else {
                    self?.playbackRate = rate
                }
            }
        }
    }
}
#endif
