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
                FocusDynamicFeedView(
                    viewModel: viewModel.dynamicFeedViewModel,
                    onOpenCard: { card in
                        viewModel.open(card: card)
                    },
                    onOpenLogin: viewModel.openLogin
                )
                .opacity(viewModel.isBrowserActive ? 0 : 1)
                .allowsHitTesting(!viewModel.isBrowserActive)
                .accessibilityHidden(viewModel.isBrowserActive)
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
        FocusWebView(viewModel: viewModel.browserViewModel, settingsStore: settingsStore)
            .opacity(viewModel.isBrowserActive ? 1 : 0)
            .allowsHitTesting(viewModel.isBrowserActive)
            .accessibilityHidden(!viewModel.isBrowserActive)
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
        cache.countLimit = 768
        cache.totalCostLimit = 192 * 1024 * 1024
        return cache
    }()
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 192 * 1024 * 1024,
            diskCapacity: 768 * 1024 * 1024,
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
        if let image = UIImage(data: data) {
            return image
        }

        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
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
            candidates.insert(optimizedURL, at: 0)
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
    let onOpenCard: (DynamicCard) -> Void
    let onOpenLogin: () -> Void

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
                    .padding(.top, 16)
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
        for card in cards {
            let urls = ([card.author.avatarURL] + card.coverURLs).compactMap { $0 }
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
