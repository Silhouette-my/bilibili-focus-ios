#if canImport(UIKit)
import FocusCore
import ImageIO
import SwiftUI
import UIKit
import WebKit

private enum FocusDesign {
    static let primary = Color(red: 0.984, green: 0.447, blue: 0.600) // Bilibili pink #FB7299
    static let primaryLight = primary.opacity(0.12)
    static let primaryStroke = primary.opacity(0.22)
    static let tabInactive = Color(red: 0.55, green: 0.58, blue: 0.63) // #8C94A1
    static let videoControlForeground = Color(red: 0.18, green: 0.21, blue: 0.27) // #2E3645
}

struct FocusBrowserView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var settingsStore: FocusSettingsStore
    @StateObject private var viewModel: FocusAppViewModel

    init() {
        let store = FocusSettingsStore()
        _settingsStore = StateObject(wrappedValue: store)
        _viewModel = StateObject(wrappedValue: FocusAppViewModel(settingsStore: store))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                browserLayer
                nativeContentLayer
            }
            .padding(
                .bottom,
                viewModel.isBrowserActive
                    ? bottomChromeContentInset(safeAreaBottom: FocusWindowMetrics.safeAreaBottom)
                    : 0
            )
            .overlay(alignment: .leading) {
                if viewModel.isBrowserActive {
                    FocusEdgeSwipeBackArea {
                        viewModel.handleBrowserBack()
                    }
                }
            }
            .overlay(alignment: .bottom) {
                bottomChrome(safeAreaBottom: FocusWindowMetrics.safeAreaBottom)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .ignoresSafeArea(edges: .bottom)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.showsBackButton {
                        Button {
                            viewModel.handleTopLevelBack()
                        } label: {
                            Label("返回", systemImage: "chevron.left")
                        }
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text(viewModel.navigationTitle)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if viewModel.isBrowserActive {
                            Button {
                                viewModel.reloadCurrent()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                        }

                        Button {
                            viewModel.showSettings = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showSettings) {
                FocusSettingsView(settingsStore: settingsStore)
            }
            .sheet(isPresented: $viewModel.showSearch) {
                FocusSearchEntryView(
                    keyword: $viewModel.searchKeyword,
                    onSubmit: viewModel.submitSearch
                )
            }
            .onAppear {
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                viewModel.browserViewModel.handleDeviceOrientationChange(UIDevice.current.orientation)
            }
            .onDisappear {
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                viewModel.browserViewModel.handleDeviceOrientationChange(UIDevice.current.orientation)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                viewModel.handleAppDidBecomeActive()
            }
            .task {
                viewModel.handleLaunchEntryIfNeeded()
            }
        }
    }

    private var browserLayer: some View {
        Group {
            if viewModel.hasInstantiatedBrowser {
                FocusWebView(viewModel: viewModel.browserViewModel, settingsStore: settingsStore)
                    .opacity(viewModel.isBrowserActive ? 1 : 0)
                    .allowsHitTesting(viewModel.isBrowserActive)
                    .accessibilityHidden(!viewModel.isBrowserActive)
            }
        }
    }

    @ViewBuilder
    private var nativeContentLayer: some View {
        ZStack {
            FocusDynamicFeedView(
                viewModel: viewModel.dynamicFeedViewModel,
                searchPrompt: viewModel.searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "搜索视频、UP主、直播"
                    : viewModel.searchKeyword,
                onOpenCard: { card in
                    viewModel.open(card: card)
                },
                onOpenLogin: viewModel.openLogin,
                onSearch: {
                    viewModel.showSearch = true
                }
            )
            .opacity(isDynamicRouteActive ? 1 : 0)
            .allowsHitTesting(isDynamicRouteActive)
            .accessibilityHidden(!isDynamicRouteActive)

            FocusSearchResultsView(
                viewModel: viewModel.searchResultsViewModel,
                onOpenItem: { item in
                    viewModel.open(searchItem: item)
                },
                onOpenPreview: { preview in
                    viewModel.open(searchPreview: preview)
                },
                onEditQuery: {
                    viewModel.showSearch = true
                }
            )
            .opacity(isSearchRouteActive ? 1 : 0)
            .allowsHitTesting(isSearchRouteActive)
            .accessibilityHidden(!isSearchRouteActive)

            FocusMyView(
                viewModel: viewModel.myViewModel,
                onOpenLogin: viewModel.openLogin,
                onOpenHistory: viewModel.openHistory,
                onOpenVideo: { url in
                    viewModel.openMyVideo(url)
                }
            )
            .opacity(isMyRouteActive ? 1 : 0)
            .allowsHitTesting(isMyRouteActive)
            .accessibilityHidden(!isMyRouteActive)

            FocusHistoryView(
                viewModel: viewModel.historyViewModel,
                onOpenVideo: { url in
                    viewModel.openMyVideo(url)
                }
            )
            .opacity(isHistoryRouteActive ? 1 : 0)
            .allowsHitTesting(isHistoryRouteActive)
            .accessibilityHidden(!isHistoryRouteActive)

            FocusUserSpaceView(
                viewModel: viewModel.userSpaceViewModel,
                onOpenVideo: { url in
                    viewModel.openOpusRelatedURL(url)
                },
                onOpenCollection: { collection in
                    viewModel.openUserCollection(collection)
                },
                onOpenArticle: { url in
                    viewModel.openOpusRelatedURL(url)
                }
            )
            .opacity(isUserSpaceRouteActive ? 1 : 0)
            .allowsHitTesting(isUserSpaceRouteActive)
            .accessibilityHidden(!isUserSpaceRouteActive)

            FocusUserCollectionView(
                viewModel: viewModel.userCollectionViewModel,
                onOpenVideo: { url in
                    viewModel.openOpusRelatedURL(url)
                }
            )
            .opacity(isUserCollectionRouteActive ? 1 : 0)
            .allowsHitTesting(isUserCollectionRouteActive)
            .accessibilityHidden(!isUserCollectionRouteActive)

            FocusArticleView(
                viewModel: viewModel.articleViewModel,
                onOpenUser: { mid in
                    guard let url = URL(string: "https://space.bilibili.com/\(mid)") else {
                        return
                    }
                    viewModel.openNativeUserSpace(url)
                }
            )
            .opacity(isArticleRouteActive ? 1 : 0)
            .allowsHitTesting(isArticleRouteActive)
            .accessibilityHidden(!isArticleRouteActive)

            FocusOpusDetailView(
                viewModel: viewModel.opusDetailViewModel,
                onOpenURL: { url in
                    viewModel.openOpusRelatedURL(url)
                }
            )
            .opacity(isOpusRouteActive ? 1 : 0)
            .allowsHitTesting(isOpusRouteActive)
            .accessibilityHidden(!isOpusRouteActive)
        }
    }

    private var isDynamicRouteActive: Bool {
        if case .dynamicFeed = viewModel.route {
            return true
        }
        return false
    }

    private var isSearchRouteActive: Bool {
        if case .searchResults(_) = viewModel.route {
            return true
        }
        return false
    }

    private var isMyRouteActive: Bool {
        if case .my = viewModel.route {
            return true
        }
        return false
    }

    private var isHistoryRouteActive: Bool {
        if case .history = viewModel.route {
            return true
        }
        return false
    }

    private var isUserSpaceRouteActive: Bool {
        if case .userSpace(_) = viewModel.route {
            return true
        }
        return false
    }

    private var isUserCollectionRouteActive: Bool {
        if case .userCollection(_) = viewModel.route {
            return true
        }
        return false
    }

    private var isArticleRouteActive: Bool {
        if case .article(_) = viewModel.route {
            return true
        }
        return false
    }

    private var isOpusRouteActive: Bool {
        if case .opus(_) = viewModel.route {
            return true
        }
        return false
    }

    private func bottomChrome(safeAreaBottom: CGFloat) -> some View {
        let tabBottomPadding = bottomTabBarPadding(safeAreaBottom: safeAreaBottom)
        let tabTopPadding = viewModel.isBrowserActive && viewModel.browserViewModel.showsNativeVideoControls ? 2.0 : 3.0

        return VStack(spacing: 0) {
            if viewModel.isBrowserActive, viewModel.browserViewModel.showsNativeVideoControls {
                videoControls
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }

            primaryTabBar
                .padding(.horizontal, 18)
                .padding(.top, tabTopPadding)
                .padding(.bottom, tabBottomPadding)
        }
        .background {
            FocusBottomChromeBackground(
                safeAreaBottom: safeAreaBottom,
                isDarkMode: colorScheme == .dark
            )
        }
        .compositingGroup()
        .frame(maxWidth: .infinity, alignment: .bottom)
        .shadow(color: .black.opacity(0.028), radius: 10, y: -1)
    }

    private func bottomChromeContentInset(safeAreaBottom: CGFloat) -> CGFloat {
        let tabInset = 54 + bottomTabBarPadding(safeAreaBottom: safeAreaBottom)
        if viewModel.isBrowserActive, viewModel.browserViewModel.showsNativeVideoControls {
            return tabInset + 74
        }
        return tabInset
    }

    private func bottomTabBarPadding(safeAreaBottom: CGFloat) -> CGFloat {
        max(0, safeAreaBottom * 0.03)
    }

    private var primaryTabBar: some View {
        HStack(spacing: 2) {
            FocusPrimaryTabButton(
                title: "动态",
                systemImage: "square.stack.3d.up.fill",
                isSelected: viewModel.activePrimaryTab == .dynamic
            ) {
                viewModel.open(.dynamic)
            }

            FocusPrimaryTabButton(
                title: "搜索",
                systemImage: "magnifyingglass",
                isSelected: viewModel.activePrimaryTab == .search
            ) {
                viewModel.showSearch = true
            }

            FocusPrimaryTabButton(
                title: "我的",
                systemImage: "person.crop.circle.fill",
                isSelected: viewModel.activePrimaryTab == .my
            ) {
                viewModel.openMy()
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity)
    }

    private var videoControls: some View {
        HStack(spacing: 8) {
            FocusVideoControlButton(
                systemImage: "playpause.fill",
                accessibilityLabel: "播放或暂停"
            ) {
                viewModel.browserViewModel.togglePlayback()
            }

            FocusVideoControlButton(
                systemImage: "speedometer",
                title: "倍速",
                accessibilityLabel: "切换倍速"
            ) {
                viewModel.browserViewModel.cyclePlaybackRate()
            }

            FocusVideoControlButton(
                systemImage: "arrow.up.left.and.arrow.down.right",
                accessibilityLabel: "切换全屏"
            ) {
                if viewModel.browserViewModel.isImmersiveVideo {
                    viewModel.browserViewModel.exitFullscreen()
                } else {
                    viewModel.browserViewModel.requestFullscreen()
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
    }
}

private struct FocusEdgeSwipeBackArea: View {
    let onBack: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        guard value.translation.width > 80, abs(value.translation.height) < 80 else {
                            return
                        }

                        onBack()
                    }
            )
    }
}

private struct FocusVideoControlButton: View {
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
            .foregroundStyle(FocusDesign.videoControlForeground)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.9))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct FocusPrimaryTabButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))

                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(
                isSelected
                    ? FocusDesign.primary
                    : FocusDesign.tabInactive
            )
            .padding(.top, 5)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private enum FocusWindowMetrics {
    static var safeAreaBottom: CGFloat {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }),
            let window = windowScene.windows.first(where: \.isKeyWindow) ?? windowScene.windows.first
        else {
            return 0
        }

        return window.safeAreaInsets.bottom
    }
}

private struct FocusBottomChromeBackground: View {
    let safeAreaBottom: CGFloat
    let isDarkMode: Bool

    var body: some View {
        ZStack(alignment: .top) {
            FocusVisualEffectBlur(style: isDarkMode ? .systemChromeMaterialDark : .systemThinMaterialLight)
                .ignoresSafeArea(edges: .bottom)

            Rectangle()
                .fill(isDarkMode ? Color.white.opacity(0.02) : Color.white.opacity(0.16))
                .ignoresSafeArea(edges: .bottom)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            isDarkMode ? Color.white.opacity(0.10) : Color.white.opacity(0.30),
                            isDarkMode ? Color.white.opacity(0.02) : Color.white.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea(edges: .bottom)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            isDarkMode ? Color.white.opacity(0.03) : Color.white.opacity(0.13)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: safeAreaBottom + 30)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            isDarkMode ? Color.white.opacity(0.018) : Color.white.opacity(0.075),
                            isDarkMode ? Color.white.opacity(0.018) : Color.white.opacity(0.075),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .blur(radius: 18)
                .ignoresSafeArea(edges: .bottom)

            Rectangle()
                .fill(isDarkMode ? Color.white.opacity(0.12) : Color.white.opacity(0.52))
                .frame(height: 0.5)
        }
    }
}

private struct FocusVisualEffectBlur: UIViewRepresentable {
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

private enum FocusRemoteImagePhase {
    case empty
    case success(Image)
    case failure
}

private struct FocusRemoteImage<Content: View>: View {
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

private struct FocusRemoteImageWebFallback: UIViewRepresentable {
    let url: URL?
    let referer: String
    var objectFit: String = "cover"

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.backgroundColor = .clear
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
private final class FocusRemoteImageLoader: ObservableObject {
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

    private static func cacheCost(for image: UIImage) -> Int {
        guard let cgImage = image.cgImage else {
            return Int(image.size.width * image.size.height * image.scale * image.scale)
        }

        return cgImage.bytesPerRow * cgImage.height
    }

    private static func decodeImage(from data: Data) -> UIImage? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil)
        else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1280,
        ]

        if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return UIImage(cgImage: thumbnail)
        }

        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    private static func cookieHeaderValue() async -> String? {
        let cookies = await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }

        guard !cookies.isEmpty else {
            return nil
        }

        return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
    }

    private static func imageURLCandidates(for url: URL) -> [URL] {
        var candidates: [URL] = [url]
        let absoluteString = url.absoluteString
        let isHDSlbImage = (url.host?.lowercased().contains("hdslb.com") == true)
        var squareFallbackURL: URL?

        if absoluteString.lowercased().hasPrefix("http://"),
           let secureURL = URL(string: "https://" + absoluteString.dropFirst("http://".count))
        {
            candidates.insert(secureURL, at: 0)
        }

        if let atIndex = absoluteString.lastIndex(of: "@"),
           let slashIndex = absoluteString[absoluteString.startIndex...].lastIndex(of: "/"),
           atIndex > slashIndex,
           let strippedURL = URL(string: String(absoluteString[..<atIndex]))
        {
            candidates.append(strippedURL)
        }

        if isHDSlbImage,
           !absoluteString.contains("@"),
           let optimizedURL = URL(string: absoluteString + "@480w_480h_1c.webp")
        {
            squareFallbackURL = optimizedURL
        }

        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           components.query != nil
        {
            components.query = nil
            if let querylessURL = components.url {
                candidates.append(querylessURL)
            }
        }

        let lowercasedPath = url.path.lowercased()
        if lowercasedPath.hasSuffix(".avif") || lowercasedPath.hasSuffix(".webp") {
            let baseString: String
            if let dotIndex = absoluteString.lastIndex(of: ".") {
                baseString = String(absoluteString[..<dotIndex])
            } else {
                baseString = absoluteString
            }

            ["jpg", "jpeg", "png"].forEach { `extension` in
                if let candidate = URL(string: "\(baseString).\(`extension`)") {
                    candidates.append(candidate)
                }
            }
        }

        if let squareFallbackURL {
            candidates.append(squareFallbackURL)
        }

        let secureVariants = candidates.compactMap { candidate -> URL? in
            let raw = candidate.absoluteString
            guard raw.lowercased().hasPrefix("http://") else {
                return nil
            }
            return URL(string: "https://" + String(raw.dropFirst("http://".count)))
        }
        if !secureVariants.isEmpty {
            candidates.insert(contentsOf: secureVariants, at: 0)
        }

        var deduplicated: [URL] = []
        var seen = Set<String>()
        for candidate in candidates {
            guard seen.insert(candidate.absoluteString).inserted else {
                continue
            }
            deduplicated.append(candidate)
        }
        return deduplicated
    }
}

private struct FocusDynamicFeedView: View {
    @ObservedObject var viewModel: FocusDynamicFeedViewModel
    let searchPrompt: String
    let onOpenCard: (DynamicCard) -> Void
    let onOpenLogin: () -> Void
    let onSearch: () -> Void

    var body: some View {
        content
            .task {
                viewModel.loadIfNeeded()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("加载关注动态…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .loaded(cards):
            if cards.isEmpty {
                FocusStateView(
                    title: "暂无可显示的关注动态",
                    message: "当前页面没有拿到内容，稍后可以再刷新一次。",
                    buttonTitle: "重新加载",
                    action: viewModel.reload
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        FocusSearchQueryButton(
                            title: searchPrompt,
                            inactiveAccessorySystemImage: "chevron.right",
                            action: onSearch
                        )

                        ForEach(cards) { card in
                            Button {
                                onOpenCard(card)
                            } label: {
                                FocusDynamicCardView(card: card)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                viewModel.loadMoreIfNeeded(currentCardID: card.id)
                            }
                        }

                        if viewModel.isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 126)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .refreshable {
                    await viewModel.refresh()
                }
                .task(id: cards.map(\.id)) {
                    prefetchImages(for: cards)
                }
            }

        case let .loginRequired(message):
            VStack(spacing: 12) {
                FocusStateView(
                    title: "需要登录",
                    message: "\(message)\n先点“去登录”，网页登录完成后再回来刷新。",
                    buttonTitle: "重新检测登录态",
                    action: viewModel.reload
                )

                Button("去登录") {
                    onOpenLogin()
                }
                .buttonStyle(.borderedProminent)
            }

        case let .failed(message):
            FocusStateView(
                title: "动态加载失败",
                message: message,
                buttonTitle: "重试",
                action: viewModel.reload
            )
        }
    }

    private func prefetchImages(for cards: [DynamicCard]) {
        for card in cards.prefix(8) {
            let urls = ([card.author.avatarURL] + Array(card.coverURLs.prefix(2))).compactMap { $0 }
            guard !urls.isEmpty else {
                continue
            }
            FocusRemoteImageLoader.prefetch(urls: urls, referer: card.targetURL.absoluteString)
        }
    }
}

private struct FocusDynamicCardView: View {
    let card: DynamicCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                avatar

                VStack(alignment: .leading, spacing: 4) {
                    Text(card.author.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        if !card.publishTime.isEmpty {
                            Text(card.publishTime)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        FocusKindBadge(kind: card.kind)
                    }
                }

                Spacer(minLength: 0)
            }

            if !card.text.isEmpty {
                Text(card.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
            }

            if !card.coverURLs.isEmpty {
                if let firstURL = card.coverURLs.first, card.coverURLs.count == 1 {
                    FocusDynamicMediaCover(
                        url: firstURL,
                        referer: card.targetURL.absoluteString,
                        height: 176
                    )
                } else {
                    LazyVGrid(columns: coverColumns, spacing: 10) {
                        ForEach(Array(card.coverURLs.enumerated()), id: \.offset) { item in
                            FocusDynamicMediaCover(
                                url: item.element,
                                referer: card.targetURL.absoluteString,
                                height: coverHeight(for: card.coverURLs.count, index: item.offset)
                            )
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var coverColumns: [GridItem] {
        let count = card.coverURLs.count
        let columnCount = count == 1 ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: columnCount)
    }

    private func coverHeight(for count: Int, index _: Int) -> CGFloat {
        count == 1 ? 176 : 132
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarURL = card.author.avatarURL {
            FocusRemoteImage(url: avatarURL, referer: card.targetURL.absoluteString) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    FocusRemoteImageWebFallback(url: avatarURL, referer: card.targetURL.absoluteString)
                case .empty:
                    Circle()
                        .fill(Color(uiColor: .secondarySystemFill))
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(Color(uiColor: .secondarySystemFill))
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                )
        }
    }
}

private struct FocusDynamicMediaCover: View {
    let url: URL?
    let referer: String
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            FocusRemoteImage(url: url, referer: referer) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                case .failure:
                    FocusRemoteImageWebFallback(
                        url: url,
                        referer: referer,
                        objectFit: "cover"
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                case .empty:
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemFill))
                        ProgressView()
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color(uiColor: .secondarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct FocusKindBadge: View {
    let kind: DynamicCard.Kind

    private var title: String {
        switch kind {
        case .text:
            return "文本"
        case .image:
            return "图文"
        case .video:
            return "视频"
        case .articleLike:
            return "专栏"
        }
    }

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(FocusDesign.primary.opacity(0.12))
            .foregroundStyle(FocusDesign.primary)
            .clipShape(Capsule())
    }
}

private struct FocusStateView: View {
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

private struct FocusSearchResultsView: View {
    @ObservedObject var viewModel: FocusSearchResultsViewModel
    let onOpenItem: (SearchResultItem) -> Void
    let onOpenPreview: (SearchResultItem.PreviewVideo) -> Void
    let onEditQuery: () -> Void

    var body: some View {
        content
            .background(Color(uiColor: .systemGroupedBackground))
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            FocusStateView(
                title: "还没有搜索内容",
                message: "点底栏里的“搜索”输入关键词。",
                buttonTitle: "开始搜索",
                action: onEditQuery
            )

        case .loading:
            ProgressView("加载搜索结果…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .loaded(sections):
            if sections.isEmpty {
                FocusStateView(
                    title: "没有找到结果",
                    message: "换个关键词试试，或者稍后再搜一次。",
                    buttonTitle: "重新搜索",
                    action: onEditQuery
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        FocusSearchQueryButton(
                            title: viewModel.currentQuery?.keyword ?? "搜索",
                            isVideoSortEnabled: viewModel.selectedFilter == .video,
                            selectedVideoSort: viewModel.selectedVideoSort,
                            availableVideoSortOptions: viewModel.availableVideoSortOptions,
                            onSelectVideoSort: viewModel.selectVideoSort,
                            action: onEditQuery
                        )

                        FocusSearchFilterStrip(
                            filters: viewModel.availableFilters,
                            selectedFilter: viewModel.selectedFilter,
                            onSelect: viewModel.selectFilter
                        )

                        ForEach(sections) { section in
                            FocusSearchSectionView(
                                section: section,
                                isLoadingMore: viewModel.isLoadingMore && section.filter == .video,
                                onOpenItem: onOpenItem,
                                onOpenPreview: onOpenPreview,
                                onLoadMoreTrigger: { item in
                                    viewModel.loadMoreIfNeeded(currentItemID: item.id, in: section)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 126)
                }
                .refreshable {
                    await viewModel.refresh()
                }
                .task(id: prefetchSignature(for: sections)) {
                    prefetchImages(for: sections)
                }
            }

        case let .failed(message):
            FocusStateView(
                title: "搜索加载失败",
                message: message,
                buttonTitle: "重试",
                action: viewModel.reload
            )
        }
    }

    private func prefetchSignature(for sections: [SearchResultSection]) -> String {
        sections
            .flatMap(\.items)
            .prefix(12)
            .map(\.id)
            .joined(separator: "|")
    }

    private func prefetchImages(for sections: [SearchResultSection]) {
        for item in sections.flatMap(\.items).prefix(10) {
            let urls = ([item.coverURL, item.avatarURL] + item.previews.prefix(3).map(\.coverURL)).compactMap { $0 }
            guard !urls.isEmpty else {
                continue
            }

            FocusRemoteImageLoader.prefetch(
                urls: urls,
                referer: item.targetURL.absoluteString
            )
        }
    }
}

private struct FocusSearchQueryButton: View {
    let title: String
    let isVideoSortEnabled: Bool
    let selectedVideoSort: SearchVideoSortOption
    let availableVideoSortOptions: [SearchVideoSortOption]
    let onSelectVideoSort: (SearchVideoSortOption) -> Void
    var inactiveAccessorySystemImage: String = "slider.horizontal.3"
    let action: () -> Void

    init(
        title: String,
        isVideoSortEnabled: Bool = false,
        selectedVideoSort: SearchVideoSortOption = .default,
        availableVideoSortOptions: [SearchVideoSortOption] = [],
        onSelectVideoSort: @escaping (SearchVideoSortOption) -> Void = { _ in },
        inactiveAccessorySystemImage: String = "slider.horizontal.3",
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isVideoSortEnabled = isVideoSortEnabled
        self.selectedVideoSort = selectedVideoSort
        self.availableVideoSortOptions = availableVideoSortOptions
        self.onSelectVideoSort = onSelectVideoSort
        self.inactiveAccessorySystemImage = inactiveAccessorySystemImage
        self.action = action
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1, height: 24)

            if isVideoSortEnabled {
                Menu {
                    ForEach(availableVideoSortOptions) { option in
                        Button {
                            onSelectVideoSort(option)
                        } label: {
                            if option == selectedVideoSort {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    filterLabel(accented: selectedVideoSort != .default)
                }
                .buttonStyle(.plain)
            } else {
                inactiveAccessoryLabel
                    .opacity(0.48)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func filterLabel(accented: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .semibold))

            if isVideoSortEnabled {
                Text(selectedVideoSort.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(accented ? FocusDesign.primary : .secondary)
    }

    private var inactiveAccessoryLabel: some View {
        Image(systemName: inactiveAccessorySystemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

private struct FocusSearchFilterStrip: View {
    let filters: [SearchResultFilter]
    let selectedFilter: SearchResultFilter
    let onSelect: (SearchResultFilter) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(filters) { filter in
                    Button(filter.title) {
                        onSelect(filter)
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selectedFilter == filter ? FocusDesign.primary : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(selectedFilter == filter ? FocusDesign.primary.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .overlay {
                        Capsule()
                            .stroke(selectedFilter == filter ? FocusDesign.primary.opacity(0.22) : Color.clear, lineWidth: 1)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct FocusSearchSectionView: View {
    let section: SearchResultSection
    let isLoadingMore: Bool
    let onOpenItem: (SearchResultItem) -> Void
    let onOpenPreview: (SearchResultItem.PreviewVideo) -> Void
    let onLoadMoreTrigger: (SearchResultItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 2)

            switch section.filter {
            case .video:
                LazyVGrid(columns: videoColumns, spacing: 10) {
                    ForEach(section.items) { item in
                        Button {
                            onOpenItem(item)
                        } label: {
                            FocusSearchVideoCard(item: item)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            onLoadMoreTrigger(item)
                        }
                    }
                }

            case .users:
                LazyVStack(spacing: 10) {
                    ForEach(section.items) { item in
                        FocusSearchUserCard(
                            item: item,
                            onOpenItem: onOpenItem,
                            onOpenPreview: onOpenPreview
                        )
                    }
                }

            case .live:
                LazyVGrid(columns: videoColumns, spacing: 10) {
                    ForEach(section.items) { item in
                        Button {
                            onOpenItem(item)
                        } label: {
                            FocusSearchLiveCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }

            case .bangumi, .film:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(section.items) { item in
                            Button {
                                onOpenItem(item)
                            } label: {
                                FocusSearchMediaCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }

            case .all:
                EmptyView()
            }

            if isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
    }

    private var videoColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
    }
}

private struct FocusSearchVideoCard: View {
    let item: SearchResultItem

    var body: some View {
        FocusTwoColumnVideoCard(content: .init(item: item))
    }
}

private struct FocusSearchUserCard: View {
    let item: SearchResultItem
    let onOpenItem: (SearchResultItem) -> Void
    let onOpenPreview: (SearchResultItem.PreviewVideo) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                onOpenItem(item)
            } label: {
                HStack(spacing: 12) {
                    avatar

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if !item.subtitle.isEmpty {
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }

                        if !item.metadataText.isEmpty {
                            Text(item.metadataText)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            if !item.previews.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(item.previews) { preview in
                            Button {
                                onOpenPreview(preview)
                            } label: {
                                FocusSearchPreviewCard(preview: preview)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarURL = item.avatarURL {
            FocusRemoteImage(url: avatarURL, referer: item.targetURL.absoluteString) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    FocusRemoteImageWebFallback(url: avatarURL, referer: item.targetURL.absoluteString)
                case .empty:
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
        }
    }
}

private struct FocusSearchPreviewCard: View {
    let preview: SearchResultItem.PreviewVideo

    private let cardWidth: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FocusSearchCover(
                url: preview.coverURL,
                referer: preview.targetURL.absoluteString,
                height: 76,
                badgeText: preview.badgeText,
                cornerRadius: 12
            )
            .frame(width: cardWidth)

            Text(preview.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: cardWidth, alignment: .leading)

            if !preview.metadataText.isEmpty {
                Text(preview.metadataText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: cardWidth, alignment: .leading)
    }
}

private struct FocusSearchLiveCard: View {
    let item: SearchResultItem

    var body: some View {
        FocusTwoColumnVideoCard(content: .init(item: item))
    }
}

private struct FocusTwoColumnVideoCardContent {
    let title: String
    let subtitle: String
    let metadataText: String
    let badgeText: String
    let coverURL: URL?
    let referer: String

    init(item: SearchResultItem) {
        title = item.title
        subtitle = item.subtitle
        metadataText = item.metadataText
        badgeText = item.badgeText
        coverURL = item.coverURL
        referer = item.targetURL.absoluteString
    }

    init(video: FocusUserSpaceVideo) {
        title = video.title
        let combinedSubtitle: String
        switch (video.playText.isEmpty, video.publishText.isEmpty) {
        case (false, false):
            combinedSubtitle = "\(video.playText) · \(video.publishText)"
        case (false, true):
            combinedSubtitle = video.playText
        case (true, false):
            combinedSubtitle = video.publishText
        case (true, true):
            combinedSubtitle = ""
        }
        subtitle = combinedSubtitle
        metadataText = ""
        badgeText = video.durationText
        coverURL = video.coverURL
        referer = video.targetURL?.absoluteString ?? "https://space.bilibili.com/"
    }

    init(history item: FocusMyHistoryItem) {
        title = item.title
        subtitle = item.authorName
        metadataText = FocusHistoryCardFormatter.metadataText(for: item)
        badgeText = FocusHistoryCardFormatter.durationText(progress: item.progress, duration: item.duration)
        coverURL = item.coverURL
        referer = item.videoURL?.absoluteString ?? "https://www.bilibili.com/"
    }
}

private enum FocusHistoryCardFormatter {
    static func metadataText(for item: FocusMyHistoryItem) -> String {
        let parts = [progressText(for: item), viewAtText(item.viewAt)]
            .filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    static func durationText(progress: Int64, duration: Int64) -> String {
        guard duration > 0 else {
            return ""
        }
        let effectiveProgress = progress > 0 ? min(progress, duration) : duration
        return "\(formatDuration(effectiveProgress))/\(formatDuration(duration))"
    }

    private static func progressText(for item: FocusMyHistoryItem) -> String {
        guard item.duration > 0 else {
            return ""
        }
        if item.progress <= 0 {
            return "未开始"
        }
        if item.progress >= max(0, item.duration - 5) {
            return "已看完"
        }
        return "看到 \(formatDuration(item.progress))"
    }

    private static func viewAtText(_ timestamp: Int64) -> String {
        guard timestamp > 0 else {
            return ""
        }

        let interval = Int64(Date().timeIntervalSince1970) - timestamp
        switch interval {
        case ..<0:
            return ""
        case 0 ..< 3600:
            return "\(max(1, interval / 60)) 分钟前"
        case 3600 ..< 86_400:
            return "\(interval / 3600) 小时前"
        case 86_400 ..< 604_800:
            return "\(interval / 86_400) 天前"
        default:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
        }
    }

    private static func formatDuration(_ seconds: Int64) -> String {
        guard seconds > 0 else {
            return "00:00"
        }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%lld:%02lld:%02lld", hours, minutes, remainingSeconds)
        }
        return String(format: "%02lld:%02lld", minutes, remainingSeconds)
    }
}

private struct FocusTwoColumnVideoCard: View {
    let content: FocusTwoColumnVideoCardContent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FocusSearchCover(
                url: content.coverURL,
                referer: content.referer,
                height: 104,
                badgeText: content.badgeText,
                cornerRadius: 12
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(content.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 44, alignment: .topLeading)

                Text(content.subtitle.isEmpty ? " " : content.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: 16, alignment: .topLeading)

                Text(content.metadataText.isEmpty ? " " : content.metadataText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: 14, alignment: .topLeading)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct FocusSearchMediaCard: View {
    let item: SearchResultItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FocusSearchCover(
                url: item.coverURL,
                referer: item.targetURL.absoluteString,
                height: 186,
                badgeText: item.badgeText,
                cornerRadius: 14
            )
            .frame(width: 138)

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if !item.subtitle.isEmpty {
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !item.metadataText.isEmpty || !item.descriptionText.isEmpty {
                Text(!item.metadataText.isEmpty ? item.metadataText : item.descriptionText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(width: 138, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private struct FocusSearchCover: View {
    let url: URL?
    let referer: String
    let height: CGFloat
    let badgeText: String
    let cornerRadius: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let url {
                    FocusRemoteImage(url: url, referer: referer) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            FocusRemoteImageWebFallback(url: url, referer: referer)
                        case .empty:
                            ZStack {
                                RoundedRectangle(cornerRadius: 0)
                                    .fill(Color(uiColor: .tertiarySystemFill))
                                ProgressView()
                            }
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Color(uiColor: .tertiarySystemFill))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()

            if !badgeText.isEmpty {
                Text(badgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.62))
                    .clipShape(Capsule())
                    .padding(8)
            }
        }
        .background(Color(uiColor: .tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct FocusSearchEntryView: View {
    @Binding var keyword: String
    let onSubmit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("关键词") {
                    TextField("输入搜索内容", text: $keyword)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            onSubmit()
                        }
                }

                Section {
                    Button("搜索") {
                        onSubmit()
                    }
                    .disabled(keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("搜索")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .task {
                isTextFieldFocused = true
            }
        }
    }
}

private struct FocusMyView: View {
    @ObservedObject var viewModel: FocusMyViewModel
    let onOpenLogin: () -> Void
    let onOpenHistory: () -> Void
    let onOpenVideo: (URL) -> Void

    var body: some View {
        content
            .task {
                viewModel.loadIfNeeded()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("加载个人页面…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loginRequired:
            VStack(spacing: 12) {
                FocusStateView(
                    title: "需要登录",
                    message: "登录后即可查看你的播放历史和收藏夹。",
                    buttonTitle: "重新检测登录态",
                    action: viewModel.reload
                )

                Button("去登录") {
                    onOpenLogin()
                }
                .buttonStyle(.borderedProminent)
            }

        case let .failed(message):
            FocusStateView(
                title: "个人页面加载失败",
                message: message,
                buttonTitle: "重试",
                action: viewModel.reload
            )

        case let .loaded(page):
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FocusMyProfileCard(profile: page.profile)

                    if !page.history.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Text("播放历史")
                                    .font(.headline.weight(.semibold))

                                Spacer(minLength: 0)

                                Button("更多") {
                                    onOpenHistory()
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(FocusDesign.primary)
                            }
                            .padding(.horizontal, 2)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(page.history) { item in
                                        Button {
                                            guard let url = item.videoURL else {
                                                return
                                            }
                                            onOpenVideo(url)
                                        } label: {
                                            FocusMyHistoryCard(item: item)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    if !page.folders.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("收藏夹")
                                .font(.headline.weight(.semibold))
                                .padding(.horizontal, 2)

                            VStack(spacing: 10) {
                                ForEach(page.folders) { folder in
                                    FocusMyFolderRow(folder: folder)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 132)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .task(id: page.history.map(\.id).joined(separator: "|")) {
                prefetchAssets(for: page)
            }
            .refreshable {
                viewModel.reload()
            }
        }
    }

    private func prefetchAssets(for page: FocusMyPage) {
        let historyURLs = page.history.compactMap(\.coverURL)
        if !historyURLs.isEmpty {
            FocusRemoteImageLoader.prefetch(urls: historyURLs, referer: "https://www.bilibili.com/")
        }

        let folderURLs = page.folders.compactMap(\.coverURL)
        if !folderURLs.isEmpty {
            FocusRemoteImageLoader.prefetch(urls: folderURLs, referer: "https://www.bilibili.com/")
        }
    }
}

private struct FocusMyProfileCard: View {
    let profile: FocusMyProfile

    var body: some View {
        VStack(spacing: 14) {
            FocusRemoteImage(url: profile.avatarURL, referer: "https://space.bilibili.com/\(profile.mid)") { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                case .empty:
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay(ProgressView())
                }
            }
            .frame(width: 78, height: 78)
            .clipShape(Circle())

            VStack(spacing: 6) {
                Text(profile.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                Text("LV\(profile.level)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FocusDesign.primary)
            }

            HStack(spacing: 24) {
                FocusMyStat(value: formatCount(profile.following), label: "关注")
                FocusMyStat(value: formatCount(profile.followers), label: "粉丝")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func formatCount(_ value: Int64) -> String {
        switch value {
        case 100_000_000...:
            return String(format: "%.1f亿", Double(value) / 100_000_000).replacingOccurrences(of: ".0", with: "")
        case 10_000...:
            return String(format: "%.1f万", Double(value) / 10_000).replacingOccurrences(of: ".0", with: "")
        default:
            return "\(value)"
        }
    }
}

private struct FocusMyStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FocusMyHistoryCard: View {
    let item: FocusMyHistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                FocusRemoteImage(url: item.coverURL, referer: item.videoURL?.absoluteString ?? "https://www.bilibili.com/") { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    case .empty:
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                            .overlay(ProgressView())
                    }
                }
                .frame(width: 176, height: 102)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if item.duration > 0 {
                    Text(FocusHistoryCardFormatter.durationText(progress: item.progress, duration: item.duration))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.62))
                        .clipShape(Capsule())
                        .padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(item.authorName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 176, alignment: .leading)
    }
}

private struct FocusMyFolderRow: View {
    let folder: FocusMyFolder

    var body: some View {
        HStack(spacing: 12) {
            FocusRemoteImage(url: folder.coverURL, referer: "https://www.bilibili.com/") { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                case .empty:
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay(ProgressView())
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(folder.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text("\(folder.mediaCount) 个内容")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private struct FocusHistoryView: View {
    @ObservedObject var viewModel: FocusHistoryViewModel
    let onOpenVideo: (URL) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        content
            .task {
                viewModel.loadIfNeeded()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("加载播放历史…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loginRequired:
            FocusStateView(
                title: "需要登录",
                message: "登录后即可查看完整播放历史。",
                buttonTitle: "重新检测登录态",
                action: viewModel.reload
            )

        case let .failed(message):
            FocusStateView(
                title: "播放历史加载失败",
                message: message,
                buttonTitle: "重试",
                action: viewModel.reload
            )

        case let .loaded(items):
            if items.isEmpty {
                FocusStateView(
                    title: "暂无播放历史",
                    message: "开始播放视频后，这里会显示最近看过的内容。",
                    buttonTitle: "刷新",
                    action: viewModel.reload
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(items) { item in
                            Button {
                                guard let url = item.videoURL else {
                                    return
                                }
                                onOpenVideo(url)
                            } label: {
                                FocusHistoryGridCard(item: item)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                viewModel.loadMoreIfNeeded(currentItemID: item.id)
                            }
                        }

                        if viewModel.isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 6)
                                .gridCellColumns(columns.count)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 132)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .task(id: items.map(\.id).joined(separator: "|")) {
                    prefetchAssets(items)
                }
                .refreshable {
                    viewModel.reload()
                }
            }
        }
    }

    private func prefetchAssets(_ items: [FocusMyHistoryItem]) {
        let urls = items.prefix(20).compactMap(\.coverURL)
        guard !urls.isEmpty else {
            return
        }
        FocusRemoteImageLoader.prefetch(urls: urls, referer: "https://www.bilibili.com/")
    }
}

private struct FocusHistoryGridCard: View {
    let item: FocusMyHistoryItem

    var body: some View {
        FocusTwoColumnVideoCard(content: .init(history: item))
    }
}

private struct FocusUserSpaceView: View {
    fileprivate enum ContentSection: String, CaseIterable, Hashable {
        case videos = "视频"
        case collections = "合集"
        case articles = "专栏"
    }

    @ObservedObject var viewModel: FocusUserSpaceViewModel
    let onOpenVideo: (URL) -> Void
    let onOpenCollection: (FocusUserSpaceCollection) -> Void
    let onOpenArticle: (URL) -> Void
    @State private var selectedSection: ContentSection = .videos

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        content
            .task {
                viewModel.loadIfNeeded()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("加载 UP 空间…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .failed(message):
            FocusStateView(
                title: "UP 主空间加载失败",
                message: message,
                buttonTitle: "重试",
                action: viewModel.reload
            )

        case let .loaded(page):
            let sections = availableSections(for: page)
            let activeSection = sections.contains(selectedSection) ? selectedSection : (sections.first ?? .videos)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FocusUserSpaceHeaderCard(profile: page.profile)

                    if !sections.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionTitle("内容")
                            FocusUserSpaceSectionPicker(sections: sections, selection: $selectedSection)

                            switch activeSection {
                            case .videos:
                                LazyVGrid(columns: columns, spacing: 10) {
                                    ForEach(page.videos) { video in
                                        Button {
                                            guard let url = video.targetURL else {
                                                return
                                            }
                                            onOpenVideo(url)
                                        } label: {
                                            FocusUserSpaceVideoCard(video: video)
                                        }
                                        .buttonStyle(.plain)
                                        .onAppear {
                                            viewModel.loadMoreIfNeeded(currentVideoID: video.id)
                                        }
                                    }
                                }

                                if viewModel.isLoadingMoreVideos {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding(.top, 4)
                                }

                            case .collections:
                                VStack(spacing: 10) {
                                    ForEach(page.collections) { collection in
                                        Button {
                                            onOpenCollection(collection)
                                        } label: {
                                            FocusUserSpaceCollectionCard(collection: collection, fixedWidth: nil)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                            case .articles:
                                VStack(spacing: 10) {
                                    ForEach(page.articles) { article in
                                        Button {
                                            onOpenArticle(article.targetURL)
                                        } label: {
                                            FocusUserSpaceArticleRow(article: article)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    if page.videos.isEmpty, page.collections.isEmpty, page.articles.isEmpty {
                        FocusStateView(
                            title: "内容较少",
                            message: "这个 UP 主空间暂时没有可展示的公开视频、合集或专栏。",
                            buttonTitle: "刷新",
                            action: viewModel.reload
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 132)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .task(id: page.profile.mid) {
                prefetchAssets(for: page)
                if !sections.contains(selectedSection) {
                    selectedSection = sections.first ?? .videos
                }
            }
            .refreshable {
                viewModel.reload()
            }
        }
    }

    private func availableSections(for page: FocusUserSpacePage) -> [ContentSection] {
        var sections: [ContentSection] = []
        if !page.videos.isEmpty {
            sections.append(.videos)
        }
        if !page.collections.isEmpty {
            sections.append(.collections)
        }
        if !page.articles.isEmpty {
            sections.append(.articles)
        }
        return sections
    }

    private func sectionTitle(_ value: String) -> some View {
        Text(value)
            .font(.headline.weight(.semibold))
            .padding(.horizontal, 2)
    }

    private func prefetchAssets(for page: FocusUserSpacePage) {
        let referer = "https://space.bilibili.com/\(page.profile.mid)"
        let urls = (
            [page.profile.avatarURL]
                + page.videos.prefix(8).compactMap(\.coverURL)
                + page.collections.prefix(6).compactMap(\.coverURL)
                + page.articles.prefix(4).compactMap(\.coverURL)
        ).compactMap { $0 }

        guard !urls.isEmpty else {
            return
        }
        FocusRemoteImageLoader.prefetch(urls: urls, referer: referer)
    }
}

private struct FocusUserSpaceSectionPicker: View {
    let sections: [FocusUserSpaceView.ContentSection]
    @Binding var selection: FocusUserSpaceView.ContentSection

    var body: some View {
        HStack(spacing: 8) {
            ForEach(sections, id: \.self) { section in
                Button {
                    selection = section
                } label: {
                    Text(section.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection == section ? Color.white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    selection == section
                                        ? FocusDesign.primary
                                        : Color(uiColor: .secondarySystemGroupedBackground)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct FocusUserSpaceHeaderCard: View {
    let profile: FocusUserSpaceProfile

    var body: some View {
        VStack(spacing: 14) {
            FocusRemoteImage(url: profile.avatarURL, referer: "https://space.bilibili.com/\(profile.mid)") { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                case .empty:
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay(ProgressView())
                }
            }
            .frame(width: 82, height: 82)
            .clipShape(Circle())

            VStack(spacing: 6) {
                Text(profile.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text("LV\(profile.level)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FocusDesign.primary)

                if !profile.sign.isEmpty {
                    Text(profile.sign)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.top, 2)
                }
            }

            HStack(spacing: 18) {
                FocusUserSpaceStat(value: formatCount(profile.following), label: "关注")
                FocusUserSpaceStat(value: formatCount(profile.followers), label: "粉丝")
                FocusUserSpaceStat(value: "\(profile.videoCount)", label: "视频")
                FocusUserSpaceStat(value: "\(profile.articleCount)", label: "专栏")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func formatCount(_ value: Int64) -> String {
        switch value {
        case 100_000_000...:
            return String(format: "%.1f亿", Double(value) / 100_000_000).replacingOccurrences(of: ".0", with: "")
        case 10_000...:
            return String(format: "%.1f万", Double(value) / 10_000).replacingOccurrences(of: ".0", with: "")
        default:
            return "\(value)"
        }
    }
}

private struct FocusUserSpaceStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FocusUserSpaceVideoCard: View {
    let video: FocusUserSpaceVideo

    var body: some View {
        FocusTwoColumnVideoCard(content: .init(video: video))
    }
}

private struct FocusUserSpaceCollectionCard: View {
    let collection: FocusUserSpaceCollection
    var fixedWidth: CGFloat? = 260

    var body: some View {
        HStack(spacing: 12) {
            FocusRemoteImage(url: collection.coverURL, referer: "https://space.bilibili.com/") { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                case .empty:
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay(ProgressView())
                }
            }
            .frame(width: 78, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(collection.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(collection.subtitle)
                    .font(.caption)
                    .foregroundStyle(FocusDesign.primary)

                if !collection.description.isEmpty {
                    Text(collection.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(collection.badgeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(width: fixedWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private struct FocusUserCollectionView: View {
    @ObservedObject var viewModel: FocusUserCollectionViewModel
    let onOpenVideo: (URL) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        content
            .task {
                viewModel.loadIfNeeded()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("加载合集…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .failed(message):
            FocusStateView(
                title: "合集加载失败",
                message: message,
                buttonTitle: "重试",
                action: viewModel.reload
            )

        case let .loaded(page):
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FocusUserCollectionHeroCard(collection: page.collection)

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(page.videos) { video in
                            Button {
                                guard let url = video.targetURL else {
                                    return
                                }
                                onOpenVideo(url)
                            } label: {
                                FocusUserSpaceVideoCard(video: video)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                viewModel.loadMoreIfNeeded(currentVideoID: video.id)
                            }
                        }
                    }

                    if viewModel.isLoadingMoreVideos {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 132)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .refreshable {
                viewModel.reload()
            }
            .task(id: page.collection.id + "-\(page.videos.count)") {
                prefetchAssets(for: page)
            }
        }
    }

    private func prefetchAssets(for page: FocusUserCollectionPage) {
        let urls = ([page.collection.coverURL] + page.videos.prefix(10).compactMap(\.coverURL)).compactMap { $0 }
        guard !urls.isEmpty else {
            return
        }
        FocusRemoteImageLoader.prefetch(urls: urls, referer: "https://space.bilibili.com/\(page.collection.ownerMID)")
    }
}

private struct FocusUserCollectionHeroCard: View {
    let collection: FocusUserSpaceCollection

    var body: some View {
        HStack(spacing: 14) {
            FocusRemoteImage(url: collection.coverURL, referer: "https://space.bilibili.com/\(collection.ownerMID)") { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                case .empty:
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay(ProgressView())
                }
            }
            .frame(width: 110, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(collection.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(collection.subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FocusDesign.primary)

                if !collection.description.isEmpty {
                    Text(collection.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                } else {
                    Text(collection.badgeText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private struct FocusArticleView: View {
    @ObservedObject var viewModel: FocusArticleViewModel
    let onOpenUser: (Int64) -> Void

    var body: some View {
        content
            .task {
                viewModel.loadIfNeeded()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("加载专栏…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loginRequired:
            FocusStateView(
                title: "需要登录",
                message: "当前专栏需要登录后查看。",
                buttonTitle: "重新加载",
                action: viewModel.reload
            )

        case let .failed(message):
            FocusStateView(
                title: "专栏加载失败",
                message: message,
                buttonTitle: "重试",
                action: viewModel.reload
            )

        case let .loaded(page):
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if page.bannerURL != nil {
                        FocusRemoteImage(url: page.bannerURL, referer: "https://www.bilibili.com/read/cv\(page.cvid)") { phase in
                            switch phase {
                            case let .success(image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color(uiColor: .tertiarySystemFill))
                            case .empty:
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color(uiColor: .tertiarySystemFill))
                                    .overlay(ProgressView())
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16 / 9, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }

                    Text(page.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    FocusArticleAuthorCard(page: page, onOpenUser: onOpenUser)
                    FocusArticleStatsCard(stats: page.stats)

                    if !page.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(page.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(FocusDesign.primary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(FocusDesign.primary.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    if !page.htmlContent.isEmpty {
                        FocusArticleHTMLCard(htmlContent: page.htmlContent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 132)
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }
}

private struct FocusArticleAuthorCard: View {
    let page: FocusArticlePage
    let onOpenUser: (Int64) -> Void

    var body: some View {
        Button {
            guard page.author.mid > 0 else {
                return
            }
            onOpenUser(page.author.mid)
        } label: {
            HStack(spacing: 12) {
                FocusRemoteImage(url: page.author.avatarURL, referer: "https://space.bilibili.com/\(page.author.mid)") { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Circle()
                            .fill(Color(uiColor: .tertiarySystemFill))
                    case .empty:
                        Circle()
                            .fill(Color(uiColor: .tertiarySystemFill))
                            .overlay(ProgressView())
                    }
                }
                .frame(width: 46, height: 46)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(page.author.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if page.publishTime > 0 {
                        Text(formatDate(page.publishTime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }

    private func formatDate(_ seconds: Int64) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }
}

private struct FocusArticleStatsCard: View {
    let stats: FocusArticleStats

    var body: some View {
        HStack(spacing: 0) {
            FocusArticleStatItem(value: formatCount(stats.views), label: "阅读")
            FocusArticleStatItem(value: formatCount(stats.likes), label: "点赞")
            FocusArticleStatItem(value: formatCount(stats.coins), label: "硬币")
            FocusArticleStatItem(value: formatCount(stats.favorites), label: "收藏")
            FocusArticleStatItem(value: formatCount(stats.comments), label: "评论")
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func formatCount(_ value: Int64) -> String {
        switch value {
        case 100_000_000...:
            return String(format: "%.1f亿", Double(value) / 100_000_000).replacingOccurrences(of: ".0", with: "")
        case 10_000...:
            return String(format: "%.1f万", Double(value) / 10_000).replacingOccurrences(of: ".0", with: "")
        default:
            return "\(value)"
        }
    }
}

private struct FocusArticleStatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FocusArticleHTMLCard: View {
    let htmlContent: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var contentHeight: CGFloat = 1

    var body: some View {
        FocusArticleHTMLWebView(
            html: styledHTML,
            contentHeight: $contentHeight
        )
        .frame(height: max(contentHeight, 1))
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var styledHTML: String {
        let isDark = colorScheme == .dark
        let background = "transparent"
        let textColor = isDark ? "#E8ECF2" : "#1F2937"
        let secondaryColor = isDark ? "#A7B0BE" : "#5B6472"
        let linkColor = isDark ? "#FF9FBC" : "#FB7299"
        let codeBackground = isDark ? "#1A2230" : "#F4F6F9"
        let quoteBackground = isDark ? "#151C27" : "#F8FAFC"
        let borderColor = isDark ? "rgba(255,255,255,0.08)" : "rgba(15,23,42,0.08)"

        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
          <style>
            :root { color-scheme: \(isDark ? "dark" : "light"); }
            html, body {
              margin: 0;
              padding: 0;
              background: \(background);
              color: \(textColor);
              font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif;
              font-size: 17px;
              line-height: 1.72;
            }
            body { overflow-x: hidden; }
            article { width: 100%; box-sizing: border-box; }
            p, li, blockquote, pre { margin: 0 0 14px 0; }
            h1, h2, h3, h4 {
              color: \(textColor);
              margin: 22px 0 12px 0;
              line-height: 1.35;
            }
            a {
              color: \(linkColor);
              text-decoration: none;
            }
            img, video, iframe {
              display: block;
              width: 100%;
              max-width: 100%;
              height: auto;
              border-radius: 14px;
              overflow: hidden;
              margin: 14px 0;
            }
            blockquote {
              padding: 12px 14px;
              border-radius: 14px;
              background: \(quoteBackground);
              border: 1px solid \(borderColor);
              color: \(secondaryColor);
            }
            pre, code {
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            }
            pre {
              padding: 14px;
              border-radius: 14px;
              background: \(codeBackground);
              overflow-x: auto;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              margin: 14px 0;
              font-size: 15px;
            }
            th, td {
              padding: 8px 10px;
              border: 1px solid \(borderColor);
            }
          </style>
        </head>
        <body>
          <article>\(htmlContent)</article>
        </body>
        </html>
        """
    }
}

private struct FocusArticleHTMLWebView: UIViewRepresentable {
    let html: String
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else {
            context.coordinator.updateHeightIfNeeded(for: webView)
            return
        }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.bilibili.com/"))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var contentHeight: CGFloat
        var lastHTML = ""

        init(contentHeight: Binding<CGFloat>) {
            _contentHeight = contentHeight
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateHeightIfNeeded(for: webView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                self.updateHeightIfNeeded(for: webView)
            }
        }

        func updateHeightIfNeeded(for webView: WKWebView) {
            let script = "Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);"
            webView.evaluateJavaScript(script) { [weak self] result, _ in
                guard let self else {
                    return
                }
                let resolvedHeight: CGFloat?
                if let value = result as? Double {
                    resolvedHeight = CGFloat(value)
                } else if let value = result as? NSNumber {
                    resolvedHeight = CGFloat(truncating: value)
                } else {
                    resolvedHeight = nil
                }

                guard let resolvedHeight else {
                    return
                }
                DispatchQueue.main.async {
                    self.contentHeight = resolvedHeight
                }
            }
        }
    }
}

private struct FocusUserSpaceArticleRow: View {
    let article: FocusUserSpaceArticle

    var body: some View {
        HStack(spacing: 12) {
            if article.coverURL != nil {
                FocusRemoteImage(url: article.coverURL, referer: article.targetURL.absoluteString) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    case .empty:
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                            .overlay(ProgressView())
                    }
                }
                .frame(width: 96, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(article.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !article.summary.isEmpty {
                    Text(article.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                let meta = [article.viewText.isEmpty ? nil : "\(article.viewText)阅读", article.publishText]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                if !meta.isEmpty {
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private struct FocusOpusDetailView: View {
    @ObservedObject var viewModel: FocusOpusDetailViewModel
    let onOpenURL: (URL) -> Void

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("加载图文详情…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loginRequired:
            FocusStateView(
                title: "需要登录",
                message: "当前图文详情需要登录后才能查看。",
                buttonTitle: "重新加载",
                action: viewModel.reload
            )

        case let .failed(message):
            FocusStateView(
                title: "图文详情加载失败",
                message: message,
                buttonTitle: "重试",
                action: viewModel.reload
            )

        case let .loaded(page):
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FocusOpusAuthorCard(page: page, onOpenURL: onOpenURL)

                    ForEach(page.paragraphs) { paragraph in
                        FocusOpusParagraphCard(paragraph: paragraph)
                    }

                    if !page.comments.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("评论")
                                .font(.headline.weight(.semibold))
                                .padding(.horizontal, 2)

                            ForEach(Array(page.comments.enumerated()), id: \.offset) { item in
                                FocusOpusCommentCard(comment: item.element)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 132)
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }
}

private struct FocusOpusAuthorCard: View {
    let page: FocusOpusDetailPage
    let onOpenURL: (URL) -> Void

    var body: some View {
        Button {
            guard page.author.mid > 0,
                  let url = URL(string: "https://space.bilibili.com/\(page.author.mid)")
            else {
                return
            }
            onOpenURL(url)
        } label: {
            HStack(spacing: 12) {
                FocusRemoteImage(url: page.author.avatarURL, referer: "https://space.bilibili.com/\(page.author.mid)") { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Circle()
                            .fill(Color(uiColor: .tertiarySystemFill))
                            .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                    case .empty:
                        Circle()
                            .fill(Color(uiColor: .tertiarySystemFill))
                            .overlay(ProgressView())
                    }
                }
                .frame(width: 46, height: 46)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(page.author.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if !page.publishTime.isEmpty {
                        Text(page.publishTime)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct FocusOpusParagraphCard: View {
    let paragraph: FocusOpusParagraph

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(paragraph.blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .text(nodes):
                    FocusOpusRichText(nodes: nodes)
                case let .image(images):
                    FocusOpusImageGrid(images: images)
                case let .code(lang, content):
                    VStack(alignment: .leading, spacing: 8) {
                        if !lang.isEmpty {
                            Text(lang.uppercased())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(FocusDesign.primary)
                        }
                        Text(content)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private struct FocusOpusRichText: View {
    let nodes: [FocusOpusTextNode]

    var body: some View {
        combinedText
            .font(.body)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var combinedText: Text {
        nodes.reduce(Text("")) { partial, node in
            let rawText = node.emojiURL != nil && node.text.isEmpty ? "[表情]" : node.text
            let segment = Text(rawText)
                .fontWeight(node.bold ? .semibold : .regular)
                .foregroundColor(node.linkURL == nil ? .primary : FocusDesign.primary)
            return partial + segment
        }
    }
}

private struct FocusOpusImageGrid: View {
    let images: [FocusOpusImage]

    var body: some View {
        if images.count == 1, let image = images.first {
            FocusOpusImageTile(image: image)
        } else {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(images) { image in
                    FocusOpusImageTile(image: image)
                }
            }
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
    }
}

private struct FocusOpusImageTile: View {
    let image: FocusOpusImage

    var body: some View {
        FocusRemoteImage(url: image.url, referer: image.url?.absoluteString ?? "https://www.bilibili.com/") { phase in
            switch phase {
            case let .success(view):
                view
                    .resizable()
                    .scaledToFit()
            case .failure:
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
            case .empty:
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .overlay(ProgressView())
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(image.aspectRatio ?? 1, contentMode: .fit)
        .background(Color(uiColor: .tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct FocusOpusCommentCard: View {
    let comment: FocusNativeCommentPayload

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FocusRemoteImage(url: URL(string: comment.avatarURL), referer: "https://www.bilibili.com/") { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                case .empty:
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay(ProgressView())
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(comment.author)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FocusDesign.primary)

                Text(comment.content)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                let meta = [comment.timeText, comment.likeText, comment.replyText]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                if !meta.isEmpty {
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private struct FocusSettingsView: View {
    @ObservedObject var settingsStore: FocusSettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("入口") {
                    Picker("默认入口", selection: binding(\.defaultEntry)) {
                        ForEach(FocusEntry.allCases, id: \.self) { entry in
                            Text(entry.title).tag(entry)
                        }
                    }
                }

                Section("规则") {
                    Toggle("首页重定向", isOn: binding(\.redirectEnabled))
                    Toggle("动态详情页去干扰", isOn: binding(\.dynamicMaskEnabled))
                    Toggle("搜索结果页去干扰", isOn: binding(\.searchMaskEnabled))
                    Toggle("播放页去干扰", isOn: binding(\.playerMaskEnabled))
                }

                Section("高级") {
                    Toggle("调试日志", isOn: binding(\.debugMode))
                    Button("恢复默认设置", role: .destructive) {
                        settingsStore.reset()
                    }
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<FocusSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { settingsStore.settings[keyPath: keyPath] = $0 }
        )
    }
}
#endif
