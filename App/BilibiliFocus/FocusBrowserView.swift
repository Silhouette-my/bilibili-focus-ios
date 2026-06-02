#if canImport(UIKit)
import FocusCore
import ImageIO
import SwiftUI
import UIKit
import WebKit

struct FocusBrowserView: View {
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
            .padding(.bottom, bottomChromeContentInset(safeAreaBottom: FocusWindowMetrics.safeAreaBottom))
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.showsBrowserBackButton {
                        Button {
                            viewModel.handleBrowserBack()
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
        }
    }

    private var isDynamicRouteActive: Bool {
        if case .dynamicFeed = viewModel.route {
            return true
        }
        return false
    }

    private var isSearchRouteActive: Bool {
        if case .searchResults = viewModel.route {
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
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Rectangle()
                            .fill(Color.white.opacity(0.03))
                    }
                    .ignoresSafeArea(edges: .bottom)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color(red: 0.95, green: 0.965, blue: 0.985).opacity(0.035),
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
                                Color.white.opacity(0.0),
                                Color.white.opacity(0.05),
                                Color.white.opacity(0.05),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .blur(radius: 18)
                    .ignoresSafeArea(edges: .bottom)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 24)
                    .ignoresSafeArea(edges: .bottom)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.035),
                                Color.white.opacity(0.07)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: safeAreaBottom + 22)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .blur(radius: 10)
                    .ignoresSafeArea(edges: .bottom)

                Rectangle()
                    .fill(Color.black.opacity(0.035))
                    .frame(height: 0.5)
            }
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
                title: "登录",
                systemImage: "person.crop.circle.fill",
                isSelected: viewModel.activePrimaryTab == .login
            ) {
                viewModel.openLogin()
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
            .foregroundStyle(Color(red: 0.18, green: 0.21, blue: 0.27))
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
                    ? Color(red: 0.28, green: 0.56, blue: 1.0)
                    : Color(red: 0.55, green: 0.58, blue: 0.63)
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
                object-fit: cover;
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
                LazyVGrid(columns: coverColumns, spacing: 10) {
                    ForEach(Array(card.coverURLs.enumerated()), id: \.offset) { item in
                        let url = item.element
                        FocusRemoteImage(url: url, referer: card.targetURL.absoluteString) { phase in
                            switch phase {
                            case let .success(image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                FocusRemoteImageWebFallback(url: url, referer: card.targetURL.absoluteString)
                            case .empty:
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(uiColor: .secondarySystemFill))
                                    ProgressView()
                                }
                            }
                        }
                        .frame(height: coverHeight(for: card.coverURLs.count, index: item.offset))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
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
    }

    private var coverColumns: [GridItem] {
        let count = card.coverURLs.count
        let columnCount = count == 1 ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: columnCount)
    }

    private func coverHeight(for count: Int, index _: Int) -> CGFloat {
        count == 1 ? 220 : 148
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
            .background(Color.accentColor.opacity(0.12))
            .foregroundStyle(Color.accentColor)
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
        .foregroundStyle(accented ? Color.accentColor : .secondary)
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
                    .foregroundStyle(selectedFilter == filter ? Color.accentColor : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(selectedFilter == filter ? Color.accentColor.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .overlay {
                        Capsule()
                            .stroke(selectedFilter == filter ? Color.accentColor.opacity(0.22) : Color.clear, lineWidth: 1)
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
        VStack(alignment: .leading, spacing: 0) {
            FocusSearchCover(
                url: item.coverURL,
                referer: item.targetURL.absoluteString,
                height: 104,
                badgeText: item.badgeText,
                cornerRadius: 12
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 44, alignment: .topLeading)

                Text(item.subtitle.isEmpty ? " " : item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: 16, alignment: .topLeading)

                Text(item.metadataText.isEmpty ? " " : item.metadataText)
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
        VStack(alignment: .leading, spacing: 0) {
            FocusSearchCover(
                url: item.coverURL,
                referer: item.targetURL.absoluteString,
                height: 104,
                badgeText: item.badgeText,
                cornerRadius: 12
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 44, alignment: .topLeading)

                Text(item.subtitle.isEmpty ? " " : item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: 16, alignment: .topLeading)

                Text(item.metadataText.isEmpty ? " " : item.metadataText)
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
