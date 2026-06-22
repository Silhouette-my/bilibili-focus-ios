#if canImport(UIKit)
import SwiftUI
import UIKit
import WebKit

enum FocusSharedDesign {
    static let primary = Color(red: 0.984, green: 0.447, blue: 0.600)
    static let videoControlForeground = Color(uiColor: .label)
    static let chromeButtonBackground = Color(uiColor: .secondarySystemBackground)
    static let chromePanelBackground = Color(uiColor: .systemBackground)
}

struct FocusStateView: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FocusLoginRequiredView: View {
    let title: String
    let message: String
    let reloadTitle: String
    let reloadAction: () -> Void
    let loginAction: () -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 16) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 12) {
                        Button(reloadTitle, action: reloadAction)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)

                        Button("去登录", action: loginAction)
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom + 132, 156))
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

enum FocusRemoteImagePhase {
    case empty
    case success(Image)
    case failure
}

struct FocusRemoteImage<Content: View>: View {
    let url: URL?
    let referer: String
    let content: (FocusRemoteImagePhase) -> Content

    @StateObject private var loader = FocusRemoteImageLoader()

    init(
        url: URL?,
        referer: String = "https://www.bilibili.com/",
        @ViewBuilder content: @escaping (FocusRemoteImagePhase) -> Content
    ) {
        self.url = url
        self.referer = referer
        self.content = content
    }

    var body: some View {
        content(displayPhase)
            .task(id: url) {
                await loader.load(url: url, referer: referer)
            }
    }

    private var displayPhase: FocusRemoteImagePhase {
        if case .empty = loader.phase,
           let url,
           let cachedImage = FocusRemoteImageLoader.cachedUIImage(for: url)
        {
            return .success(Image(uiImage: cachedImage))
        }

        return loader.phase
    }
}

struct FocusRemoteImageWebFallback: UIViewRepresentable {
    let url: URL?
    let referer: String
    var objectFit: String = "cover"

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = true
        webView.backgroundColor = UIColor.secondarySystemBackground
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.isUserInteractionEnabled = false
        webView.customUserAgent = FocusUserAgent.mobileSafari()
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let url else {
            webView.loadHTMLString("", baseURL: nil)
            return
        }

        let escapedURL = url.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        let html = """
        <!doctype html>
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
              html, body {
                margin: 0;
                padding: 0;
                width: 100%;
                height: 100%;
                overflow: hidden;
                background: transparent;
              }

              body {
                display: flex;
                align-items: stretch;
                justify-content: stretch;
              }

              img {
                width: 100%;
                height: 100%;
                object-fit: \(objectFit);
                display: block;
              }
            </style>
          </head>
          <body>
            <img src="\(escapedURL)" loading="eager" referrerpolicy="origin">
          </body>
        </html>
        """

        let baseURL = URL(string: referer) ?? URL(string: "https://www.bilibili.com/")
        webView.loadHTMLString(html, baseURL: baseURL)
    }
}

@MainActor
final class FocusRemoteImageLoader: ObservableObject {
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 192
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 48 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "FocusRemoteImageCache"
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    @Published fileprivate var phase: FocusRemoteImagePhase = .empty

    private var currentURL: URL?
    private var task: Task<Void, Never>?

    deinit {
        task?.cancel()
    }

    func load(url: URL?, referer: String) async {
        task?.cancel()
        currentURL = url

        guard let url else {
            phase = .failure
            return
        }

        if let cachedImage = Self.cache.object(forKey: url as NSURL) {
            phase = .success(Image(uiImage: cachedImage))
            return
        }

        phase = .empty

        task = Task {
            do {
                let uiImage = try await Self.fetchImage(from: url, preferredReferer: referer)
                guard !Task.isCancelled, self.currentURL == url else {
                    return
                }

                Self.cache.setObject(uiImage, forKey: url as NSURL, cost: Self.cacheCost(for: uiImage))
                phase = .success(Image(uiImage: uiImage))
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                phase = .failure
            }
        }

        await task?.value
    }

    static func cachedUIImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    static func prefetch(urls: [URL], referer: String) {
        Task(priority: .utility) { @MainActor in
            for url in urls {
                if cache.object(forKey: url as NSURL) != nil {
                    continue
                }

                guard let image = try? await fetchImage(from: url, preferredReferer: referer) else {
                    continue
                }

                cache.setObject(image, forKey: url as NSURL, cost: cacheCost(for: image))
            }
        }
    }

    private static func fetchImage(from url: URL, preferredReferer: String) async throws -> UIImage {
        let cookieHeader = await cookieHeaderValue()
        let referers = [preferredReferer, "https://t.bilibili.com/", "https://www.bilibili.com/", ""]

        for referer in referers {
            for candidate in imageURLCandidates(for: url) {
                do {
                    var request = URLRequest(url: candidate)
                    request.timeoutInterval = 20
                    if !referer.isEmpty {
                        request.setValue(referer, forHTTPHeaderField: "Referer")
                    }
                    if let cookieHeader, !cookieHeader.isEmpty {
                        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
                    }
                    request.httpShouldHandleCookies = true
                    request.setValue(
                        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                        forHTTPHeaderField: "User-Agent"
                    )
                    request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Origin")
                    request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
                    request.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")

                    let (data, response) = try await session.data(for: request)
                    guard
                        let httpResponse = response as? HTTPURLResponse,
                        (200 ..< 300).contains(httpResponse.statusCode),
                        let image = decodeImage(from: data)
                    else {
                        continue
                    }

                    return image
                } catch {
                    continue
                }
            }
        }

        throw URLError(.cannotDecodeContentData)
    }

    private static func cacheCost(for image: UIImage) -> Int {
        guard let cgImage = image.cgImage else {
            return Int(image.size.width * image.size.height * image.scale * image.scale)
        }

        return cgImage.bytesPerRow * cgImage.height
    }

    private static func decodeImage(from data: Data) -> UIImage? {
        if let image = UIImage(data: data) {
            return image
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    private static func imageURLCandidates(for url: URL) -> [URL] {
        let absoluteString = url.absoluteString
        let cleaned = absoluteString.replacingOccurrences(of: "http://", with: "https://")
        let stripped = cleaned.replacingOccurrences(of: #"@[^/?#]+"#, with: "", options: .regularExpression)
        let preferred = stripped.contains("@") ? stripped : cleaned
        return [preferred, stripped, cleaned]
            .compactMap(URL.init(string:))
            .reduce(into: [URL]()) { partialResult, candidate in
                if !partialResult.contains(candidate) {
                    partialResult.append(candidate)
                }
            }
    }

    private static func cookieHeaderValue() async -> String? {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        guard !cookies.isEmpty else {
            return nil
        }
        return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
    }
}

struct FocusVideoControlButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let systemImage: String
    var title: String? = nil
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: title == nil ? 0 : 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                if let title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .foregroundStyle(FocusSharedDesign.videoControlForeground)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(FocusSharedDesign.chromeButtonBackground.opacity(colorScheme == .dark ? 0.86 : 0.92))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct FocusVisualEffectBlur: UIViewRepresentable {
    let style: UIBlurEffect.Style

    func makeUIView(context _: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ view: UIVisualEffectView, context _: Context) {
        view.effect = UIBlurEffect(style: style)
        view.clipsToBounds = true
        view.backgroundColor = .clear
    }
}
#endif
