#if canImport(UIKit)
import Combine
import CryptoKit
import FocusCore
import Foundation
import WebKit

@MainActor
final class FocusAppViewModel: ObservableObject {
    enum PrimaryTab {
        case dynamic
        case search
        case my
    }

    enum Route {
        case dynamicFeed
        case searchResults(SearchQuery)
        case my
        case history
        case userSpace(URL)
        case userCollection(FocusUserSpaceCollection)
        case article(URL)
        case opus(URL)
        case browser(URL)
    }

    private static let loginURL = URL(string: "https://passport.bilibili.com/login")!

    @Published private(set) var route: Route = .dynamicFeed
    @Published private(set) var hasInstantiatedBrowser = false
    @Published var showSettings = false
    @Published var showSearch = false
    @Published var searchKeyword = ""

    let settingsStore: FocusSettingsStore
    let browserViewModel: FocusBrowserViewModel
    let dynamicFeedViewModel: FocusDynamicFeedViewModel
    let searchResultsViewModel: FocusSearchResultsViewModel
    let myViewModel: FocusMyViewModel
    let historyViewModel: FocusHistoryViewModel
    let userSpaceViewModel: FocusUserSpaceViewModel
    let userCollectionViewModel: FocusUserCollectionViewModel
    let articleViewModel: FocusArticleViewModel
    let opusDetailViewModel: FocusOpusDetailViewModel
    private let cookieProvider: WebViewCookieSnapshotProvider
    private let nativePageAugmentService: FocusNativePageAugmentService

    private var didHandleLaunchEntry = false
    private var browserReturnRoute: Route = .dynamicFeed
    private var historyReturnRoute: Route = .my
    private var userSpaceReturnRoute: Route = .dynamicFeed
    private var userCollectionReturnRoute: Route = .dynamicFeed
    private var articleReturnRoute: Route = .dynamicFeed
    private var opusReturnRoute: Route = .dynamicFeed
    private var cancellables: Set<AnyCancellable> = []

    init(settingsStore: FocusSettingsStore) {
        self.settingsStore = settingsStore

        let browserViewModel = FocusBrowserViewModel(settingsStore: settingsStore)
        let cookieProvider = WebViewCookieSnapshotProvider()
        let nativePageAugmentService = FocusNativePageAugmentService(cookieProvider: cookieProvider)
        let myDataService = FocusMyDataService(cookieProvider: cookieProvider)
        let dynamicFeedViewModel = FocusDynamicFeedViewModel(
            service: DynamicFeedService(cookieProvider: cookieProvider)
        )
        let searchResultsViewModel = FocusSearchResultsViewModel(
            service: SearchResultService(cookieProvider: cookieProvider)
        )
        let myViewModel = FocusMyViewModel(service: myDataService)
        let historyViewModel = FocusHistoryViewModel(service: myDataService)
        let userSpaceViewModel = FocusUserSpaceViewModel(
            service: FocusUserSpaceService(cookieProvider: cookieProvider)
        )
        let userCollectionViewModel = FocusUserCollectionViewModel(
            service: FocusUserSpaceService(cookieProvider: cookieProvider)
        )
        let articleViewModel = FocusArticleViewModel(
            service: FocusArticleService(cookieProvider: cookieProvider)
        )
        let opusDetailViewModel = FocusOpusDetailViewModel(
            detailService: FocusOpusDetailService(cookieProvider: cookieProvider),
            augmentService: nativePageAugmentService
        )

        self.browserViewModel = browserViewModel
        self.cookieProvider = cookieProvider
        self.nativePageAugmentService = nativePageAugmentService
        self.dynamicFeedViewModel = dynamicFeedViewModel
        self.searchResultsViewModel = searchResultsViewModel
        self.myViewModel = myViewModel
        self.historyViewModel = historyViewModel
        self.userSpaceViewModel = userSpaceViewModel
        self.userCollectionViewModel = userCollectionViewModel
        self.articleViewModel = articleViewModel
        self.opusDetailViewModel = opusDetailViewModel
        browserViewModel.nativePageAugmentService = nativePageAugmentService

        browserViewModel.onEntryRequest = { [weak self] entry in
            Task { @MainActor [weak self] in
                self?.open(entry)
            }
        }

        browserViewModel.onUserSpaceRequest = { [weak self] url in
            Task { @MainActor [weak self] in
                self?.openNativeUserSpace(url)
            }
        }

        browserViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var navigationTitle: String {
        switch route {
        case .dynamicFeed:
            return "动态"
        case let .searchResults(query):
            return query.keyword.isEmpty ? "搜索" : query.keyword
        case .my:
            return myViewModel.navigationTitle
        case .history:
            return historyViewModel.navigationTitle
        case .userSpace(_):
            return userSpaceViewModel.navigationTitle
        case .userCollection(_):
            return userCollectionViewModel.navigationTitle
        case .article(_):
            return articleViewModel.navigationTitle
        case .opus(_):
            return opusDetailViewModel.navigationTitle
        case .browser(_):
            return browserViewModel.navigationTitle
        }
    }

    var activePrimaryTab: PrimaryTab {
        switch route {
        case .dynamicFeed:
            return .dynamic
        case .searchResults(_):
            return .search
        case .my:
            return .my
        case .history:
            return .my
        case .userSpace(_):
            return primaryTab(for: userSpaceReturnRoute)
        case .userCollection(_):
            return primaryTab(for: userCollectionReturnRoute)
        case .article(_):
            return primaryTab(for: articleReturnRoute)
        case .opus(_):
            return primaryTab(for: opusReturnRoute)
        case .browser(_):
            switch browserViewModel.entryContext {
            case .dynamic:
                return .dynamic
            case .search:
                return .search
            case .my:
                return .my
            }
        }
    }

    var isBrowserActive: Bool {
        if case .browser(_) = route {
            return true
        }
        return false
    }

    var showsBrowserBackButton: Bool {
        isBrowserActive
    }

    var showsBackButton: Bool {
        if isBrowserActive {
            return true
        }
        if case .opus(_) = route {
            return true
        }
        if case .history = route {
            return true
        }
        if case .userSpace(_) = route {
            return true
        }
        if case .userCollection(_) = route {
            return true
        }
        if case .article(_) = route {
            return true
        }
        return false
    }

    func handleLaunchEntryIfNeeded() {
        guard !didHandleLaunchEntry else {
            return
        }

        didHandleLaunchEntry = true
        hasInstantiatedBrowser = true
        refreshLoginSensitiveContent()
        if settingsStore.settings.defaultEntry == .search {
            showSearch = true
        }
    }

    func open(_ entry: FocusEntry) {
        switch entry {
        case .dynamic:
            if isBrowserActive {
                browserViewModel.prepareForDismiss()
            }
            route = .dynamicFeed
            dynamicFeedViewModel.loadIfNeeded()
        case .search:
            showSearch = true
        }
    }

    func open(card: DynamicCard) {
        let destinationURL = card.videoURL ?? card.targetURL
        if Self.isArticleURL(destinationURL) {
            openArticle(destinationURL)
            return
        }
        if Self.isOpusURL(destinationURL) {
            openOpus(destinationURL)
            return
        }
        openBrowser(destinationURL, context: .dynamic)
    }

    func open(searchItem: SearchResultItem) {
        if Self.isUserSpaceURL(searchItem.targetURL) {
            openUserSpace(searchItem.targetURL)
            return
        }
        if Self.isArticleURL(searchItem.targetURL) {
            openArticle(searchItem.targetURL)
            return
        }
        if Self.isOpusURL(searchItem.targetURL) {
            openOpus(searchItem.targetURL)
            return
        }
        openBrowser(searchItem.targetURL, context: .search)
    }

    func open(searchPreview: SearchResultItem.PreviewVideo) {
        openBrowser(searchPreview.targetURL, context: .search)
    }

    func openMyVideo(_ url: URL) {
        openBrowser(url, context: .my)
    }

    func openOpusRelatedURL(_ url: URL) {
        if Self.isUserSpaceURL(url) {
            openUserSpace(url)
            return
        }
        if Self.isArticleURL(url) {
            openArticle(url)
            return
        }
        if Self.isOpusURL(url) {
            openOpus(url)
            return
        }
        openBrowser(url, context: entryContext(for: activePrimaryTab))
    }

    func openUserCollection(_ collection: FocusUserSpaceCollection) {
        userCollectionReturnRoute = routeForCurrentNativeContext()
        route = .userCollection(collection)
        userCollectionViewModel.open(collection)
    }

    func submitSearch() {
        let query = SearchQuery(keyword: searchKeyword)
        guard !query.keyword.isEmpty else {
            return
        }

        showSearch = false
        route = .searchResults(query)
        searchResultsViewModel.search(query)
    }

    func openMy() {
        if isBrowserActive {
            browserViewModel.prepareForDismiss()
        }
        route = .my
        myViewModel.refreshForAppearance()
    }

    func openHistory() {
        if isBrowserActive {
            browserViewModel.prepareForDismiss()
        }
        historyReturnRoute = routeForCurrentNativeContext()
        route = .history
        historyViewModel.loadIfNeeded()
    }

    func openLogin() {
        openBrowser(Self.loginURL, context: .my)
    }

    func reloadCurrent() {
        switch route {
        case .dynamicFeed:
            dynamicFeedViewModel.reload()
        case .searchResults(_):
            searchResultsViewModel.reload()
        case .my:
            myViewModel.reload()
        case .history:
            historyViewModel.reload()
        case .userSpace(_):
            userSpaceViewModel.reload()
        case .userCollection(_):
            userCollectionViewModel.reload()
        case .article(_):
            articleViewModel.reload()
        case .opus(_):
            opusDetailViewModel.reload()
        case .browser(_):
            browserViewModel.reload()
        }
    }

    func handleAppDidBecomeActive() {
        refreshLoginSensitiveContent()
    }

    func goBack() {
        guard isBrowserActive else {
            return
        }
        browserViewModel.goBack()
    }

    func handleBrowserBack() {
        guard isBrowserActive else {
            return
        }

        switch browserViewModel.resolveAppBackAction() {
        case .close:
            closeBrowser()
        case let .navigate(url):
            browserViewModel.navigateAppBack(to: url)
        }
    }

    func handleTopLevelBack() {
        if isBrowserActive {
            handleBrowserBack()
            return
        }

        if case .opus(_) = route {
            closeOpus()
            return
        }

        if case .history = route {
            closeHistory()
            return
        }

        if case .userSpace(_) = route {
            closeUserSpace()
            return
        }

        if case .userCollection(_) = route {
            closeUserCollection()
            return
        }

        if case .article(_) = route {
            closeArticle()
        }
    }

    func goForward() {
        guard isBrowserActive else {
            return
        }
        browserViewModel.goForward()
    }

    func closeBrowser() {
        browserViewModel.prepareForDismiss()
        switch browserReturnRoute {
        case .dynamicFeed:
            route = .dynamicFeed
        case .searchResults(_):
            route = browserReturnRoute
        case .my:
            route = .my
        case .history:
            route = browserReturnRoute
        case .userSpace(_):
            route = browserReturnRoute
        case .userCollection(_):
            route = browserReturnRoute
        case .article(_):
            route = browserReturnRoute
        case .opus(_):
            route = browserReturnRoute
        case .browser(_):
            route = .dynamicFeed
        }
    }

    private func openBrowser(_ url: URL, context: FocusBrowserViewModel.EntryContext) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        hasInstantiatedBrowser = true
        if case .browser(_) = route {
            // Keep the current return route while navigating within the browser shell.
        } else {
            browserReturnRoute = route
        }
        route = .browser(canonicalURL)
        browserViewModel.open(canonicalURL, context: context)
    }

    private func openOpus(_ url: URL) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        opusReturnRoute = routeForCurrentNativeContext()
        route = .opus(canonicalURL)
        opusDetailViewModel.open(canonicalURL)
    }

    private func openUserSpace(_ url: URL) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        guard Self.extractUserSpaceMID(from: canonicalURL) != nil else {
            openBrowser(canonicalURL, context: entryContext(for: activePrimaryTab))
            return
        }

        userSpaceReturnRoute = routeForCurrentNativeContext()
        route = .userSpace(canonicalURL)
        userSpaceViewModel.open(canonicalURL)
    }

    private func openArticle(_ url: URL) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        guard Self.extractArticleCVID(from: canonicalURL) != nil else {
            openBrowser(canonicalURL, context: entryContext(for: activePrimaryTab))
            return
        }

        articleReturnRoute = routeForCurrentNativeContext()
        route = .article(canonicalURL)
        articleViewModel.open(canonicalURL)
    }

    private func closeOpus() {
        switch opusReturnRoute {
        case .dynamicFeed:
            route = .dynamicFeed
        case .searchResults(_):
            route = opusReturnRoute
        case .my:
            route = .my
        case .history:
            route = opusReturnRoute
        case .userSpace(_):
            route = opusReturnRoute
        case .userCollection(_):
            route = opusReturnRoute
        case .article(_):
            route = opusReturnRoute
        case .opus(_):
            route = .dynamicFeed
        case .browser(_):
            route = .dynamicFeed
        }
    }

    private func closeHistory() {
        switch historyReturnRoute {
        case .dynamicFeed:
            route = .dynamicFeed
        case .searchResults(_):
            route = historyReturnRoute
        case .my:
            route = .my
        case .history:
            route = .my
        case .userSpace(_):
            route = historyReturnRoute
        case .userCollection(_):
            route = historyReturnRoute
        case .article(_):
            route = historyReturnRoute
        case .opus(_):
            route = historyReturnRoute
        case .browser(_):
            route = .my
        }
    }

    private func closeUserSpace() {
        switch userSpaceReturnRoute {
        case .dynamicFeed:
            route = .dynamicFeed
        case .searchResults(_):
            route = userSpaceReturnRoute
        case .my:
            route = .my
        case .history:
            route = userSpaceReturnRoute
        case .userSpace(_):
            route = .dynamicFeed
        case .userCollection(_):
            route = userSpaceReturnRoute
        case .article(_):
            route = userSpaceReturnRoute
        case .opus(_):
            route = userSpaceReturnRoute
        case .browser(_):
            route = .dynamicFeed
        }
    }

    private func closeUserCollection() {
        switch userCollectionReturnRoute {
        case .dynamicFeed:
            route = .dynamicFeed
        case .searchResults(_):
            route = userCollectionReturnRoute
        case .my:
            route = .my
        case .history:
            route = userCollectionReturnRoute
        case .userSpace(_):
            route = userCollectionReturnRoute
        case .userCollection(_):
            route = .dynamicFeed
        case .article(_):
            route = userCollectionReturnRoute
        case .opus(_):
            route = userCollectionReturnRoute
        case .browser(_):
            route = .dynamicFeed
        }
    }

    private func closeArticle() {
        switch articleReturnRoute {
        case .dynamicFeed:
            route = .dynamicFeed
        case .searchResults(_):
            route = articleReturnRoute
        case .my:
            route = .my
        case .history:
            route = articleReturnRoute
        case .userSpace(_):
            route = articleReturnRoute
        case .userCollection(_):
            route = articleReturnRoute
        case .article(_):
            route = .dynamicFeed
        case .opus(_):
            route = articleReturnRoute
        case .browser(_):
            route = .dynamicFeed
        }
    }

    private func refreshLoginSensitiveContent() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            _ = await cookieProvider.refreshSnapshotIfNeeded()
            switch route {
        case .dynamicFeed:
            dynamicFeedViewModel.reload()
        case .searchResults(_):
            searchResultsViewModel.reload()
        case .my:
            myViewModel.reload()
        case .history:
            historyViewModel.reload()
        case .userSpace(_):
            userSpaceViewModel.reload()
        case .userCollection(_):
            userCollectionViewModel.reload()
            case .article(_):
                articleViewModel.reload()
            case .opus(_):
                break
            case .browser(_):
                break
            }
        }
    }

    private func primaryTab(for route: Route) -> PrimaryTab {
        switch route {
        case .dynamicFeed, .opus(_):
            return .dynamic
        case .searchResults(_):
            return .search
        case .my, .history:
            return .my
        case .userSpace(_):
            switch userSpaceReturnRoute {
            case .searchResults(_):
                return .search
            case .my:
                return .my
            case .history:
                return .my
            default:
                return .dynamic
            }
        case .userCollection(_):
            return primaryTab(for: userCollectionReturnRoute)
        case .article(_):
            return primaryTab(for: articleReturnRoute)
        case .browser(_):
            switch browserViewModel.entryContext {
            case .dynamic:
                return .dynamic
            case .search:
                return .search
            case .my:
                return .my
            }
        }
    }

    private func routeForCurrentNativeContext() -> Route {
        switch route {
        case .browser(_):
            return browserReturnRoute
        default:
            return route
        }
    }

    private static func isOpusURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        let path = url.path.lowercased()
        if (host == "www.bilibili.com" || host == "bilibili.com" || host == "m.bilibili.com"),
           path.hasPrefix("/opus/")
        {
            return true
        }

        let pathComponents = url.path.split(separator: "/")
        return host == "t.bilibili.com"
            && pathComponents.count == 1
            && pathComponents[0].allSatisfy(\.isNumber)
    }

    private static func isUserSpaceURL(_ url: URL) -> Bool {
        extractUserSpaceMID(from: url) != nil
    }

    private static func isArticleURL(_ url: URL) -> Bool {
        extractArticleCVID(from: url) != nil
    }

    private static func extractUserSpaceMID(from url: URL) -> Int64? {
        guard url.host?.lowercased() == "space.bilibili.com" else {
            return nil
        }

        guard let first = url.path.split(separator: "/").first else {
            return nil
        }

        let candidate = String(first)
        guard candidate.allSatisfy(\.isNumber) else {
            return nil
        }

        return Int64(candidate)
    }

    private static func extractArticleCVID(from url: URL) -> Int64? {
        let absoluteString = url.absoluteString
        if let match = absoluteString.range(of: #"read/cv(\d+)"#, options: .regularExpression) {
            let matched = String(absoluteString[match])
            return Int64(matched.replacingOccurrences(of: "read/cv", with: ""))
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        return components.queryItems?
            .first(where: { $0.name.caseInsensitiveCompare("id") == .orderedSame })?
            .value
            .flatMap(Int64.init)
    }

    private func entryContext(for tab: PrimaryTab) -> FocusBrowserViewModel.EntryContext {
        switch tab {
        case .dynamic:
            return .dynamic
        case .search:
            return .search
        case .my:
            return .my
        }
    }

    func shouldOpenNativeUserSpace(_ url: URL) -> Bool {
        Self.isUserSpaceURL(url)
    }

    func openNativeUserSpace(_ url: URL) {
        openUserSpace(url)
    }
}

@MainActor
final class FocusBrowserViewModel: ObservableObject {
    enum EntryContext {
        case dynamic
        case search
        case my
    }

    enum AppBackAction {
        case close
        case navigate(URL)
    }

    private struct DetectedPageState: Sendable {
        let hasPlayer: Bool
        let pageURLString: String?
        let pageTitle: String?
        let videoTitle: String?
    }

    @Published private(set) var currentURL: URL?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var hasActiveVideoRoute = false
    @Published private(set) var hasDetectedPlayer = false
    @Published private(set) var isImmersiveVideo = false
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackRate: Double = 1.0
    @Published private(set) var isDanmakuHidden = false
    @Published private(set) var hasSubtitles = false
    @Published private(set) var isSubtitleHidden = false
    @Published private(set) var isLoadingPage = false
    @Published private(set) var entryContext: EntryContext = .dynamic
    @Published private(set) var navigationTitle = "浏览"

    let settingsStore: FocusSettingsStore

    weak var webView: WKWebView?
    fileprivate var nativePageAugmentService: FocusNativePageAugmentService?
    var reconfigureScripts: ((WKWebView, FocusSettings) -> Void)?
    var prepareForURL: ((WKWebView, URL) -> Void)?
    var onEntryRequest: ((FocusEntry) -> Void)?
    var onUserSpaceRequest: ((URL) -> Void)?
    private var pendingURL: URL?
    private var cancellables: Set<AnyCancellable> = []
    private var playerStateObservationTask: Task<Void, Never>?
    private var embeddedPlayerDetectionTask: Task<Void, Never>?
    private var pageAugmentationTask: Task<Void, Never>?
    private var pageAugmentationRevision = 0
    private var pageAugmentCache: [String: FocusNativePageAugmentPayload] = [:]
    private var appBackStack: [URL] = []
    private var pendingAppBackTarget: URL?
    private var isHandlingAppBackNavigation = false
    private var lastDebugDetectedPageStateSignature: String?
    private var lastDebugPlayerStateSignature: String?

    init(settingsStore: FocusSettingsStore) {
        self.settingsStore = settingsStore

        settingsStore.$settings
            .dropFirst()
            .sink { [weak self] settings in
                self?.applySettingsChange(settings)
            }
            .store(in: &cancellables)
    }

    var router: FocusRouter {
        FocusRouter(settings: settingsStore.settings)
    }

    var navigationPolicy: FocusNavigationPolicy {
        FocusNavigationPolicy(settings: settingsStore.settings)
    }

    var isVideoPage: Bool {
        if let currentURL {
            return FocusUserAgent.shouldUseDesktopPlayback(for: currentURL)
        }

        if let pendingURL {
            return FocusUserAgent.shouldUseDesktopPlayback(for: pendingURL)
        }

        return false
    }

    var showsNativeVideoControls: Bool {
        if let pendingURL, FocusUserAgent.shouldUseDesktopPlayback(for: pendingURL) {
            return true
        }

        if let currentURL, FocusUserAgent.shouldUseDesktopPlayback(for: currentURL) {
            return true
        }

        if hasDetectedPlayer || hasActiveVideoRoute {
            return true
        }

        guard let activeURL = currentURL ?? pendingURL else {
            return allowsPlayerControl
        }

        return !isSearchResultURL(activeURL) && allowsPlayerControl
    }

    var playbackRateLabel: String {
        switch playbackRate {
        case 1:
            return "1x"
        case 1.25:
            return "1.25x"
        case 1.5:
            return "1.5x"
        case 2:
            return "2x"
        default:
            return String(format: "%.2gx", playbackRate)
        }
    }

    func attach(
        webView: WKWebView,
        reconfigureScripts: @escaping (WKWebView, FocusSettings) -> Void,
        prepareForURL: @escaping (WKWebView, URL) -> Void
    ) {
        self.webView = webView
        self.reconfigureScripts = reconfigureScripts
        self.prepareForURL = prepareForURL

        if let pendingURL {
            prepareForURL(webView, pendingURL)
            webView.load(URLRequest(url: pendingURL))
        }
    }

    func open(_ url: URL, context: EntryContext) {
        resetAppBackStack()
        invalidatePageAugmentation()
        entryContext = context
        pendingURL = url
        isLoadingPage = true
        playerStateObservationTask?.cancel()
        embeddedPlayerDetectionTask?.cancel()
        hasActiveVideoRoute = FocusUserAgent.shouldUseDesktopPlayback(for: url)
        updateNavigationMetadata(for: url, pageTitle: nil, context: context)
        if !hasActiveVideoRoute {
            resetPlayerState()
        }
        if let webView {
            prepareForURL?(webView, url)
            webView.load(URLRequest(url: url))
        }

        debugLog(
            "open",
            fields: debugStateFields([
                "inputURL": url.absoluteString,
                "context": entryContextLabel(context)
            ])
        )
    }

    func reload() {
        if let webView {
            webView.reload()
            return
        }

        guard let pendingURL else {
            return
        }

        if let webView {
            prepareForURL?(webView, pendingURL)
        }
        webView?.load(URLRequest(url: pendingURL))
    }

    func goBack() {
        guard canGoBack else { return }
        webView?.goBack()
    }

    func goForward() {
        guard canGoForward else { return }
        webView?.goForward()
    }

    func noteUpcomingNavigation(to url: URL, from currentURL: URL?, navigationType: WKNavigationType) {
        let canonicalTargetURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        let canonicalCurrentURL = currentURL.map(FocusNavigationPolicy.canonicalWebURL(for:))
        let shouldPushAppBack = shouldPushAppBackEntry(
            from: canonicalCurrentURL,
            to: canonicalTargetURL,
            navigationType: navigationType
        )

        pendingURL = canonicalTargetURL
        updateNavigationMetadata(for: canonicalTargetURL)
        if canonicalCurrentURL != canonicalTargetURL {
            isLoadingPage = true
        }
        hasActiveVideoRoute = FocusUserAgent.shouldUseDesktopPlayback(for: canonicalTargetURL)

        if isHandlingAppBackNavigation {
            debugLog(
                "noteUpcomingNavigation",
                fields: debugStateFields([
                    "fromURL": canonicalCurrentURL?.absoluteString,
                    "targetURL": canonicalTargetURL.absoluteString,
                    "navigationType": navigationTypeLabel(navigationType),
                    "handlingAppBack": debugBool(isHandlingAppBackNavigation),
                    "shouldPushAppBack": debugBool(shouldPushAppBack)
                ])
            )
            return
        }

        guard shouldPushAppBack,
              let canonicalCurrentURL,
              appBackStack.last != canonicalCurrentURL
        else {
            debugLog(
                "noteUpcomingNavigation",
                fields: debugStateFields([
                    "fromURL": canonicalCurrentURL?.absoluteString,
                    "targetURL": canonicalTargetURL.absoluteString,
                    "navigationType": navigationTypeLabel(navigationType),
                    "handlingAppBack": debugBool(isHandlingAppBackNavigation),
                    "shouldPushAppBack": debugBool(shouldPushAppBack)
                ])
            )
            return
        }

        appBackStack.append(canonicalCurrentURL)
        debugLog(
            "noteUpcomingNavigation",
            fields: debugStateFields([
                "fromURL": canonicalCurrentURL.absoluteString,
                "targetURL": canonicalTargetURL.absoluteString,
                "navigationType": navigationTypeLabel(navigationType),
                "handlingAppBack": debugBool(isHandlingAppBackNavigation),
                "shouldPushAppBack": debugBool(shouldPushAppBack),
                "appBackDepth": String(appBackStack.count)
            ])
        )
    }

    func updateNavigationState(from webView: WKWebView) {
        currentURL = webView.url
        pendingURL = webView.url
        isLoadingPage = false
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        updateNavigationMetadata(for: webView.url, pageTitle: webView.title)
        playerStateObservationTask?.cancel()
        embeddedPlayerDetectionTask?.cancel()

        if isHandlingAppBackNavigation,
           let resolvedURL = webView.url,
           let pendingAppBackTarget,
           FocusNavigationPolicy.canonicalWebURL(for: resolvedURL) == pendingAppBackTarget
        {
            isHandlingAppBackNavigation = false
            self.pendingAppBackTarget = nil
        }

        if let currentURL = webView.url {
            hasActiveVideoRoute = FocusUserAgent.shouldUseDesktopPlayback(for: currentURL)
        }

        if hasActiveVideoRoute {
            debugLog(
                "updateNavigationState",
                fields: debugStateFields([
                    "webViewURL": webView.url?.absoluteString,
                    "webViewTitle": webView.title,
                    "canGoBack": debugBool(webView.canGoBack),
                    "canGoForward": debugBool(webView.canGoForward),
                    "mode": "video-route"
                ])
            )
            schedulePageAugmentationRefresh()
            startPlayerStateObservation()
            return
        }

        resetPlayerState()
        debugLog(
            "updateNavigationState",
            fields: debugStateFields([
                "webViewURL": webView.url?.absoluteString,
                "webViewTitle": webView.title,
                "canGoBack": debugBool(webView.canGoBack),
                "canGoForward": debugBool(webView.canGoForward),
                "mode": "page"
            ])
        )
        schedulePageAugmentationRefresh()
        if webView.url != nil {
            startEmbeddedPlayerDetection(on: webView)
        }
    }

    func beginNavigation(to url: URL?) {
        var isStaleStartURL = false
        if let url {
            let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
            let canonicalCurrentURL = currentURL.map(FocusNavigationPolicy.canonicalWebURL(for:))
            let canonicalPendingURL = pendingURL.map(FocusNavigationPolicy.canonicalWebURL(for:))
            isStaleStartURL = canonicalCurrentURL == canonicalURL
                && canonicalPendingURL != nil
                && canonicalPendingURL != canonicalURL

            if !isStaleStartURL {
                invalidatePageAugmentation()
                pendingURL = canonicalURL
                updateNavigationMetadata(for: canonicalURL)
            }
        }
        isLoadingPage = true
        debugLog(
            "beginNavigation",
            fields: debugStateFields([
                "inputURL": url?.absoluteString,
                "isStaleStartURL": debugBool(isStaleStartURL)
            ])
        )
    }

    func handleNavigationFailure(failingURL: URL?) {
        if let failingURL {
            pendingURL = FocusNavigationPolicy.canonicalWebURL(for: failingURL)
            updateNavigationMetadata(for: pendingURL)
        }
        isLoadingPage = false
        debugLog(
            "handleNavigationFailure",
            fields: debugStateFields([
                "failingURL": failingURL?.absoluteString
            ])
        )
    }

    func entryRedirect(for url: URL) -> FocusEntry? {
        router.redirectTarget(for: url)
    }

    func requestNativeEntry(_ entry: FocusEntry) {
        onEntryRequest?(entry)
    }

    func shouldOpenNativeUserSpace(_ url: URL) -> Bool {
        Self.extractUserSpaceMID(from: url) != nil
    }

    func openNativeUserSpace(_ url: URL) {
        onUserSpaceRequest?(FocusNavigationPolicy.canonicalWebURL(for: url))
    }

    func resolveAppBackAction() -> AppBackAction {
        guard let targetURL = appBackStack.popLast() else {
            return .close
        }

        return .navigate(targetURL)
    }

    func navigateAppBack(to url: URL) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        invalidatePageAugmentation()
        isHandlingAppBackNavigation = true
        pendingAppBackTarget = canonicalURL
        pendingURL = canonicalURL
        isLoadingPage = true
        hasActiveVideoRoute = FocusUserAgent.shouldUseDesktopPlayback(for: canonicalURL)
        updateNavigationMetadata(for: canonicalURL)

        if !hasActiveVideoRoute {
            resetPlayerState()
        }

        if let webView {
            if let historyItem = historyItem(for: canonicalURL, in: webView) {
                debugLog(
                    "navigateAppBack",
                    fields: debugStateFields([
                        "targetURL": canonicalURL.absoluteString,
                        "usedHistoryItem": debugBool(true),
                        "appBackDepth": String(appBackStack.count)
                    ])
                )
                webView.go(to: historyItem)
                return
            }

            prepareForURL?(webView, canonicalURL)
            webView.load(URLRequest(url: canonicalURL))
        }

        debugLog(
            "navigateAppBack",
            fields: debugStateFields([
                "targetURL": canonicalURL.absoluteString,
                "usedHistoryItem": debugBool(false),
                "appBackDepth": String(appBackStack.count)
            ])
        )
    }

    func navigationDecision(for url: URL, currentURL: URL? = nil) -> FocusNavigationPolicy.Decision {
        navigationPolicy.decision(for: url, currentURL: currentURL)
    }

    func logNavigationDecision(
        url: URL,
        currentURL: URL?,
        navigationType: WKNavigationType,
        decision: String
    ) {
        debugLog(
            "navigationDecision",
            fields: debugStateFields([
                "requestURL": url.absoluteString,
                "currentURL": currentURL?.absoluteString,
                "navigationType": navigationTypeLabel(navigationType),
                "decision": decision
            ])
        )
    }

    func cyclePlaybackRate() {
        let rates: [Double] = [1.0, 1.25, 1.5, 2.0]
        let nextIndex = rates.firstIndex(of: playbackRate).map { ($0 + 1) % rates.count } ?? 0
        let nextRate = rates[nextIndex]

        runPlayerCommand(
            """
            (() => {
              const rate = \(nextRate);
              const videos = Array.from(document.querySelectorAll('video'));
              const trackedVideo = window.__FOCUS_ACTIVE_VIDEO__;
              const rankedVideos = videos
                .map((video) => {
                  const rect = video.getBoundingClientRect();
                  const style = window.getComputedStyle(video);
                  const area = Math.max(rect.width, 0) * Math.max(rect.height, 0);
                  const visible = rect.width > 120
                    && rect.height > 70
                    && style.display !== 'none'
                    && style.visibility !== 'hidden'
                    && style.opacity !== '0';
                  const insidePlayer = !!video.closest('#bilibili-player, .bpx-player-container, #playerWrap, .player-container, .bpx-player-video-wrap');
                  const score = (insidePlayer ? 1000000 : 0) + (visible ? 100000 : 0) + area + (video.readyState > 0 ? 5000 : 0);
                  return { video, score };
                })
                .sort((left, right) => right.score - left.score);
              const primaryVideo = trackedVideo && trackedVideo.isConnected ? trackedVideo : (rankedVideos[0]?.video || null);
              const targetVideos = primaryVideo ? [primaryVideo] : videos;
              if (primaryVideo) {
                window.__FOCUS_ACTIVE_VIDEO__ = primaryVideo;
              }

              targetVideos.forEach((video) => {
                video.playbackRate = rate;
                video.defaultPlaybackRate = rate;
                video.dispatchEvent(new Event('ratechange'));
              });
              if (typeof window.__FOCUS_SNAPSHOT_PLAYER_STATE__ === 'function') {
                window.__FOCUS_SNAPSHOT_PLAYER_STATE__();
                setTimeout(() => window.__FOCUS_SNAPSHOT_PLAYER_STATE__(), 80);
                setTimeout(() => window.__FOCUS_SNAPSHOT_PLAYER_STATE__(), 260);
              }
              return targetVideos.length > 0;
            })();
            """
        )
    }

    func togglePlayback() {
        runPlayerCommand(
            """
            (() => {
              const videos = Array.from(document.querySelectorAll('video'));
              const trackedVideo = window.__FOCUS_ACTIVE_VIDEO__;
              const rankedVideos = videos
                .map((video) => {
                  const rect = video.getBoundingClientRect();
                  const style = window.getComputedStyle(video);
                  const area = Math.max(rect.width, 0) * Math.max(rect.height, 0);
                  const visible = rect.width > 120
                    && rect.height > 70
                    && style.display !== 'none'
                    && style.visibility !== 'hidden'
                    && style.opacity !== '0';
                  const insidePlayer = !!video.closest('#bilibili-player, .bpx-player-container, #playerWrap, .player-container, .bpx-player-video-wrap');
                  const score = (insidePlayer ? 1000000 : 0) + (visible ? 100000 : 0) + area + (video.readyState > 0 ? 5000 : 0) + (!video.paused && !video.ended ? 1000 : 0);
                  return { video, score };
                })
                .sort((left, right) => right.score - left.score);
              const primaryVideo = trackedVideo && trackedVideo.isConnected ? trackedVideo : (rankedVideos[0]?.video || null);
              const playButton = document.querySelector('.bpx-player-ctrl-play, .bilibili-player-video-btn-start, [class*="ctrl-play"]');
              const hasPlayingVideo = primaryVideo
                ? (!primaryVideo.paused && !primaryVideo.ended)
                : videos.some((video) => !video.paused && !video.ended);
              let didIssueCommand = false;

              if (primaryVideo) {
                window.__FOCUS_ACTIVE_VIDEO__ = primaryVideo;
                if (hasPlayingVideo) {
                  primaryVideo.pause?.();
                } else {
                  const playTask = primaryVideo.play?.();
                  if (playTask && typeof playTask.catch === 'function') {
                    playTask.catch(() => {});
                  }
                }
                primaryVideo.dispatchEvent(new Event(hasPlayingVideo ? 'pause' : 'play'));
                didIssueCommand = true;
              } else if (playButton) {
                playButton.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
                didIssueCommand = true;
              }

              if (typeof window.__FOCUS_SNAPSHOT_PLAYER_STATE__ === 'function' && didIssueCommand) {
                window.__FOCUS_SNAPSHOT_PLAYER_STATE__();
                setTimeout(() => window.__FOCUS_SNAPSHOT_PLAYER_STATE__(), 90);
                setTimeout(() => window.__FOCUS_SNAPSHOT_PLAYER_STATE__(), 280);
              }

              return didIssueCommand;
            })();
            """
        )
    }

    func toggleDanmaku() {
        runPlayerCommand(
            """
            (() => {
              const toggle = document.querySelector('.bpx-player-ctrl-dm, .bpx-player-dm-switch, [class*="dm-switch"], [class*="ctrl-dm"]');
              if (toggle) {
                toggle.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
                return true;
              }

              const hidden = !document.documentElement.classList.contains('focus-hide-danmaku');
              document.documentElement.classList.toggle('focus-hide-danmaku', hidden);
              return !!document.querySelector('video');
            })();
            """
        )
    }

    func requestFullscreen() {
        runPlayerCommand(
            """
            (() => {
              const trackedVideo = window.__FOCUS_ACTIVE_VIDEO__;
              const video = trackedVideo && trackedVideo.isConnected ? trackedVideo : document.querySelector('video');
              if (video && typeof video.webkitEnterFullscreen === 'function') {
                try {
                  video.webkitEnterFullscreen();
                  return true;
                } catch (_) {}
              }

              if (video && typeof video.webkitSetPresentationMode === 'function') {
                try {
                  video.webkitSetPresentationMode('fullscreen');
                  return true;
                } catch (_) {}
              }

              const fullscreenButton = document.querySelector('.bpx-player-ctrl-full, [class*="ctrl-full"], [class*="fullscreen"]');
              if (fullscreenButton) {
                fullscreenButton.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
                return true;
              }

              const webFullscreenButton = document.querySelector('.bpx-player-ctrl-web, [class*="web-fullscreen"]');
              if (webFullscreenButton) {
                webFullscreenButton.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
                return true;
              }

              if (video && typeof video.requestFullscreen === 'function') {
                video.requestFullscreen();
                return true;
              }

              return false;
            })();
            """
        )
    }

    func exitFullscreen() {
        runPlayerCommand(
            """
            (() => {
              const playerRoot = document.querySelector('.bpx-player-container, #bilibili-player, #playerWrap');
              const playerClassName = String(playerRoot?.className || '');
              if (/fullscreen/.test(playerClassName)) {
                const playerExit = document.querySelector('.bpx-player-ctrl-full, .bpx-player-ctrl-web, [class*="exit-fullscreen"], [class*="web-fullscreen"]');
                if (playerExit) {
                  playerExit.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
                  return true;
                }
              }

              if (document.fullscreenElement && typeof document.exitFullscreen === 'function') {
                document.exitFullscreen();
              }

              const video = document.querySelector('video');
              if (video && typeof video.webkitSetPresentationMode === 'function') {
                try {
                  video.webkitSetPresentationMode('inline');
                } catch (_) {}
              }

              const exitButton = document.querySelector('.bpx-player-ctrl-web, .bpx-player-ctrl-full, [class*="web-fullscreen"], [class*="exit-fullscreen"]');
              exitButton?.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
              return true;
            })();
            """
        )
    }

    func toggleSubtitles() {
        runPlayerCommand(
            """
            (() => {
              const subtitleToggle = document.querySelector('.bpx-player-ctrl-subtitle, .bpx-player-subtitle-btn, [class*="subtitle-switch"], [class*="subtitle-btn"], [class*="subtitle"] button');
              if (subtitleToggle) {
                subtitleToggle.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
                return true;
              }

              const video = document.querySelector('video');
              if (!video || !video.textTracks) {
                return false;
              }

              const tracks = Array.from(video.textTracks);
              if (tracks.length === 0) {
                return false;
              }

              const hasVisibleTrack = tracks.some((track) => track.mode !== 'disabled');
              tracks.forEach((track) => {
                track.mode = hasVisibleTrack ? 'disabled' : 'showing';
              });

              document.documentElement.classList.toggle('focus-hide-subtitles', hasVisibleTrack);
              return true;
            })();
            """
        )
    }

    func handleDeviceOrientationChange(_ orientation: UIDeviceOrientation) {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            return
        }

        guard showsNativeVideoControls || hasActiveVideoRoute || hasDetectedPlayer else {
            return
        }

        switch orientation {
        case .landscapeLeft, .landscapeRight:
            if !isImmersiveVideo {
                requestFullscreen()
            }
        case .portrait:
            if isImmersiveVideo {
                exitFullscreen()
            }
        default:
            break
        }
    }

    func prepareForDismiss() {
        invalidatePageAugmentation()
        playerStateObservationTask?.cancel()
        playerStateObservationTask = nil
        embeddedPlayerDetectionTask?.cancel()
        embeddedPlayerDetectionTask = nil
        isLoadingPage = false
        isImmersiveVideo = false
        navigationTitle = "浏览"
        entryContext = .dynamic
        resetAppBackStack()
    }

    private func applySettingsChange(_ settings: FocusSettings) {
        guard let webView else { return }
        reconfigureScripts?(webView, settings)

        if let currentURL = webView.url {
            prepareForURL?(webView, currentURL)
            webView.load(URLRequest(url: currentURL))
        } else if let pendingURL {
            prepareForURL?(webView, pendingURL)
            webView.load(URLRequest(url: pendingURL))
        }
    }

    private func runPlayerCommand(_ script: String) {
        guard allowsPlayerControl else {
            return
        }

        webView?.evaluateJavaScript(script) { [weak self] _, _ in
            guard let self else {
                return
            }

            Task { @MainActor [weak self] in
                let delays: [UInt64] = [80_000_000, 220_000_000, 520_000_000, 1_000_000_000]
                for delay in delays {
                    try? await Task.sleep(nanoseconds: delay)
                    self?.refreshPlayerState()
                }
            }
        }
    }

    private func startEmbeddedPlayerDetection(on webView: WKWebView) {
        let expectedURL = webView.url
        let shouldContinuouslyObserve = expectedURL.map(isSearchResultURL) ?? (entryContext == .search)
        debugLog(
            "startEmbeddedPlayerDetection",
            fields: debugStateFields([
                "expectedURL": expectedURL?.absoluteString,
                "continuous": debugBool(shouldContinuouslyObserve)
            ])
        )
        embeddedPlayerDetectionTask = Task { @MainActor [weak self, weak webView] in
            let initialDelays: [UInt64] = [0, 180_000_000, 420_000_000, 900_000_000, 1_600_000_000]
            var attempt = 0

            while true {
                let delay: UInt64
                if attempt < initialDelays.count {
                    delay = initialDelays[attempt]
                } else if shouldContinuouslyObserve {
                    delay = 950_000_000
                } else {
                    break
                }

                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }

                guard
                    !Task.isCancelled,
                    let self,
                    let webView
                else {
                    return
                }

                if let state = await self.detectEmbeddedPlayerState(on: webView, fallbackURL: expectedURL) {
                    let hasPlayer = state.hasPlayer
                    self.hasDetectedPlayer = hasPlayer || self.hasDetectedPlayer
                    self.applyDetectedPageState(state, fallbackURL: webView.url ?? expectedURL)
                    self.debugLog(
                        "embeddedPlayerDetectionAttempt",
                        fields: self.debugStateFields([
                            "attempt": String(attempt),
                            "expectedURL": expectedURL?.absoluteString,
                            "detectedHasPlayer": self.debugBool(hasPlayer)
                        ])
                    )

                    if self.hasActiveVideoRoute || hasPlayer {
                        self.hasActiveVideoRoute = true
                        self.hasDetectedPlayer = true
                        self.refreshPlayerState()
                        self.startPlayerStateObservation()
                        return
                    }
                }

                attempt += 1
            }

            guard
                let self,
                !Task.isCancelled,
                self.currentURL == expectedURL,
                !shouldContinuouslyObserve
            else {
                return
            }

            self.resetPlayerState()
        }
    }

    private func detectEmbeddedPlayerState(on webView: WKWebView, fallbackURL: URL?) async -> DetectedPageState? {
        let script = """
        (() => {
          const cachedState = window.__FOCUS_PLAYER_STATE__;
          const titleSelectors = [
            '#viewbox_report',
            'h1.video-title',
            'h1[class*="video-title"]',
            '.video-title',
            '[class*="video-title"]',
            '[class*="archive-title"]',
            '.media-title'
          ];
          const extractVideoTitle = () => {
            for (const selector of titleSelectors) {
              const node = Array.from(document.querySelectorAll(selector)).find((candidate) => {
                const text = String(candidate?.textContent || '').trim();
                const rect = candidate?.getBoundingClientRect?.();
                return !!text && text.length >= 4 && text.length <= 160 && !!rect && rect.width > 40;
              });
              if (node) {
                return String(node.textContent || '').trim();
              }
            }
            return '';
          };
          if (cachedState && cachedState.hasPlayer) {
            return {
              ...cachedState,
              hasPlayer: true,
              pageURL: location.href,
              pageTitle: document.title || '',
              videoTitle: extractVideoTitle()
            };
          }

          const videos = Array.from(document.querySelectorAll('video'));
          const shells = document.querySelectorAll('#bilibili-player, .bpx-player-container, #playerWrap, .player-container, .bpx-player-video-wrap');
          const hasVisibleVideo = videos.some((video) => {
            const rect = video.getBoundingClientRect();
            const style = window.getComputedStyle(video);
            const area = Math.max(rect.width, 0) * Math.max(rect.height, 0);
            return rect.width > 120
              && rect.height > 70
              && (rect.width >= Math.max(window.innerWidth * 0.62, 240) || rect.height >= 180 || area >= 65000)
              && style.display !== 'none'
              && style.visibility !== 'hidden'
              && style.opacity !== '0';
          });

          return {
            hasPlayer: shells.length > 0 || hasVisibleVideo,
            pageURL: location.href,
            pageTitle: document.title || '',
            videoTitle: extractVideoTitle()
          };
        })();
        """

        return await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script) { [weak self, weak webView] value, error in
                guard
                    let self
                else {
                    continuation.resume(returning: nil)
                    return
                }

                if let error {
                    self.debugLog(
                        "detectEmbeddedPlayerState.error",
                        fields: self.debugStateFields([
                            "fallbackURL": fallbackURL?.absoluteString,
                            "error": String(describing: error)
                        ])
                    )
                }

                guard
                    let webView,
                    let payload = value as? [String: Any]
                else {
                    self.debugLog(
                        "detectEmbeddedPlayerState.missingPayload",
                        fields: self.debugStateFields([
                            "fallbackURL": fallbackURL?.absoluteString,
                            "valueType": value.map { String(describing: type(of: $0)) } ?? "nil"
                        ])
                    )
                    continuation.resume(returning: nil)
                    return
                }

                let state = self.makeDetectedPageState(from: payload)
                self.applyDetectedPageState(state, fallbackURL: webView.url ?? fallbackURL)
                self.logDetectedPageState(state, source: "detectEmbeddedPlayerState")

                let hasPlayer = state.hasPlayer
                if hasPlayer {
                    self.hasDetectedPlayer = true
                }

                continuation.resume(returning: state)
            }
        }
    }

    private func makeDetectedPageState(from payload: [String: Any]) -> DetectedPageState {
        DetectedPageState(
            hasPlayer: payload["hasPlayer"] as? Bool ?? false,
            pageURLString: payload["pageURL"] as? String,
            pageTitle: payload["pageTitle"] as? String,
            videoTitle: payload["videoTitle"] as? String
        )
    }

    private func applyDetectedPageState(_ state: DetectedPageState, fallbackURL: URL?) {
        let resolvedURL = (state.pageURLString.flatMap(URL.init(string:)) ?? fallbackURL)
            .map(FocusNavigationPolicy.canonicalWebURL(for:))
        let preferredTitle = sanitizedPageTitle(state.videoTitle)
            ?? sanitizedPageTitle(state.pageTitle)
            ?? sanitizedPageTitle(webView?.title)
        let hasPlayer = state.hasPlayer

        if let resolvedURL {
            currentURL = resolvedURL
            pendingURL = resolvedURL
            hasActiveVideoRoute = hasActiveVideoRoute || hasPlayer || FocusUserAgent.shouldUseDesktopPlayback(for: resolvedURL)
            updateNavigationMetadata(for: resolvedURL, pageTitle: preferredTitle)
            return
        }

        if preferredTitle != nil {
            updateNavigationMetadata(for: currentURL ?? pendingURL, pageTitle: preferredTitle)
        }
    }

    private var allowsPlayerControl: Bool {
        isVideoPage || hasActiveVideoRoute
    }

    private func resetAppBackStack() {
        appBackStack.removeAll()
        pendingAppBackTarget = nil
        isHandlingAppBackNavigation = false
    }

    private func historyItem(for targetURL: URL, in webView: WKWebView) -> WKBackForwardListItem? {
        let canonicalTargetURL = FocusNavigationPolicy.canonicalWebURL(for: targetURL)
        return webView.backForwardList.backList.last { item in
            FocusNavigationPolicy.canonicalWebURL(for: item.url) == canonicalTargetURL
        }
    }

    private func shouldPushAppBackEntry(from currentURL: URL?, to targetURL: URL, navigationType: WKNavigationType) -> Bool {
        guard let currentURL, currentURL != targetURL else {
            return false
        }

        if navigationType == .backForward || navigationType == .reload {
            return false
        }

        return isSearchResultURL(currentURL) && !isSearchResultURL(targetURL)
    }

    private func isSearchResultURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        if host == "search.bilibili.com" {
            return true
        }

        let path = url.path.lowercased()
        return (host == "www.bilibili.com" || host == "bilibili.com" || host == "m.bilibili.com")
            && path.hasPrefix("/search")
    }

    private static func extractUserSpaceMID(from url: URL) -> Int64? {
        guard url.host?.lowercased() == "space.bilibili.com" else {
            return nil
        }

        guard let first = url.path.split(separator: "/").first else {
            return nil
        }

        let candidate = String(first)
        guard candidate.allSatisfy(\.isNumber) else {
            return nil
        }

        return Int64(candidate)
    }

    private func updateNavigationMetadata(for url: URL?, pageTitle: String? = nil, context: EntryContext? = nil) {
        let resolvedURL = url.map(FocusNavigationPolicy.canonicalWebURL(for:))

        if let context {
            entryContext = context
        } else if let resolvedURL {
            entryContext = inferredEntryContext(for: resolvedURL)
        }

        navigationTitle = resolvedNavigationTitle(for: resolvedURL, pageTitle: pageTitle)
    }

    private func inferredEntryContext(for url: URL) -> EntryContext {
        if Self.isLoginURL(url) {
            return .my
        }

        if isSearchResultURL(url) || entryContext == .search {
            return .search
        }

        return .dynamic
    }

    private func resolvedNavigationTitle(for url: URL?, pageTitle: String?) -> String {
        guard let url else {
            switch entryContext {
            case .dynamic:
                return "浏览"
            case .search:
                return "搜索"
            case .my:
                return "我的"
            }
        }

        if isOpusDetailURL(url) {
            return "图文动态"
        }

        if isSearchResultURL(url) {
            if (hasDetectedPlayer || hasActiveVideoRoute),
               let sanitizedTitle = sanitizedPageTitle(pageTitle),
               !sanitizedTitle.isEmpty,
               sanitizedTitle != searchKeyword(from: url)
            {
                return sanitizedTitle
            }
            return searchKeyword(from: url) ?? "搜索"
        }

        if Self.isLoginURL(url) {
            return "登录"
        }

        if FocusUserAgent.shouldUseDesktopPlayback(for: url),
           let sanitizedTitle = sanitizedPageTitle(pageTitle),
           !sanitizedTitle.isEmpty
        {
            return sanitizedTitle
        }

        if let sanitizedTitle = sanitizedPageTitle(pageTitle),
           !sanitizedTitle.isEmpty,
           sanitizedTitle != "哔哩哔哩"
        {
            return sanitizedTitle
        }

        if FocusUserAgent.shouldUseDesktopPlayback(for: url) {
            return "视频"
        }

        switch entryContext {
        case .dynamic:
            return "浏览"
        case .search:
            return searchKeyword(from: url) ?? "搜索"
        case .my:
            return "我的"
        }
    }

    private func sanitizedPageTitle(_ rawTitle: String?) -> String? {
        guard let rawTitle else {
            return nil
        }

        let separators = [
            "_哔哩哔哩_bilibili",
            "_哔哩哔哩",
            " - 哔哩哔哩",
            " - bilibili",
            " - Bilibili",
            "丨哔哩哔哩",
            "| 哔哩哔哩",
        ]

        let normalizedTitle = separators.reduce(rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)) { title, separator in
            guard let range = title.range(of: separator, options: .caseInsensitive) else {
                return title
            }

            return String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return normalizedTitle.isEmpty ? nil : normalizedTitle
    }

    private func searchKeyword(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        return components.queryItems?
            .first(where: { $0.name.caseInsensitiveCompare("keyword") == .orderedSame })?
            .value?
            .removingPercentEncoding?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isOpusDetailURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        let path = url.path.lowercased()
        if (host == "www.bilibili.com" || host == "bilibili.com" || host == "m.bilibili.com")
            && path.hasPrefix("/opus/")
        {
            return true
        }

        let pathComponents = url.path.split(separator: "/")
        return host == "t.bilibili.com"
            && pathComponents.count == 1
            && pathComponents[0].allSatisfy(\.isNumber)
    }

    private static func isLoginURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        return host == "passport.bilibili.com"
    }

    private func resetPlayerState() {
        playerStateObservationTask?.cancel()
        playerStateObservationTask = nil
        embeddedPlayerDetectionTask?.cancel()
        embeddedPlayerDetectionTask = nil
        hasActiveVideoRoute = false
        hasDetectedPlayer = false
        isImmersiveVideo = false
        isPlaying = false
        playbackRate = 1.0
        isDanmakuHidden = false
        hasSubtitles = false
        isSubtitleHidden = false
        lastDebugDetectedPageStateSignature = nil
        lastDebugPlayerStateSignature = nil
    }

    private func invalidatePageAugmentation() {
        pageAugmentationRevision &+= 1
        pageAugmentationTask?.cancel()
        pageAugmentationTask = nil
    }

    private func schedulePageAugmentationRefresh() {
        guard
            let service = nativePageAugmentService,
            let activeURL = currentURL ?? pendingURL,
            let kind = nativePageKind(for: activeURL)
        else {
            return
        }

        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: activeURL)
        let cacheKey = kind.cacheKey(for: canonicalURL)
        let revision = pageAugmentationRevision

        if let cachedPayload = pageAugmentCache[cacheKey] {
            applyPageAugmentation(cachedPayload, for: canonicalURL, revision: revision)
            return
        }

        pageAugmentationTask?.cancel()
        pageAugmentationTask = Task { [weak self] in
            guard let self else {
                return
            }

            let payload = await service.loadPayload(for: canonicalURL, kind: kind)
            guard !Task.isCancelled else {
                return
            }

            guard let payload else {
                await MainActor.run {
                    guard self.pageAugmentationRevision == revision else {
                        return
                    }

                    self.debugLog(
                        "nativePageAugmentation.missingPayload",
                        fields: self.debugStateFields([
                            "pageKind": kind.rawValue,
                            "pageURL": canonicalURL.absoluteString
                        ])
                    )
                }
                return
            }

            await MainActor.run {
                guard self.pageAugmentationRevision == revision else {
                    return
                }

                self.pageAugmentCache[cacheKey] = payload
                print("[Focus Native Augment] loaded kind=\(payload.kind.rawValue) summary=\(payload.summary) url=\(canonicalURL.absoluteString)")
                self.applyPageAugmentation(payload, for: canonicalURL, revision: revision)
            }
        }
    }

    private func applyPageAugmentation(
        _ payload: FocusNativePageAugmentPayload,
        for canonicalURL: URL,
        revision: Int
    ) {
        let delays: [UInt64] = [0, 220_000_000, 900_000_000, 2_200_000_000]
        for delay in delays {
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }

                guard
                    self.pageAugmentationRevision == revision,
                    let webView = self.webView
                else {
                    return
                }

                let activeURL = (webView.url ?? self.currentURL ?? self.pendingURL)
                    .map(FocusNavigationPolicy.canonicalWebURL(for:))
                guard activeURL == canonicalURL else {
                    return
                }

                let script = payload.javaScript
                webView.evaluateJavaScript(script) { [weak self] _, error in
                    guard let self else {
                        return
                    }

                    if let error {
                        print("[Focus Native Augment] script-error kind=\(payload.kind.rawValue) url=\(canonicalURL.absoluteString) error=\(error)")
                        self.debugLog(
                            "nativePageAugmentation.error",
                            fields: self.debugStateFields([
                                "pageURL": canonicalURL.absoluteString,
                                "pageKind": payload.kind.rawValue,
                                "error": String(describing: error)
                            ])
                        )
                        return
                    }

                    print("[Focus Native Augment] applied kind=\(payload.kind.rawValue) delayMS=\(delay / 1_000_000) url=\(canonicalURL.absoluteString)")
                    let probeScript = """
                    (() => {
                      const root = document.getElementById('focus-native-video-augment') || document.getElementById('focus-native-opus-comments');
                      if (!root) {
                        return { exists: false };
                      }
                      const rect = root.getBoundingClientRect();
                      return {
                        exists: true,
                        top: Math.round(rect.top),
                        height: Math.round(rect.height),
                        childCount: root.children.length,
                        textSample: String(root.textContent || '').trim().slice(0, 120),
                        parentTag: root.parentElement?.tagName || '',
                        previousTag: root.previousElementSibling?.tagName || '',
                        previousClass: root.previousElementSibling?.className || ''
                      };
                    })();
                    """
                    webView.evaluateJavaScript(probeScript) { value, error in
                        if let error {
                            print("[Focus Native Augment] probe-error kind=\(payload.kind.rawValue) url=\(canonicalURL.absoluteString) error=\(error)")
                            return
                        }
                        print("[Focus Native Augment] probe kind=\(payload.kind.rawValue) url=\(canonicalURL.absoluteString) value=\(String(describing: value))")
                    }
                    self.debugLog(
                        "nativePageAugmentation.applied",
                        fields: self.debugStateFields([
                            "pageURL": canonicalURL.absoluteString,
                            "pageKind": payload.kind.rawValue,
                            "delayMS": String(delay / 1_000_000),
                            "summary": payload.summary
                        ])
                    )
                }
            }
        }
    }

    private func nativePageKind(for url: URL) -> FocusNativePageKind? {
        if isOpusDetailURL(url) {
            return .opus
        }

        guard let host = url.host?.lowercased() else {
            return nil
        }

        let path = url.path.lowercased()
        if (host == "www.bilibili.com" || host == "bilibili.com" || host == "m.bilibili.com"),
           path.hasPrefix("/video/")
        {
            return .video
        }

        return nil
    }

    private func startPlayerStateObservation() {
        embeddedPlayerDetectionTask?.cancel()
        embeddedPlayerDetectionTask = nil
        playerStateObservationTask?.cancel()
        playerStateObservationTask = Task { @MainActor [weak self] in
            var attempt = 0
            while let self, self.allowsPlayerControl, !Task.isCancelled {
                self.refreshPlayerState()
                attempt += 1

                let delay: UInt64
                if self.hasDetectedPlayer {
                    delay = 450_000_000
                } else if attempt < 12 {
                    delay = 220_000_000
                } else {
                    delay = 550_000_000
                }

                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    private func refreshPlayerState() {
        guard allowsPlayerControl, let webView else {
            playerStateObservationTask?.cancel()
            playerStateObservationTask = nil
            hasActiveVideoRoute = false
            hasDetectedPlayer = false
            isImmersiveVideo = false
            isPlaying = false
            playbackRate = 1.0
            isDanmakuHidden = false
            hasSubtitles = false
            isSubtitleHidden = false
            return
        }

        let script = """
        (() => {
          const titleSelectors = [
            '#viewbox_report',
            'h1.video-title',
            'h1[class*="video-title"]',
            '.video-title',
            '[class*="video-title"]',
            '[class*="archive-title"]',
            '.media-title'
          ];
          const extractVideoTitle = () => {
            for (const selector of titleSelectors) {
              const node = Array.from(document.querySelectorAll(selector)).find((candidate) => {
                const text = String(candidate?.textContent || '').trim();
                const rect = candidate?.getBoundingClientRect?.();
                return !!text && text.length >= 4 && text.length <= 160 && !!rect && rect.width > 40;
              });
              if (node) {
                return String(node.textContent || '').trim();
              }
            }
            return '';
          };
          const snapshot = typeof window.__FOCUS_SNAPSHOT_PLAYER_STATE__ === 'function'
            ? window.__FOCUS_SNAPSHOT_PLAYER_STATE__()
            : null;
          const cachedState = snapshot || window.__FOCUS_PLAYER_STATE__;
          if (cachedState && typeof cachedState === 'object' && cachedState.hasPlayer) {
            return {
              ...cachedState,
              pageURL: cachedState.pageURL || location.href,
              pageTitle: cachedState.pageTitle || document.title || '',
              videoTitle: cachedState.videoTitle || extractVideoTitle()
            };
          }

          const videos = Array.from(document.querySelectorAll('video'));
          const rankedVideos = videos
            .map((video) => {
              const rect = video.getBoundingClientRect();
              const style = window.getComputedStyle(video);
              const area = Math.max(rect.width, 0) * Math.max(rect.height, 0);
              const visible = rect.width > 120
                && rect.height > 70
                && style.display !== 'none'
                && style.visibility !== 'hidden'
                && style.opacity !== '0';
              const insidePlayer = !!video.closest('#bilibili-player, .bpx-player-container, #playerWrap, .player-container, .bpx-player-video-wrap');
              const largePlaybackCandidate = rect.width >= Math.max(window.innerWidth * 0.62, 240)
                || rect.height >= 180
                || area >= 65000;
              const score = (insidePlayer ? 1000000 : 0)
                + (largePlaybackCandidate ? 250000 : 0)
                + (visible ? 100000 : 0)
                + area
                + (video.readyState > 0 ? 5000 : 0)
                + (!video.paused && !video.ended ? 1000 : 0);
              return { video, score, insidePlayer, largePlaybackCandidate };
            })
            .sort((left, right) => right.score - left.score);
          const hasPlayerShell = !!document.querySelector('#bilibili-player, .bpx-player-container, #playerWrap, .player-container, .bpx-player-video-wrap');
          const primaryRankedVideo = rankedVideos[0] || null;
          const activeVideo = primaryRankedVideo?.video || null;
          const hasPlaybackVideo = !!(primaryRankedVideo && (primaryRankedVideo.insidePlayer || primaryRankedVideo.largePlaybackCandidate))
            || !!document.querySelector('#bilibili-player video, .bpx-player-container video, #playerWrap video, .player-container video, .bpx-player-video-wrap video');
          const playButton = document.querySelector('.bpx-player-ctrl-play, .bilibili-player-video-btn-start, [class*="ctrl-play"]');
          const danmakuToggle = document.querySelector('.bpx-player-ctrl-dm, .bpx-player-dm-switch, [class*="dm-switch"], [class*="ctrl-dm"]');
          const playbackRateNode = document.querySelector('.bpx-player-ctrl-playbackrate-result, .bpx-player-ctrl-playbackrate [class*="name"], .bpx-player-ctrl-playbackrate [class*="text"], .bpx-player-ctrl-playbackrate-menu .active, [class*="playbackrate"] [class*="name"], [class*="playbackrate"] [class*="text"], [class*="playbackrate"], [class*="speed"] .active, [class*="speed"] [aria-checked="true"]');
          const subtitleToggle = document.querySelector('.bpx-player-ctrl-subtitle, .bpx-player-subtitle-btn, [class*="subtitle-switch"], [class*="subtitle-btn"], [class*="subtitle"] button');
          const isDanmakuOff = document.documentElement.classList.contains('focus-hide-danmaku')
            || danmakuToggle?.getAttribute('aria-checked') === 'false'
            || danmakuToggle?.getAttribute('aria-pressed') === 'false'
            || danmakuToggle?.classList.contains('off')
            || danmakuToggle?.classList.contains('disabled');
          const textTracks = activeVideo && activeVideo.textTracks ? Array.from(activeVideo.textTracks) : [];
          const playerRoot = document.querySelector('.bpx-player-container, #bilibili-player, #playerWrap');
          const playerClassName = String(playerRoot?.className || '');
          const playButtonDescriptor = [playButton?.getAttribute('aria-label'), playButton?.getAttribute('title'), playButton?.textContent, playButton?.className].filter(Boolean).join(' ').toLowerCase();
          const uiSuggestsPlaying = /pause|暂停|icon-pause|state-pause|video-state-pause/.test(playButtonDescriptor);
          const uiSuggestsPaused = /play|播放|icon-play|state-play|video-state-play/.test(playButtonDescriptor);
          const videoSuggestsPlaying = !!activeVideo && !activeVideo.paused && !activeVideo.ended;
          const isFullscreen = !!document.fullscreenElement
            || activeVideo?.webkitPresentationMode === 'fullscreen'
            || activeVideo?.webkitPresentationMode === 'fullScreen'
            || /(^|\\s)(?:web-)?fullscreen(?:\\s|$)/.test(playerClassName);
          const hasSubtitleLayer = !!document.querySelector('.bpx-player-subtitle-wrap, [class*="subtitle-panel"], [class*="subtitle-item"], [class*="subtitle-wrap"]');
          const hasSubtitleTrack = !!subtitleToggle || hasSubtitleLayer || textTracks.length > 0;
          const isSubtitleOff = document.documentElement.classList.contains('focus-hide-subtitles')
            || (textTracks.length > 0 && textTracks.every((track) => track.mode === 'disabled'))
            || subtitleToggle?.getAttribute('aria-checked') === 'false'
            || subtitleToggle?.getAttribute('aria-pressed') === 'false'
            || subtitleToggle?.classList.contains('off')
            || subtitleToggle?.classList.contains('disabled');
          const rateText = String(playbackRateNode?.textContent || '').trim();
          const rateMatch = rateText.match(/(\\d+(?:\\.\\d+)?)\\s*x/i);
          const parsedRate = rateMatch ? Number(rateMatch[1]) : NaN;
          const rawPlaybackRate = Number(activeVideo?.playbackRate || 0);
          const isPlaying = activeVideo
            ? videoSuggestsPlaying
            : uiSuggestsPlaying && !uiSuggestsPaused;
          const playbackRate = Number.isFinite(rawPlaybackRate) && rawPlaybackRate > 0
            ? rawPlaybackRate
            : Number.isFinite(parsedRate) && parsedRate > 0
                ? parsedRate
                : 1;

          return {
            hasPlayer: hasPlayerShell || hasPlaybackVideo,
            pageURL: location.href,
            pageTitle: document.title || '',
            videoTitle: extractVideoTitle(),
            isPlaying: !!isPlaying,
            playbackRate,
            isDanmakuHidden: !!isDanmakuOff,
            hasSubtitles: !!hasSubtitleTrack,
            isSubtitleHidden: !!isSubtitleOff,
            isFullscreen: !!isFullscreen
          };
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard
                let self
            else {
                return
            }

            if let error {
                self.debugLog(
                    "refreshPlayerState.error",
                    fields: self.debugStateFields([
                        "error": String(describing: error)
                    ])
                )
            }

            guard
                let payload = value as? [String: Any],
                let hasPlayer = payload["hasPlayer"] as? Bool
            else {
                self.debugLog(
                    "refreshPlayerState.missingPayload",
                    fields: self.debugStateFields([
                        "valueType": value.map { String(describing: type(of: $0)) } ?? "nil"
                    ])
                )
                return
            }

            self.hasDetectedPlayer = hasPlayer || self.hasDetectedPlayer
            self.hasActiveVideoRoute = hasPlayer || self.hasActiveVideoRoute
            self.applyDetectedPageState(self.makeDetectedPageState(from: payload), fallbackURL: self.currentURL ?? self.pendingURL)
            self.isPlaying = payload["isPlaying"] as? Bool ?? false
            self.playbackRate = payload["playbackRate"] as? Double ?? 1.0
            self.isDanmakuHidden = payload["isDanmakuHidden"] as? Bool ?? false
            self.hasSubtitles = payload["hasSubtitles"] as? Bool ?? false
            self.isSubtitleHidden = payload["isSubtitleHidden"] as? Bool ?? false
            self.isImmersiveVideo = payload["isFullscreen"] as? Bool ?? self.isImmersiveVideo
            self.logPlayerStatePayload(payload)
        }
    }

    private func debugLog(_ event: String, fields: [String: String?] = [:]) {
        guard settingsStore.settings.debugMode else {
            return
        }

        let payload = fields
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(key)=\(value ?? "nil")"
            }
            .joined(separator: " ")

        if payload.isEmpty {
            print("[Focus Native Debug] \(event)")
        } else {
            print("[Focus Native Debug] \(event) \(payload)")
        }
    }

    private func debugStateFields(_ extra: [String: String?] = [:]) -> [String: String?] {
        var fields: [String: String?] = [
            "context": entryContextLabel(entryContext),
            "currentURL": currentURL?.absoluteString,
            "pendingURL": pendingURL?.absoluteString,
            "webViewURL": webView?.url?.absoluteString,
            "webViewTitle": webView?.title,
            "navigationTitle": navigationTitle,
            "hasActiveVideoRoute": debugBool(hasActiveVideoRoute),
            "hasDetectedPlayer": debugBool(hasDetectedPlayer),
            "isVideoPage": debugBool(isVideoPage),
            "showsNativeVideoControls": debugBool(showsNativeVideoControls),
            "isLoadingPage": debugBool(isLoadingPage)
        ]

        extra.forEach { key, value in
            fields[key] = value
        }
        return fields
    }

    private func logDetectedPageState(_ state: DetectedPageState, source: String) {
        let signature = [
            source,
            debugBool(state.hasPlayer),
            state.pageURLString ?? "",
            sanitizedPageTitle(state.videoTitle) ?? "",
            sanitizedPageTitle(state.pageTitle) ?? ""
        ].joined(separator: "|")

        guard signature != lastDebugDetectedPageStateSignature else {
            return
        }

        lastDebugDetectedPageStateSignature = signature
        debugLog(
            source,
            fields: debugStateFields([
                "detectedHasPlayer": debugBool(state.hasPlayer),
                "detectedPageURL": state.pageURLString,
                "detectedPageTitle": sanitizedPageTitle(state.pageTitle),
                "detectedVideoTitle": sanitizedPageTitle(state.videoTitle)
            ])
        )
    }

    private func logPlayerStatePayload(_ payload: [String: Any]) {
        let playbackRateValue = payload["playbackRate"] as? Double ?? 1.0
        let hasPlayerValue = payload["hasPlayer"] as? Bool ?? false
        let isPlayingValue = payload["isPlaying"] as? Bool ?? false
        let isFullscreenValue = payload["isFullscreen"] as? Bool ?? false
        let signature = [
            debugBool(hasPlayerValue),
            debugBool(isPlayingValue),
            String(format: "%.2f", playbackRateValue),
            debugBool(isFullscreenValue),
            String(payload["playerWidth"] as? Int ?? 0),
            String(payload["playerHeight"] as? Int ?? 0),
            sanitizedPageTitle(payload["videoTitle"] as? String) ?? "",
            payload["pageURL"] as? String ?? ""
        ].joined(separator: "|")

        guard signature != lastDebugPlayerStateSignature else {
            return
        }

        lastDebugPlayerStateSignature = signature
        debugLog(
            "refreshPlayerState",
            fields: debugStateFields([
                "payloadHasPlayer": debugBool(hasPlayerValue),
                "payloadIsPlaying": debugBool(isPlayingValue),
                "payloadPlaybackRate": String(format: "%.2f", playbackRateValue),
                "payloadIsFullscreen": debugBool(isFullscreenValue),
                "payloadPageURL": payload["pageURL"] as? String,
                "payloadPageTitle": sanitizedPageTitle(payload["pageTitle"] as? String),
                "payloadVideoTitle": sanitizedPageTitle(payload["videoTitle"] as? String),
                "payloadPlayerWidth": String(payload["playerWidth"] as? Int ?? 0),
                "payloadPlayerHeight": String(payload["playerHeight"] as? Int ?? 0),
                "payloadHasSubtitles": debugBool(payload["hasSubtitles"] as? Bool ?? false),
                "payloadIsSubtitleHidden": debugBool(payload["isSubtitleHidden"] as? Bool ?? false),
                "payloadIsDanmakuHidden": debugBool(payload["isDanmakuHidden"] as? Bool ?? false)
            ])
        )
    }

    private func debugBool(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private func entryContextLabel(_ context: EntryContext) -> String {
        switch context {
        case .dynamic:
            return "dynamic"
        case .search:
            return "search"
        case .my:
            return "my"
        }
    }

    private func navigationTypeLabel(_ navigationType: WKNavigationType) -> String {
        switch navigationType {
        case .linkActivated:
            return "linkActivated"
        case .formSubmitted:
            return "formSubmitted"
        case .backForward:
            return "backForward"
        case .reload:
            return "reload"
        case .formResubmitted:
            return "formResubmitted"
        case .other:
            return "other"
        @unknown default:
            return "unknown"
        }
    }
}

@MainActor
final class FocusSearchResultsViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded([SearchResultSection])
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var selectedFilter: SearchResultFilter = .all
    @Published private(set) var selectedVideoSort: SearchVideoSortOption = .default
    @Published private(set) var currentQuery: SearchQuery?
    @Published private(set) var isLoadingMore = false

    let availableFilters = SearchResultFilter.defaultOrder
    let availableVideoSortOptions = SearchVideoSortOption.allCases

    private let service: SearchResultService
    private var task: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var cache: [SearchResultFilter: SearchResultPage] = [:]
    private var nextPageByFilter: [SearchResultFilter: Int] = [:]

    init(service: SearchResultService) {
        self.service = service
    }

    deinit {
        task?.cancel()
        loadMoreTask?.cancel()
    }

    func search(_ query: SearchQuery) {
        currentQuery = query
        selectedFilter = .all
        selectedVideoSort = .default
        cache.removeAll()
        nextPageByFilter.removeAll()
        reload()
    }

    func reload() {
        guard let query = currentQuery, !query.keyword.isEmpty else {
            state = .idle
            return
        }

        task?.cancel()
        let filter = selectedFilter
        let videoSort = filter == .video ? selectedVideoSort : .default
        state = .loading
        task = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let page = try await service.fetchPage(
                    for: query,
                    filter: filter,
                    page: 1,
                    videoSort: videoSort
                )
                guard !Task.isCancelled else {
                    return
                }

                cachePage(page, for: filter)
                state = .loaded(page.sections)
            } catch let error as SearchResultService.ServiceError {
                guard !Task.isCancelled else {
                    return
                }
                state = .failed(error.localizedDescription)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                state = .failed(error.localizedDescription)
            }
        }
    }

    func refresh() async {
        cache[selectedFilter] = nil
        nextPageByFilter[selectedFilter] = nil
        reload()
    }

    func selectFilter(_ filter: SearchResultFilter) {
        guard selectedFilter != filter else {
            return
        }

        selectedFilter = filter
        if let cachedPage = cache[filter] {
            cachePage(cachedPage, for: filter)
            state = .loaded(cachedPage.sections)
            return
        }

        reload()
    }

    func selectVideoSort(_ sort: SearchVideoSortOption) {
        guard selectedVideoSort != sort else {
            return
        }

        selectedVideoSort = sort
        cache[.video] = nil
        nextPageByFilter[.video] = nil

        if selectedFilter == .video {
            reload()
        }
    }

    func loadMoreIfNeeded(currentItemID: String, in section: SearchResultSection) {
        guard
            let query = currentQuery,
            case let .loaded(sections) = state,
            let activeSection = sections.first(where: { $0.id == section.id }),
            shouldLoadMore(after: currentItemID, in: activeSection.items),
            !isLoadingMore
        else {
            return
        }

        let pagingFilter = selectedFilter == .all ? section.filter : selectedFilter
        guard pagingFilter == .video,
              let nextPage = nextPageByFilter[pagingFilter]
        else {
            return
        }

        isLoadingMore = true
        loadMoreTask?.cancel()
        loadMoreTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let currentVideoSort = pagingFilter == .video ? selectedVideoSort : .default
                let extraPage = try await service.fetchPage(
                    for: query,
                    filter: pagingFilter,
                    page: nextPage,
                    videoSort: currentVideoSort
                )
                guard !Task.isCancelled else {
                    return
                }

                let mergedSections = merge(
                    currentSections: sections,
                    extraSections: extraPage.sections,
                    targetFilter: pagingFilter
                )
                let mergedVideoSections = mergedSectionsForCache(
                    existing: cache[pagingFilter]?.sections ?? [],
                    incoming: extraPage.sections,
                    targetFilter: pagingFilter
                )
                cachePage(
                    SearchResultPage(
                        sections: mergedVideoSections,
                        nextPage: extraPage.nextPage
                    ),
                    for: pagingFilter
                )

                if selectedFilter == .all {
                    cachePage(
                        SearchResultPage(
                            sections: mergedSections,
                            nextPage: extraPage.nextPage
                        ),
                        for: .all
                    )
                }
                state = .loaded(mergedSections)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
            }

            if !Task.isCancelled {
                isLoadingMore = false
            }
        }
    }

    private func shouldLoadMore(after currentItemID: String, in items: [SearchResultItem]) -> Bool {
        guard let currentIndex = items.firstIndex(where: { $0.id == currentItemID }) else {
            return false
        }

        return currentIndex >= max(items.count - 4, 0)
    }

    private func merge(
        currentSections: [SearchResultSection],
        extraSections: [SearchResultSection],
        targetFilter: SearchResultFilter
    ) -> [SearchResultSection] {
        currentSections.map { section in
            guard section.filter == targetFilter,
                  let incomingSection = extraSections.first(where: { $0.filter == targetFilter })
            else {
                return section
            }

            return SearchResultSection(
                filter: section.filter,
                items: mergeItems(existing: section.items, incoming: incomingSection.items)
            )
        }
    }

    private func mergedSectionsForCache(
        existing: [SearchResultSection],
        incoming: [SearchResultSection],
        targetFilter: SearchResultFilter
    ) -> [SearchResultSection] {
        if existing.isEmpty {
            return incoming
        }

        return existing.map { section in
            guard section.filter == targetFilter,
                  let incomingSection = incoming.first(where: { $0.filter == targetFilter })
            else {
                return section
            }

            return SearchResultSection(
                filter: section.filter,
                items: mergeItems(existing: section.items, incoming: incomingSection.items)
            )
        }
    }

    private func mergeItems(existing: [SearchResultItem], incoming: [SearchResultItem]) -> [SearchResultItem] {
        var merged = existing
        var seen = Set(existing.map(\.id))

        for item in incoming where seen.insert(item.id).inserted {
            merged.append(item)
        }

        return merged
    }

    private func cachePage(_ page: SearchResultPage, for filter: SearchResultFilter) {
        cache[filter] = page
        nextPageByFilter[filter] = page.nextPage

        guard filter == .all,
              let videoSection = page.sections.first(where: { $0.filter == .video })
        else {
            return
        }

        let videoPage = SearchResultPage(
            sections: [videoSection],
            nextPage: page.nextPage
        )
        cache[.video] = videoPage
        nextPageByFilter[.video] = page.nextPage
    }
}

@MainActor
final class FocusDynamicFeedViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded([DynamicCard])
        case loginRequired(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isLoadingMore = false

    private let service: DynamicFeedService
    private var task: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var nextOffset: String?

    init(service: DynamicFeedService) {
        self.service = service
    }

    deinit {
        task?.cancel()
        loadMoreTask?.cancel()
    }

    func loadIfNeeded() {
        guard case .idle = state else {
            return
        }

        reload()
    }

    func reload() {
        task?.cancel()
        task = Task { [weak self] in
            await self?.performReload()
        }
    }

    func refresh() async {
        task?.cancel()
        task = nil
        await performReload()
    }

    func loadMoreIfNeeded(currentCardID: String) {
        guard
            case let .loaded(cards) = state,
            shouldLoadMore(after: currentCardID, in: cards),
            !isLoadingMore,
            let nextOffset,
            !nextOffset.isEmpty
        else {
            return
        }

        isLoadingMore = true
        let currentCards = cards

        loadMoreTask?.cancel()
        loadMoreTask = Task { [service] in
            do {
                let page = try await service.fetchFollowingFeedPage(offset: nextOffset)
                guard !Task.isCancelled else {
                    return
                }

                let mergedCards = mergeCards(currentCards, with: page.cards)
                self.nextOffset = page.nextOffset
                state = .loaded(mergedCards)
            } catch let error as DynamicFeedService.ServiceError {
                guard !Task.isCancelled else {
                    return
                }

                if error == .loginRequired {
                    self.nextOffset = nil
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }
            }

            if !Task.isCancelled {
                isLoadingMore = false
            }
        }
    }

    private func shouldLoadMore(after currentCardID: String, in cards: [DynamicCard]) -> Bool {
        guard let currentIndex = cards.firstIndex(where: { $0.id == currentCardID }) else {
            return false
        }

        return currentIndex >= max(cards.count - 4, 0)
    }

    private func performReload() async {
        loadMoreTask?.cancel()
        nextOffset = nil
        isLoadingMore = false
        state = .loading

        do {
            let page = try await service.fetchFollowingFeedPage()
            guard !Task.isCancelled else {
                return
            }

            var mergedCards = page.cards
            var finalNextOffset = page.nextOffset

            if let secondOffset = page.nextOffset, !secondOffset.isEmpty {
                do {
                    let secondPage = try await service.fetchFollowingFeedPage(offset: secondOffset)
                    guard !Task.isCancelled else {
                        return
                    }

                    mergedCards = mergeCards(mergedCards, with: secondPage.cards)
                    finalNextOffset = secondPage.nextOffset
                } catch {
                    finalNextOffset = page.nextOffset
                }
            }

            nextOffset = finalNextOffset
            state = .loaded(mergedCards)
        } catch let error as DynamicFeedService.ServiceError {
            guard !Task.isCancelled else {
                return
            }

            switch error {
            case .loginRequired:
                state = .loginRequired(error.localizedDescription)
            default:
                state = .failed(error.localizedDescription)
            }
        } catch {
            guard !Task.isCancelled else {
                return
            }
            state = .failed(error.localizedDescription)
        }
    }

    private func mergeCards(_ existingCards: [DynamicCard], with newCards: [DynamicCard]) -> [DynamicCard] {
        var mergedCards = existingCards
        var seen = Set(existingCards.map(\.id))

        for card in newCards where seen.insert(card.id).inserted {
            mergedCards.append(card)
        }

        return mergedCards
    }
}

private enum FocusNativePageKind: String {
    case video
    case opus

    func cacheKey(for url: URL) -> String {
        "\(rawValue)::\(url.absoluteString)"
    }
}

private enum FocusNativePageAugmentPayload {
    case video(FocusNativeVideoAugmentPayload)
    case opus(FocusNativeOpusAugmentPayload)

    var kind: FocusNativePageKind {
        switch self {
        case .video:
            return .video
        case .opus:
            return .opus
        }
    }

    var summary: String {
        switch self {
        case let .video(payload):
            let episodeCount = payload.groups.reduce(0) { $0 + $1.items.count }
            return "groups=\(payload.groups.count) episodes=\(episodeCount) comments=\(payload.comments.count)"
        case let .opus(payload):
            return "comments=\(payload.comments.count)"
        }
    }

    var javaScript: String {
        switch self {
        case let .video(payload):
            return payload.javaScript
        case let .opus(payload):
            return payload.javaScript
        }
    }
}

private struct FocusNativeVideoAugmentPayload: Encodable {
    let title: String
    let groups: [FocusNativeEpisodeGroupPayload]
    let comments: [FocusNativeCommentPayload]
}

private struct FocusNativeOpusAugmentPayload: Encodable {
    let comments: [FocusNativeCommentPayload]
}

private struct FocusNativeEpisodeGroupPayload: Encodable {
    let title: String
    let items: [FocusNativeEpisodeItemPayload]
}

private struct FocusNativeEpisodeItemPayload: Encodable {
    let title: String
    let subtitle: String
    let badge: String
    let targetURL: String
    let isCurrent: Bool
}

struct FocusNativeCommentPayload: Encodable {
    let author: String
    let avatarURL: String
    let content: String
    let likeText: String
    let replyText: String
    let timeText: String
}

fileprivate actor FocusNativePageAugmentService {
    private typealias JSONObject = [String: Any]

    fileprivate static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    private static let wbiMixinTable = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
        27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
        37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
        22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 52, 34, 44,
    ]

    private let cookieProvider: WebViewCookieSnapshotProvider
    private let session: URLSession
    private var cachedWbiKey: String?
    private var cachedWbiExpiration = Date.distantPast

    init(cookieProvider: WebViewCookieSnapshotProvider) {
        self.cookieProvider = cookieProvider
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 16
        configuration.timeoutIntervalForResource = 24
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    func loadPayload(for url: URL, kind: FocusNativePageKind) async -> FocusNativePageAugmentPayload? {
        switch kind {
        case .video:
            return await loadVideoPayload(for: url).map(FocusNativePageAugmentPayload.video)
        case .opus:
            return await loadOpusPayload(for: url).map(FocusNativePageAugmentPayload.opus)
        }
    }

    private func loadVideoPayload(for url: URL) async -> FocusNativeVideoAugmentPayload? {
        guard let bvid = Self.extractBvid(from: url) else {
            return nil
        }

        let referer = "https://www.bilibili.com/video/\(bvid)"
        guard
            let viewRoot = try? await requestObject(
                urlString: "https://api.bilibili.com/x/web-interface/view?bvid=\(bvid)",
                referer: referer
            ),
            viewRoot.intValue(at: "code") == 0,
            let data = viewRoot.dictionaryValue(at: "data")
        else {
            return nil
        }

        let title = data.stringValue(at: "title") ?? "视频"
        let currentPageNumber = Self.extractPageNumber(from: url)
        var groups: [FocusNativeEpisodeGroupPayload] = []

        let pages = parseVideoPages(from: data, bvid: bvid, currentPageNumber: currentPageNumber)
        if !pages.isEmpty {
            groups.append(
                FocusNativeEpisodeGroupPayload(
                    title: pages.count > 1 ? "分P · 共 \(pages.count) 条" : "分P",
                    items: pages
                )
            )
        }

        groups.append(contentsOf: parseEpisodeGroups(from: data, currentBvid: bvid))

        let aid = data.int64Value(at: "aid") ?? 0
        let comments = aid > 0
            ? (try? await fetchComments(oid: String(aid), type: 1, referer: referer)) ?? []
            : []

        let meaningfulGroups = groups.filter { $0.items.count > 1 }

        if meaningfulGroups.isEmpty, comments.isEmpty {
            return nil
        }

        return FocusNativeVideoAugmentPayload(
            title: title,
            groups: meaningfulGroups,
            comments: comments
        )
    }

    private func loadOpusPayload(for url: URL) async -> FocusNativeOpusAugmentPayload? {
        guard let opusID = Self.extractOpusID(from: url) else {
            return nil
        }

        let features = "onlyfansVote,onlyfansAssetsV2,decorationCard,htmlNewStyle,ugcDelete,editable,opusPrivateVisible"
        let detailURL = "https://api.bilibili.com/x/polymer/web-dynamic/v1/opus/detail?id=\(opusID)&timezone_offset=-480&features=\(features)"

        guard
            let detailRoot = try? await requestObject(urlString: detailURL, referer: url.absoluteString),
            detailRoot.intValue(at: "code") == 0
        else {
            return nil
        }

        let item = detailRoot.dictionaryValue(at: "data", "item")
        let basic = item?.dictionaryValue(at: "basic")
        let commentIdString = basic?.stringValue(at: "comment_id_str")
        let ridString = basic?.stringValue(at: "rid_str")
        let directCommentID = basic?.int64Value(at: "comment_id")
        let commentIDFromString = commentIdString.flatMap(Int64.init)
        let commentIDFromRid = ridString.flatMap(Int64.init)
        let commentIDFromOpus = Int64(opusID)
        let commentId: Int64
        if let directCommentID {
            commentId = directCommentID
        } else if let commentIDFromString {
            commentId = commentIDFromString
        } else if let commentIDFromRid {
            commentId = commentIDFromRid
        } else if let commentIDFromOpus {
            commentId = commentIDFromOpus
        } else {
            commentId = 0
        }
        let fallbackID = commentIdString ?? ridString ?? opusID

        let candidates = [commentId > 0 ? String(commentId) : nil, fallbackID]
            .compactMap { $0 }
            .reduce(into: [String]()) { partialResult, value in
                if !partialResult.contains(value) {
                    partialResult.append(value)
                }
            }

        for oid in candidates {
            for type in [17, 11, 12] {
                let comments = (try? await fetchComments(oid: oid, type: type, referer: url.absoluteString)) ?? []
                if !comments.isEmpty {
                    return FocusNativeOpusAugmentPayload(comments: comments)
                }
            }
        }

        return nil
    }

    private func parseVideoPages(from data: JSONObject, bvid: String, currentPageNumber: Int?) -> [FocusNativeEpisodeItemPayload] {
        guard let pages = data.arrayValue(at: "pages") else {
            return []
        }

        return pages.compactMap { page in
            let pageNumber = page.intValue(at: "page") ?? 1
            let title = page.stringValue(at: "part")?.nilIfBlank ?? "P\(pageNumber)"
            let duration = Self.formatDuration(page.int64Value(at: "duration") ?? 0)
            return FocusNativeEpisodeItemPayload(
                title: title,
                subtitle: "P\(pageNumber)",
                badge: duration,
                targetURL: "https://www.bilibili.com/video/\(bvid)?p=\(pageNumber)",
                isCurrent: currentPageNumber == pageNumber
            )
        }
    }

    private func parseEpisodeGroups(from data: JSONObject, currentBvid: String) -> [FocusNativeEpisodeGroupPayload] {
        guard let ugcSeason = data.dictionaryValue(at: "ugc_season") else {
            return []
        }

        let seasonTitle = ugcSeason.stringValue(at: "title")?.nilIfBlank ?? "选集"
        let sections = ugcSeason.arrayValue(at: "sections") ?? []

        return sections.compactMap { section in
            let groupTitle = section.stringValue(at: "title")?.nilIfBlank ?? seasonTitle
            let episodes = (section.arrayValue(at: "episodes") ?? []).compactMap { episode -> FocusNativeEpisodeItemPayload? in
                guard let bvid = episode.stringValue(at: "bvid")?.nilIfBlank else {
                    return nil
                }

                let arc = episode.dictionaryValue(at: "arc")
                let rawTitle = episode.stringValue(at: "title")
                    ?? episode.stringValue(at: "long_title")
                    ?? arc?.stringValue(at: "title")
                let badge = episode.stringValue(at: "badge")
                    ?? episode.dictionaryValue(at: "badge_info")?.stringValue(at: "text")
                    ?? ""

                return FocusNativeEpisodeItemPayload(
                    title: rawTitle?.nilIfBlank ?? "视频",
                    subtitle: bvid,
                    badge: badge,
                    targetURL: "https://www.bilibili.com/video/\(bvid)",
                    isCurrent: bvid.caseInsensitiveCompare(currentBvid) == .orderedSame
                )
            }

            guard !episodes.isEmpty else {
                return nil
            }

            return FocusNativeEpisodeGroupPayload(title: groupTitle, items: episodes)
        }
    }

    private func fetchComments(oid: String, type: Int, referer: String) async throws -> [FocusNativeCommentPayload] {
        let query = try await signedWbiQuery(
            parameters: [
                "type": String(type),
                "oid": oid,
                "pn": "1",
                "ps": "20",
                "sort": "2",
            ],
            referer: referer
        )
        let urlString = "https://api.bilibili.com/x/v2/reply/wbi/main?\(query)"
        let root = try await requestObject(urlString: urlString, referer: referer)
        guard root.intValue(at: "code") == 0 else {
            return []
        }

        let replies = root.arrayValue(at: "data", "replies") ?? []
        return replies.compactMap(parseComment(from:))
    }

    private func parseComment(from object: JSONObject) -> FocusNativeCommentPayload? {
        guard
            let member = object.dictionaryValue(at: "member"),
            let content = object.dictionaryValue(at: "content"),
            let message = content.stringValue(at: "message")?.nilIfBlank
        else {
            return nil
        }

        let likeCount = object.int64Value(at: "like") ?? 0
        let replyCount = object.int64Value(at: "rcount") ?? 0
        let publishTime = object.int64Value(at: "ctime") ?? 0

        return FocusNativeCommentPayload(
            author: member.stringValue(at: "uname")?.nilIfBlank ?? "用户",
            avatarURL: member.stringValue(at: "avatar") ?? "",
            content: message,
            likeText: likeCount > 0 ? "\(Self.formatCount(likeCount))赞" : "",
            replyText: replyCount > 0 ? "\(Self.formatCount(replyCount))回复" : "",
            timeText: Self.formatCommentTime(publishTime)
        )
    }

    private func requestObject(urlString: String, referer: String?) async throws -> JSONObject {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let data = try await requestData(url: url, referer: referer)
        let rawObject = try JSONSerialization.jsonObject(with: data)
        guard let object = rawObject as? JSONObject else {
            throw URLError(.cannotParseResponse)
        }
        return object
    }

    private func requestData(url: URL, referer: String?) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 18
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(referer ?? "https://www.bilibili.com/", forHTTPHeaderField: "Referer")

        let cookies = await cookieProvider.loadCookies()
        if !cookies.isEmpty {
            let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func signedWbiQuery(parameters: [String: String], referer: String) async throws -> String {
        let key = try await fetchWbiKey(referer: referer)
        var items = parameters
        items["wts"] = String(Int(Date().timeIntervalSince1970))
        let query = items.keys.sorted().map { key in
            "\(key)=\(items[key] ?? "")"
        }.joined(separator: "&")
        let wrid = Self.md5Hex(query + key)
        return "\(query)&w_rid=\(wrid)"
    }

    private func fetchWbiKey(referer: String) async throws -> String {
        let now = Date()
        if let cachedWbiKey, now < cachedWbiExpiration {
            return cachedWbiKey
        }

        let nav = try await requestObject(
            urlString: "https://api.bilibili.com/x/web-interface/nav",
            referer: referer
        )
        guard
            let imgURL = nav.stringValue(at: "data", "wbi_img", "img_url"),
            let subURL = nav.stringValue(at: "data", "wbi_img", "sub_url")
        else {
            throw URLError(.cannotParseResponse)
        }

        let imgKey = imgURL.substringAfterLast("/").substringBefore(".")
        let subKey = subURL.substringAfterLast("/").substringBefore(".")
        let raw = imgKey + subKey
        let mixed = Self.wbiMixinTable.reduce(into: "") { partialResult, index in
            guard index < raw.count else {
                return
            }
            partialResult.append(raw[raw.index(raw.startIndex, offsetBy: index)])
        }

        let resolved = String(mixed.prefix(32))
        cachedWbiKey = resolved
        cachedWbiExpiration = now.addingTimeInterval(25 * 60)
        return resolved
    }

    private static func extractBvid(from url: URL) -> String? {
        let components = url.path.split(separator: "/")
        guard
            let videoIndex = components.firstIndex(of: "video"),
            components.indices.contains(components.index(after: videoIndex))
        else {
            return nil
        }

        let candidate = String(components[components.index(after: videoIndex)])
        return candidate.nilIfBlank
    }

    private static func extractOpusID(from url: URL) -> String? {
        let host = url.host?.lowercased()
        let components = url.path.split(separator: "/")

        if (host == "www.bilibili.com" || host == "bilibili.com" || host == "m.bilibili.com"),
           let opusIndex = components.firstIndex(of: "opus"),
           components.indices.contains(components.index(after: opusIndex))
        {
            return String(components[components.index(after: opusIndex)]).nilIfBlank
        }

        if host == "t.bilibili.com", let first = components.first {
            let candidate = String(first)
            return candidate.allSatisfy(\.isNumber) ? candidate : nil
        }

        return nil
    }

    private static func extractPageNumber(from url: URL) -> Int? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        return components.queryItems?
            .first(where: { $0.name.caseInsensitiveCompare("p") == .orderedSame })?
            .value
            .flatMap(Int.init)
    }

    private static func formatDuration(_ seconds: Int64) -> String {
        guard seconds > 0 else {
            return ""
        }

        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return String(format: "%lld:%02lld:%02lld", hours, minutes, remainingSeconds)
        }

        return String(format: "%02lld:%02lld", minutes, remainingSeconds)
    }

    private static func formatCount(_ value: Int64) -> String {
        switch value {
        case 100_000_000...:
            return String(format: "%.1f亿", Double(value) / 100_000_000).replacingOccurrences(of: ".0", with: "")
        case 10_000...:
            return String(format: "%.1f万", Double(value) / 10_000).replacingOccurrences(of: ".0", with: "")
        default:
            return "\(value)"
        }
    }

    private static func formatCommentTime(_ seconds: Int64) -> String {
        guard seconds > 0 else {
            return ""
        }

        let now = Int64(Date().timeIntervalSince1970)
        let delta = max(now - seconds, 0)

        switch delta {
        case 0 ..< 60:
            return "刚刚"
        case 60 ..< 3600:
            return "\(max(delta / 60, 1))分钟前"
        case 3600 ..< 86_400:
            return "\(max(delta / 3600, 1))小时前"
        case 86_400 ..< 604_800:
            return "\(max(delta / 86_400, 1))天前"
        default:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
        }
    }

    private static func md5Hex(_ value: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension FocusNativeVideoAugmentPayload {
    var javaScript: String {
        let payloadJSON = focusJSONString
        return #"""
        (() => {
          const payload = \#(payloadJSON);
          const styleId = 'focus-native-video-augment-style';
          const rootId = 'focus-native-video-augment';
          if (!payload || ((!payload.groups || payload.groups.length === 0) && (!payload.comments || payload.comments.length === 0))) {
            document.getElementById(rootId)?.remove?.();
            return;
          }

          const escapeHTML = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({
            '&': '&amp;',
            '<': '&lt;',
            '>': '&gt;',
            '"': '&quot;',
            "'": '&#39;'
          })[char] || char);
          const nl2br = (value) => escapeHTML(value).replace(/\n/g, '<br>');
          const ensureStyle = () => {
            let style = document.getElementById(styleId);
            if (!style) {
              style = document.createElement('style');
              style.id = styleId;
              document.head.appendChild(style);
            }
            style.textContent = `
              #${rootId} {
                display: block !important;
                width: 100% !important;
                box-sizing: border-box !important;
                padding: 8px 16px 24px !important;
              }
              #${rootId} .focus-native-section {
                margin-top: 8px !important;
                padding: 16px !important;
                border-radius: 20px !important;
                background: rgba(255, 255, 255, 0.97) !important;
                border: 1px solid rgba(15, 23, 42, 0.06) !important;
                box-shadow: 0 14px 32px rgba(15, 23, 42, 0.05) !important;
                box-sizing: border-box !important;
              }
              #${rootId} .focus-native-section:first-child {
                margin-top: 0 !important;
              }
              html[data-focus-theme='dark'] #${rootId} .focus-native-section {
                background: rgba(23, 27, 35, 0.94) !important;
                border-color: rgba(255, 255, 255, 0.08) !important;
                box-shadow: 0 12px 24px rgba(0, 0, 0, 0.22) !important;
              }
              #${rootId} .focus-native-header {
                display: flex !important;
                align-items: center !important;
                justify-content: space-between !important;
                gap: 12px !important;
                margin-bottom: 12px !important;
              }
              #${rootId} .focus-native-title {
                font-size: 17px !important;
                font-weight: 700 !important;
                line-height: 1.3 !important;
                color: #111827 !important;
              }
              html[data-focus-theme='dark'] #${rootId} .focus-native-title {
                color: #f8fafc !important;
              }
              #${rootId} .focus-native-scroller {
                display: flex !important;
                gap: 10px !important;
                overflow-x: auto !important;
                overflow-y: hidden !important;
                padding: 2px 0 2px !important;
                scroll-snap-type: x proximity !important;
                -webkit-overflow-scrolling: touch !important;
              }
              #${rootId} .focus-native-scroller::-webkit-scrollbar {
                display: none !important;
              }
              #${rootId} .focus-native-episode-card {
                flex: 0 0 168px !important;
                min-height: 92px !important;
                padding: 12px !important;
                border-radius: 16px !important;
                background: rgba(248, 250, 252, 0.98) !important;
                border: 1px solid rgba(15, 23, 42, 0.06) !important;
                box-sizing: border-box !important;
                text-decoration: none !important;
                color: inherit !important;
                scroll-snap-align: start !important;
              }
              html[data-focus-theme='dark'] #${rootId} .focus-native-episode-card {
                background: rgba(30, 41, 59, 0.94) !important;
                border-color: rgba(255, 255, 255, 0.06) !important;
              }
              #${rootId} .focus-native-episode-card.is-current {
                border-color: rgba(251, 114, 153, 0.44) !important;
                box-shadow: inset 0 0 0 1px rgba(251, 114, 153, 0.22) !important;
              }
              #${rootId} .focus-native-episode-subtitle {
                font-size: 12px !important;
                font-weight: 700 !important;
                line-height: 1.2 !important;
                color: #fb7299 !important;
                margin-bottom: 8px !important;
              }
              #${rootId} .focus-native-episode-text {
                font-size: 14px !important;
                font-weight: 600 !important;
                line-height: 1.42 !important;
                color: #0f172a !important;
                display: -webkit-box !important;
                -webkit-line-clamp: 2 !important;
                -webkit-box-orient: vertical !important;
                overflow: hidden !important;
                word-break: break-word !important;
              }
              html[data-focus-theme='dark'] #${rootId} .focus-native-episode-text {
                color: #f8fafc !important;
              }
              #${rootId} .focus-native-episode-badge {
                margin-top: 10px !important;
                font-size: 12px !important;
                line-height: 1.2 !important;
                color: rgba(100, 116, 139, 0.92) !important;
              }
              html[data-focus-theme='dark'] #${rootId} .focus-native-episode-badge {
                color: rgba(226, 232, 240, 0.72) !important;
              }
              #${rootId} .focus-native-comment-list {
                display: grid !important;
                gap: 12px !important;
              }
              #${rootId} .focus-native-comment-card {
                display: flex !important;
                gap: 12px !important;
                padding: 14px !important;
                border-radius: 16px !important;
                background: rgba(248, 250, 252, 0.94) !important;
                border: 1px solid rgba(15, 23, 42, 0.05) !important;
                box-sizing: border-box !important;
              }
              html[data-focus-theme='dark'] #${rootId} .focus-native-comment-card {
                background: rgba(30, 41, 59, 0.9) !important;
                border-color: rgba(255, 255, 255, 0.06) !important;
              }
              #${rootId} .focus-native-avatar {
                flex: 0 0 38px !important;
                width: 38px !important;
                height: 38px !important;
                border-radius: 999px !important;
                overflow: hidden !important;
                background: rgba(148, 163, 184, 0.16) !important;
              }
              #${rootId} .focus-native-avatar img {
                display: block !important;
                width: 100% !important;
                height: 100% !important;
                object-fit: cover !important;
              }
              #${rootId} .focus-native-comment-main {
                min-width: 0 !important;
                flex: 1 1 auto !important;
              }
              #${rootId} .focus-native-comment-author {
                font-size: 14px !important;
                font-weight: 700 !important;
                line-height: 1.25 !important;
                color: #fb7299 !important;
                margin-bottom: 6px !important;
              }
              #${rootId} .focus-native-comment-content {
                font-size: 15px !important;
                line-height: 1.6 !important;
                color: #0f172a !important;
                word-break: break-word !important;
              }
              html[data-focus-theme='dark'] #${rootId} .focus-native-comment-content {
                color: #f8fafc !important;
              }
              #${rootId} .focus-native-comment-meta {
                margin-top: 8px !important;
                font-size: 12px !important;
                line-height: 1.3 !important;
                color: rgba(100, 116, 139, 0.92) !important;
              }
              html[data-focus-theme='dark'] #${rootId} .focus-native-comment-meta {
                color: rgba(226, 232, 240, 0.72) !important;
              }
              #${rootId} .focus-native-footnote {
                margin-top: 12px !important;
                font-size: 12px !important;
                color: rgba(100, 116, 139, 0.92) !important;
              }
              html[data-focus-theme='dark'] #${rootId} .focus-native-footnote {
                color: rgba(226, 232, 240, 0.68) !important;
              }
            `;
          };

          const hideOriginalSections = () => {
            if (payload.groups && payload.groups.length > 0) {
              [
                '.video-pod',
                '.video-pod__head',
                '.video-pod__header',
                '.video-pod__body',
                '.video-pod__list',
                '.multi-page',
                '[class*="multi-page"]',
                '[class*="episode-list"]',
                '[class*="part-list"]',
                '[class*="page-list"]'
              ].forEach((selector) => {
                document.querySelectorAll(selector).forEach((node) => {
                  if (!node.closest(`#${rootId}`)) {
                    node.style.setProperty('display', 'none', 'important');
                  }
                });
              });
            }
            if (payload.comments && payload.comments.length > 0) {
              [
                '#commentapp',
                '#commentapp > *',
                'bili-comments',
                '.comment-container',
                '.bb-comment'
              ].forEach((selector) => {
                document.querySelectorAll(selector).forEach((node) => {
                  if (!node.closest(`#${rootId}`)) {
                    node.style.setProperty('display', 'none', 'important');
                  }
                });
              });
            }
          };

          const buildGroupsHTML = () => (payload.groups || []).map((group) => {
            const items = (group.items || []).map((item) => `
              <a class="focus-native-episode-card${item.isCurrent ? ' is-current' : ''}" href="${escapeHTML(item.targetURL)}">
                <div class="focus-native-episode-subtitle">${escapeHTML(item.subtitle)}</div>
                <div class="focus-native-episode-text">${escapeHTML(item.title)}</div>
                ${item.badge ? `<div class="focus-native-episode-badge">${escapeHTML(item.badge)}</div>` : ''}
              </a>
            `).join('');
            return `
              <section class="focus-native-section">
                <div class="focus-native-header">
                  <div class="focus-native-title">${escapeHTML(group.title)}</div>
                </div>
                <div class="focus-native-scroller">${items}</div>
              </section>
            `;
          }).join('');

          const buildCommentsHTML = () => {
            if (!payload.comments || payload.comments.length === 0) {
              return '';
            }
            const items = payload.comments.map((comment) => `
              <article class="focus-native-comment-card">
                <div class="focus-native-avatar">
                  ${comment.avatarURL ? `<img src="${escapeHTML(comment.avatarURL)}" alt="">` : ''}
                </div>
                <div class="focus-native-comment-main">
                  <div class="focus-native-comment-author">${escapeHTML(comment.author)}</div>
                  <div class="focus-native-comment-content">${nl2br(comment.content)}</div>
                  <div class="focus-native-comment-meta">${[comment.timeText, comment.likeText, comment.replyText].filter(Boolean).map(escapeHTML).join(' · ')}</div>
                </div>
              </article>
            `).join('');
            return `
              <section class="focus-native-section">
                <div class="focus-native-header">
                  <div class="focus-native-title">评论</div>
                </div>
                <div class="focus-native-comment-list">${items}</div>
                <div class="focus-native-footnote">当前展示前 ${payload.comments.length} 条评论。</div>
              </section>
            `;
          };

          ensureStyle();
          const preservedScrollY = window.scrollY || document.documentElement.scrollTop || document.body.scrollTop || 0;
          const root = document.getElementById(rootId) || document.createElement('section');
          root.id = rootId;
          root.style.setProperty('display', 'block', 'important');
          root.style.setProperty('width', '100%', 'important');
          root.style.setProperty('visibility', 'visible', 'important');
          root.style.setProperty('opacity', '1', 'important');
          root.innerHTML = `${buildGroupsHTML()}${buildCommentsHTML()}`;

          const commentAnchor = payload.comments && payload.comments.length > 0
            ? document.querySelector('#commentapp')
            : null;
          const episodeAnchor = payload.groups && payload.groups.length > 0
            ? document.querySelector('.video-pod, .multi-page, [class*="episode-list"], [class*="part-list"], [class*="page-list"]')
            : null;
          const viewbox = document.querySelector('#viewbox_report');
          const leftContainer = viewbox?.closest('.left-container') || document.querySelector('.left-container');

          if (commentAnchor && commentAnchor.parentNode) {
            commentAnchor.parentNode.insertBefore(root, commentAnchor);
          } else if (episodeAnchor && episodeAnchor.parentNode) {
            episodeAnchor.parentNode.insertBefore(root, episodeAnchor);
          } else if (viewbox && viewbox.parentNode) {
            viewbox.parentNode.insertBefore(root, viewbox.nextSibling);
          } else if (leftContainer) {
            leftContainer.appendChild(root);
          } else {
            (document.querySelector('main') || document.body || document.documentElement).appendChild(root);
          }

          hideOriginalSections();

          const restoreScroll = () => {
            const currentY = window.scrollY || document.documentElement.scrollTop || document.body.scrollTop || 0;
            if (Math.abs(currentY - preservedScrollY) > 1) {
              window.scrollTo(0, preservedScrollY);
            }
          };
          requestAnimationFrame(restoreScroll);
          setTimeout(restoreScroll, 80);
          setTimeout(restoreScroll, 260);
        })();
        """#
    }
}

private extension FocusNativeOpusAugmentPayload {
    var javaScript: String {
        let payloadJSON = focusJSONString
        return #"""
        (() => {
          const payload = \#(payloadJSON);
          const styleId = 'focus-native-opus-comments-style';
          const rootId = 'focus-native-opus-comments';
          if (!payload || !payload.comments || payload.comments.length === 0) {
            return;
          }

          const escapeHTML = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({
            '&': '&amp;',
            '<': '&lt;',
            '>': '&gt;',
            '"': '&quot;',
            "'": '&#39;'
          })[char] || char);
          const nl2br = (value) => escapeHTML(value).replace(/\n/g, '<br>');
          let style = document.getElementById(styleId);
          if (!style) {
            style = document.createElement('style');
            style.id = styleId;
            document.head.appendChild(style);
          }
          style.textContent = `
            #${rootId} {
              display: block !important;
              width: 100% !important;
              box-sizing: border-box !important;
              padding: 0 12px 24px !important;
            }
            #${rootId} .focus-native-opus-comments {
              padding: 16px !important;
              border-radius: 20px !important;
              background: rgba(255, 255, 255, 0.97) !important;
              border: 1px solid rgba(15, 23, 42, 0.06) !important;
              box-shadow: 0 14px 32px rgba(15, 23, 42, 0.05) !important;
            }
            html[data-focus-theme='dark'] #${rootId} .focus-native-opus-comments {
              background: rgba(23, 27, 35, 0.94) !important;
              border-color: rgba(255, 255, 255, 0.08) !important;
            }
            #${rootId} .focus-native-opus-title {
              margin-bottom: 12px !important;
              font-size: 17px !important;
              font-weight: 700 !important;
              line-height: 1.3 !important;
              color: #111827 !important;
            }
            html[data-focus-theme='dark'] #${rootId} .focus-native-opus-title {
              color: #f8fafc !important;
            }
            #${rootId} .focus-native-opus-list {
              display: grid !important;
              gap: 12px !important;
            }
            #${rootId} .focus-native-opus-item {
              display: flex !important;
              gap: 12px !important;
              padding: 14px !important;
              border-radius: 16px !important;
              background: rgba(248, 250, 252, 0.94) !important;
              border: 1px solid rgba(15, 23, 42, 0.05) !important;
            }
            html[data-focus-theme='dark'] #${rootId} .focus-native-opus-item {
              background: rgba(30, 41, 59, 0.9) !important;
              border-color: rgba(255, 255, 255, 0.06) !important;
            }
            #${rootId} .focus-native-opus-avatar {
              flex: 0 0 38px !important;
              width: 38px !important;
              height: 38px !important;
              border-radius: 999px !important;
              overflow: hidden !important;
              background: rgba(148, 163, 184, 0.16) !important;
            }
            #${rootId} .focus-native-opus-avatar img {
              display: block !important;
              width: 100% !important;
              height: 100% !important;
              object-fit: cover !important;
            }
            #${rootId} .focus-native-opus-main {
              min-width: 0 !important;
              flex: 1 1 auto !important;
            }
            #${rootId} .focus-native-opus-author {
              font-size: 14px !important;
              font-weight: 700 !important;
              line-height: 1.25 !important;
              color: #fb7299 !important;
              margin-bottom: 6px !important;
            }
            #${rootId} .focus-native-opus-content {
              font-size: 15px !important;
              line-height: 1.58 !important;
              color: #0f172a !important;
              word-break: break-word !important;
            }
            html[data-focus-theme='dark'] #${rootId} .focus-native-opus-content {
              color: #f8fafc !important;
            }
            #${rootId} .focus-native-opus-meta {
              margin-top: 8px !important;
              font-size: 12px !important;
              line-height: 1.3 !important;
              color: rgba(100, 116, 139, 0.92) !important;
            }
            html[data-focus-theme='dark'] #${rootId} .focus-native-opus-meta {
              color: rgba(226, 232, 240, 0.72) !important;
            }
          `;

          [
            '#commentapp',
            '#commentapp > *',
            'bili-comments',
            '.comment-container',
            '.bb-comment'
          ].forEach((selector) => {
            document.querySelectorAll(selector).forEach((node) => {
              if (!node.closest(`#${rootId}`)) {
                node.style.setProperty('display', 'none', 'important');
              }
            });
          });

          const root = document.getElementById(rootId) || document.createElement('section');
          root.id = rootId;
          root.innerHTML = `
            <section class="focus-native-opus-comments">
              <div class="focus-native-opus-title">评论</div>
              <div class="focus-native-opus-list">
                ${payload.comments.map((comment) => `
                  <article class="focus-native-opus-item">
                    <div class="focus-native-opus-avatar">
                      ${comment.avatarURL ? `<img src="${escapeHTML(comment.avatarURL)}" alt="">` : ''}
                    </div>
                    <div class="focus-native-opus-main">
                      <div class="focus-native-opus-author">${escapeHTML(comment.author)}</div>
                      <div class="focus-native-opus-content">${nl2br(comment.content)}</div>
                      <div class="focus-native-opus-meta">${[comment.timeText, comment.likeText, comment.replyText].filter(Boolean).map(escapeHTML).join(' · ')}</div>
                    </div>
                  </article>
                `).join('')}
              </div>
            </section>
          `;

          const anchor = document.querySelector('.opus-detail__primary')
            || document.querySelector('.opus-module-content')
            || document.querySelector('.bili-opus-view');
          if (anchor && anchor.parentNode) {
            anchor.parentNode.insertBefore(root, anchor.nextSibling);
          } else {
            (document.querySelector('main') || document.body || document.documentElement).appendChild(root);
          }
        })();
        """#
    }
}

struct FocusMyProfile {
    let mid: Int64
    let name: String
    let avatarURL: URL?
    let level: Int
    let following: Int64
    let followers: Int64
}

struct FocusMyHistoryItem: Identifiable {
    let id: String
    let title: String
    let coverURL: URL?
    let bvid: String
    let authorName: String
    let viewAt: Int64
    let progress: Int64
    let duration: Int64

    var videoURL: URL? {
        guard !bvid.isEmpty else {
            return nil
        }
        return URL(string: "https://www.bilibili.com/video/\(bvid)")
    }
}

struct FocusMyFolder: Identifiable {
    let id: Int64
    let title: String
    let mediaCount: Int
    let coverURL: URL?
}

struct FocusMyPage {
    let profile: FocusMyProfile
    let history: [FocusMyHistoryItem]
    let folders: [FocusMyFolder]
}

struct FocusUserSpaceProfile {
    let mid: Int64
    let name: String
    let avatarURL: URL?
    let sign: String
    let level: Int
    let following: Int64
    let followers: Int64
    let videoCount: Int
    let articleCount: Int
}

struct FocusUserSpaceVideo: Identifiable {
    let id: String
    let bvid: String
    let title: String
    let coverURL: URL?
    let playText: String
    let durationText: String
    let publishText: String

    var targetURL: URL? {
        guard !bvid.isEmpty else {
            return nil
        }
        return URL(string: "https://www.bilibili.com/video/\(bvid)")
    }
}

struct FocusUserSpaceCollection: Identifiable {
    enum Kind: String {
        case season
        case series

        var title: String {
            switch self {
            case .season:
                return "合集"
            case .series:
                return "系列"
            }
        }
    }

    let id: String
    let ownerMID: Int64
    let rawID: Int64
    let kind: Kind
    let title: String
    let subtitle: String
    let description: String
    let badgeText: String
    let coverURL: URL?
    let itemCount: Int
}

struct FocusUserSpaceArticle: Identifiable {
    let id: String
    let title: String
    let summary: String
    let coverURL: URL?
    let publishText: String
    let viewText: String
    let targetURL: URL
}

struct FocusUserSpacePage {
    let profile: FocusUserSpaceProfile
    let videos: [FocusUserSpaceVideo]
    let collections: [FocusUserSpaceCollection]
    let articles: [FocusUserSpaceArticle]
    let nextVideoPage: Int?
}

struct FocusUserCollectionPage {
    let collection: FocusUserSpaceCollection
    let videos: [FocusUserSpaceVideo]
    let nextPage: Int?
}

struct FocusArticleAuthor {
    let mid: Int64
    let name: String
    let avatarURL: URL?
}

struct FocusArticleStats {
    let views: Int64
    let likes: Int64
    let coins: Int64
    let favorites: Int64
    let comments: Int64
}

struct FocusArticlePage {
    let cvid: Int64
    let title: String
    let author: FocusArticleAuthor
    let publishTime: Int64
    let stats: FocusArticleStats
    let bannerURL: URL?
    let tags: [String]
    let htmlContent: String
}

struct FocusOpusAuthor {
    let name: String
    let mid: Int64
    let avatarURL: URL?
}

struct FocusOpusTextNode {
    let text: String
    let bold: Bool
    let linkURL: URL?
    let emojiURL: URL?
}

struct FocusOpusImage: Identifiable {
    let id: String
    let url: URL?
    let width: Int
    let height: Int

    var aspectRatio: CGFloat? {
        guard width > 0, height > 0 else {
            return nil
        }
        return CGFloat(width) / CGFloat(height)
    }
}

enum FocusOpusBlock {
    case text([FocusOpusTextNode])
    case image([FocusOpusImage])
    case code(lang: String, content: String)
}

struct FocusOpusParagraph: Identifiable {
    let id = UUID()
    let blocks: [FocusOpusBlock]
}

struct FocusOpusDetailPage {
    let id: String
    let author: FocusOpusAuthor
    let publishTime: String
    let paragraphs: [FocusOpusParagraph]
    let comments: [FocusNativeCommentPayload]
}

private struct FocusHistoryCursor {
    let max: Int64
    let viewAt: Int64
    let business: String

    var hasMore: Bool {
        max > 0 || viewAt > 0 || !business.isEmpty
    }
}

private struct FocusMyHistoryPage {
    let items: [FocusMyHistoryItem]
    let nextCursor: FocusHistoryCursor?
}

private enum FocusMyServiceError: Error {
    case loginRequired
    case message(String)
}

final class FocusMyDataService: @unchecked Sendable {
    private let cookieProvider: WebViewCookieSnapshotProvider
    private let session: URLSession

    init(cookieProvider: WebViewCookieSnapshotProvider) {
        self.cookieProvider = cookieProvider
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 16
        configuration.timeoutIntervalForResource = 24
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func resolveLoggedInNavData() async throws -> [String: Any] {
        for delay in [0 as UInt64, 220_000_000, 520_000_000, 950_000_000] {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }

            _ = await cookieProvider.refreshSnapshotIfNeeded()
            let nav = try await requestObject(
                urlString: "https://api.bilibili.com/x/web-interface/nav",
                referer: "https://www.bilibili.com/"
            )
            let code = nav.intValue(at: "code") ?? -1
            let data = nav.dictionaryValue(at: "data")
            let isLogin = code == 0 && (data?.boolValue(at: "isLogin") ?? false)
            if isLogin, let data {
                return data
            }
        }

        throw FocusMyServiceError.loginRequired
    }

    func fetchRelation(mid: Int64) async throws -> (following: Int64, followers: Int64) {
        let relation = try await requestObject(
            urlString: "https://api.bilibili.com/x/relation/stat?vmid=\(mid)",
            referer: "https://space.bilibili.com/\(mid)"
        )
        return (
            relation.int64Value(at: "data", "following") ?? 0,
            relation.int64Value(at: "data", "follower") ?? 0
        )
    }

    fileprivate func fetchHistoryPage(pageSize: Int, cursor: FocusHistoryCursor? = nil) async throws -> FocusMyHistoryPage {
        var components = URLComponents(string: "https://api.bilibili.com/x/web-interface/history/cursor")
        var queryItems = [URLQueryItem(name: "ps", value: "\(pageSize)")]
        if let cursor {
            if cursor.max > 0 {
                queryItems.append(URLQueryItem(name: "max", value: "\(cursor.max)"))
            }
            if cursor.viewAt > 0 {
                queryItems.append(URLQueryItem(name: "view_at", value: "\(cursor.viewAt)"))
            }
            if !cursor.business.isEmpty {
                queryItems.append(URLQueryItem(name: "business", value: cursor.business))
            }
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw FocusMyServiceError.message("历史记录请求地址无效")
        }

        let root = try await requestObject(url: url, referer: "https://www.bilibili.com/")
        let code = root.intValue(at: "code") ?? -1
        if code == -101 {
            throw FocusMyServiceError.loginRequired
        }
        guard code == 0 else {
            throw FocusMyServiceError.message(root.stringValue(at: "message") ?? "历史记录加载失败")
        }

        let list = root.arrayValue(at: "data", "list") ?? []
        let rawItems = list.compactMap { item -> FocusMyHistoryItem? in
            let history = item.dictionaryValue(at: "history")
            let bvid = history?.stringValue(at: "bvid") ?? ""
            guard !bvid.isEmpty else {
                return nil
            }
            let coverString = item.stringValue(at: "cover")?.nilIfBlank
                ?? history?.stringValue(at: "cover")?.nilIfBlank
                ?? Self.firstString(in: item["covers"])?.nilIfBlank
                ?? Self.firstString(in: history?["covers"])?.nilIfBlank
            return FocusMyHistoryItem(
                id: "\(item.int64Value(at: "view_at") ?? 0)-\(bvid)",
                title: item.stringValue(at: "title") ?? "",
                coverURL: URL(string: Self.normalizedURLString(coverString) ?? ""),
                bvid: bvid,
                authorName: item.stringValue(at: "author_name") ?? "",
                viewAt: item.int64Value(at: "view_at") ?? 0,
                progress: item.int64Value(at: "progress") ?? 0,
                duration: item.int64Value(at: "duration") ?? 0
            )
        }

        let cursorData = root.dictionaryValue(at: "data", "cursor")
        let nextCursor = FocusHistoryCursor(
            max: cursorData?.int64Value(at: "max") ?? 0,
            viewAt: cursorData?.int64Value(at: "view_at") ?? 0,
            business: cursorData?.stringValue(at: "business") ?? ""
        )

        return FocusMyHistoryPage(
            items: await enrichHistoryItems(rawItems),
            nextCursor: nextCursor.hasMore ? nextCursor : nil
        )
    }

    func fetchFolders(mid: Int64) async throws -> [FocusMyFolder] {
        let root = try await requestObject(
            urlString: "https://api.bilibili.com/x/v3/fav/folder/created/list-all?up_mid=\(mid)&web_location=333.1387",
            referer: "https://www.bilibili.com/"
        )
        let code = root.intValue(at: "code") ?? -1
        if code == -101 {
            throw FocusMyServiceError.loginRequired
        }
        guard code == 0 else {
            throw FocusMyServiceError.message(root.stringValue(at: "message") ?? "收藏夹加载失败")
        }

        let list = root.arrayValue(at: "data", "list") ?? []
        return list.compactMap { folder in
            guard let id = folder.int64Value(at: "id") else {
                return nil
            }
            return FocusMyFolder(
                id: id,
                title: folder.stringValue(at: "title") ?? "",
                mediaCount: folder.intValue(at: "media_count") ?? 0,
                coverURL: URL(string: Self.normalizedURLString(folder.stringValue(at: "cover")) ?? "")
            )
        }
    }

    private func requestObject(urlString: String, referer: String) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else {
            throw FocusMyServiceError.message("请求地址无效")
        }
        return try await requestObject(url: url, referer: referer)
    }

    private func requestObject(url: URL, referer: String) async throws -> [String: Any] {
        let data = try await requestData(url: url, referer: referer)
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let object = raw as? [String: Any] else {
            throw FocusMyServiceError.message("接口返回无效数据")
        }
        return object
    }

    private func requestData(url: URL, referer: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 18
        request.httpMethod = "GET"
        request.setValue(FocusNativePageAugmentService.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(referer, forHTTPHeaderField: "Referer")

        let cookies = await cookieProvider.loadCookies()
        if !cookies.isEmpty {
            request.setValue(cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw FocusMyServiceError.message("网络请求失败")
        }
        return data
    }

    private func enrichHistoryItems(_ items: [FocusMyHistoryItem]) async -> [FocusMyHistoryItem] {
        guard items.contains(where: { $0.coverURL == nil }) else {
            return items
        }

        var resolved: [FocusMyHistoryItem] = []
        resolved.reserveCapacity(items.count)

        for item in items {
            guard item.coverURL == nil else {
                resolved.append(item)
                continue
            }

            guard let resolvedURL = try? await fetchVideoCoverURL(for: item.bvid) else {
                resolved.append(item)
                continue
            }

            resolved.append(
                FocusMyHistoryItem(
                    id: item.id,
                    title: item.title,
                    coverURL: resolvedURL,
                    bvid: item.bvid,
                    authorName: item.authorName,
                    viewAt: item.viewAt,
                    progress: item.progress,
                    duration: item.duration
                )
            )
        }

        return resolved
    }

    private func fetchVideoCoverURL(for bvid: String) async throws -> URL? {
        guard !bvid.isEmpty else {
            return nil
        }

        let root = try await requestObject(
            urlString: "https://api.bilibili.com/x/web-interface/view?bvid=\(bvid)",
            referer: "https://www.bilibili.com/video/\(bvid)"
        )
        guard root.intValue(at: "code") == 0, let cover = root.stringValue(at: "data", "pic") else {
            return nil
        }
        return URL(string: Self.normalizedURLString(cover) ?? "")
    }

    private static func firstString(in rawValue: Any?) -> String? {
        if let string = rawValue as? String {
            return string
        }
        if let array = rawValue as? [Any] {
            for item in array {
                if let string = item as? String, !string.isEmpty {
                    return string
                }
                if let dictionary = item as? [String: Any] {
                    if let string = dictionary.stringValue(at: "self")?.nilIfBlank {
                        return string
                    }
                    if let string = dictionary.stringValue(at: "url")?.nilIfBlank {
                        return string
                    }
                    if let string = dictionary.stringValue(at: "src")?.nilIfBlank {
                        return string
                    }
                }
            }
        }
        return nil
    }

    static func normalizedURLString(_ raw: String?) -> String? {
        guard let raw = raw?.nilIfBlank else {
            return nil
        }
        if raw.lowercased().hasPrefix("http://") {
            return "https://" + raw.dropFirst("http://".count)
        }
        if raw.hasPrefix("//") {
            return "https:\(raw)"
        }
        return raw
    }
}

@MainActor
final class FocusMyViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loginRequired
        case failed(String)
        case loaded(FocusMyPage)
    }

    @Published private(set) var state: State = .idle

    private let service: FocusMyDataService
    private var task: Task<Void, Never>?

    init(service: FocusMyDataService) {
        self.service = service
    }

    deinit {
        task?.cancel()
    }

    var navigationTitle: String {
        "我的"
    }

    func loadIfNeeded() {
        guard case .idle = state else {
            return
        }
        reload()
    }

    func refreshForAppearance() {
        switch state {
        case .idle, .loginRequired, .failed:
            reload()
        case .loading, .loaded:
            break
        }
    }

    func reload() {
        task?.cancel()
        task = Task { [weak self] in
            await self?.performLoad()
        }
    }

    private func performLoad() async {
        state = .loading

        do {
            let page = try await fetchPage()
            guard !Task.isCancelled else {
                return
            }
            state = .loaded(page)
        } catch let error as FocusMyServiceError {
            guard !Task.isCancelled else {
                return
            }
            switch error {
            case .loginRequired:
                state = .loginRequired
            case let .message(message):
                state = .failed(message)
            }
        } catch {
            guard !Task.isCancelled else {
                return
            }
            state = .failed(error.localizedDescription)
        }
    }

    private func fetchPage() async throws -> FocusMyPage {
        let data = try await service.resolveLoggedInNavData()
        let mid = data.int64Value(at: "mid") ?? 0
        let relation = (try? await service.fetchRelation(mid: mid)) ?? (following: 0, followers: 0)
        let history = (try? await service.fetchHistoryPage(pageSize: 12))?.items ?? []
        let folders = (try? await service.fetchFolders(mid: mid)) ?? []

        return FocusMyPage(
            profile: FocusMyProfile(
                mid: mid,
                name: data.stringValue(at: "uname") ?? "",
                avatarURL: URL(string: FocusMyDataService.normalizedURLString(data.stringValue(at: "face")) ?? ""),
                level: data.intValue(at: "level_info", "current_level") ?? 0,
                following: relation.following,
                followers: relation.followers
            ),
            history: history,
            folders: folders
        )
    }
}

@MainActor
final class FocusHistoryViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loginRequired
        case failed(String)
        case loaded([FocusMyHistoryItem])
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isLoadingMore = false

    private let service: FocusMyDataService
    private var nextCursor: FocusHistoryCursor?
    private var task: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?

    init(service: FocusMyDataService) {
        self.service = service
    }

    deinit {
        task?.cancel()
        loadMoreTask?.cancel()
    }

    var navigationTitle: String {
        "播放历史"
    }

    func loadIfNeeded() {
        if case .loaded = state {
            return
        }
        guard case .loading = state else {
            reload()
            return
        }
    }

    func reload() {
        task?.cancel()
        loadMoreTask?.cancel()
        task = Task { [weak self] in
            await self?.performLoad()
        }
    }

    func loadMoreIfNeeded(currentItemID: String) {
        guard case let .loaded(items) = state else {
            return
        }
        guard !isLoadingMore, let nextCursor else {
            return
        }
        guard let index = items.firstIndex(where: { $0.id == currentItemID }), index >= items.count - 6 else {
            return
        }

        isLoadingMore = true
        loadMoreTask?.cancel()
        loadMoreTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let page = try await service.fetchHistoryPage(pageSize: 20, cursor: nextCursor)
                guard !Task.isCancelled else {
                    return
                }

                var seen = Set<String>()
                let merged = (items + page.items).filter { seen.insert($0.id).inserted }
                self.nextCursor = page.nextCursor
                self.state = .loaded(merged)
            } catch {
                // 保留当前历史列表，下一次滚动或下拉刷新时继续尝试。
            }
            self.isLoadingMore = false
        }
    }

    private func performLoad() async {
        state = .loading
        nextCursor = nil

        do {
            let page = try await service.fetchHistoryPage(pageSize: 20)
            guard !Task.isCancelled else {
                return
            }
            nextCursor = page.nextCursor
            state = .loaded(page.items)
        } catch let error as FocusMyServiceError {
            guard !Task.isCancelled else {
                return
            }
            switch error {
            case .loginRequired:
                state = .loginRequired
            case let .message(message):
                state = .failed(message)
            }
        } catch {
            guard !Task.isCancelled else {
                return
            }
            state = .failed(error.localizedDescription)
        }
    }
}

@MainActor
final class FocusUserSpaceViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case failed(String)
        case loaded(FocusUserSpacePage)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isLoadingMoreVideos = false

    private let service: FocusUserSpaceService
    private var currentURL: URL?
    private var currentMID: Int64?
    private var task: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?

    init(service: FocusUserSpaceService) {
        self.service = service
    }

    deinit {
        task?.cancel()
        loadMoreTask?.cancel()
    }

    var navigationTitle: String {
        if case let .loaded(page) = state, !page.profile.name.isEmpty {
            return page.profile.name
        }
        return "UP主空间"
    }

    func open(_ url: URL) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        currentURL = canonicalURL
        currentMID = Self.extractMID(from: canonicalURL)

        guard let currentMID else {
            state = .failed("UP 主空间地址无效")
            return
        }

        if case let .loaded(page) = state, page.profile.mid == currentMID {
            return
        }

        reload()
    }

    func loadIfNeeded() {
        guard currentMID != nil else {
            return
        }
        guard case .idle = state else {
            return
        }
        reload()
    }

    func reload() {
        guard let currentMID else {
            state = .failed("UP 主空间地址无效")
            return
        }

        task?.cancel()
        loadMoreTask?.cancel()
        task = Task { [weak self] in
            await self?.performLoad(mid: currentMID)
        }
    }

    func loadMoreIfNeeded(currentVideoID: String) {
        guard
            let currentMID,
            case let .loaded(page) = state,
            shouldLoadMore(after: currentVideoID, in: page.videos),
            !isLoadingMoreVideos,
            let nextPage = page.nextVideoPage
        else {
            return
        }

        isLoadingMoreVideos = true
        let currentPage = page

        loadMoreTask?.cancel()
        loadMoreTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let payload = try await service.fetchVideoPage(mid: currentMID, page: nextPage)
                guard !Task.isCancelled else {
                    return
                }

                var seen = Set(currentPage.videos.map(\.id))
                let mergedVideos = currentPage.videos + payload.items.filter { seen.insert($0.id).inserted }
                state = .loaded(
                    FocusUserSpacePage(
                        profile: currentPage.profile,
                        videos: mergedVideos,
                        collections: currentPage.collections,
                        articles: currentPage.articles,
                        nextVideoPage: payload.nextPage
                    )
                )
            } catch {
                guard !Task.isCancelled else {
                    return
                }
            }

            if !Task.isCancelled {
                isLoadingMoreVideos = false
            }
        }
    }

    private func performLoad(mid: Int64) async {
        isLoadingMoreVideos = false
        state = .loading

        do {
            let page = try await service.fetchPage(mid: mid)
            guard !Task.isCancelled else {
                return
            }
            state = .loaded(page)
        } catch {
            guard !Task.isCancelled else {
                return
            }
            state = .failed(error.localizedDescription)
        }
    }

    private func shouldLoadMore(after currentVideoID: String, in videos: [FocusUserSpaceVideo]) -> Bool {
        guard let currentIndex = videos.firstIndex(where: { $0.id == currentVideoID }) else {
            return false
        }
        return currentIndex >= max(videos.count - 4, 0)
    }

    private static func extractMID(from url: URL) -> Int64? {
        guard url.host?.lowercased() == "space.bilibili.com" else {
            return nil
        }

        guard let first = url.path.split(separator: "/").first else {
            return nil
        }

        let candidate = String(first)
        guard candidate.allSatisfy(\.isNumber) else {
            return nil
        }

        return Int64(candidate)
    }
}

actor FocusUserSpaceService {
    private struct ProfileSeed {
        let mid: Int64
        let name: String
        let avatarURL: URL?
        let sign: String
        let level: Int
        let videoCount: Int
        let articleCount: Int
    }

    struct VideoPayload {
        let totalCount: Int
        let items: [FocusUserSpaceVideo]
        let nextPage: Int?
    }

    private struct ArticlePayload {
        let totalCount: Int
        let items: [FocusUserSpaceArticle]
    }

    private let cookieProvider: WebViewCookieSnapshotProvider
    private let session: URLSession
    private var cachedWbiKey: String?
    private var cachedWbiExpiration = Date.distantPast

    init(cookieProvider: WebViewCookieSnapshotProvider) {
        self.cookieProvider = cookieProvider
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 24
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: configuration)
    }

    func fetchPage(mid: Int64) async throws -> FocusUserSpacePage {
        async let profileSeedTask = fetchProfileSeed(mid: mid)
        async let relationTask = fetchRelation(mid: mid)
        async let videoTask = fetchVideos(mid: mid)
        async let collectionTask = fetchCollections(mid: mid)
        async let articleTask = fetchArticles(mid: mid)

        let profileSeed = try await profileSeedTask
        let relation = (try? await relationTask) ?? (following: Int64(0), followers: Int64(0))
        let videos = (try? await videoTask) ?? VideoPayload(totalCount: 0, items: [], nextPage: nil)
        let collections = (try? await collectionTask) ?? []
        let articles = (try? await articleTask) ?? ArticlePayload(totalCount: 0, items: [])

        let profile = FocusUserSpaceProfile(
            mid: profileSeed.mid,
            name: profileSeed.name,
            avatarURL: profileSeed.avatarURL,
            sign: profileSeed.sign,
            level: profileSeed.level,
            following: relation.following,
            followers: relation.followers,
            videoCount: max(profileSeed.videoCount, videos.totalCount),
            articleCount: max(profileSeed.articleCount, articles.totalCount)
        )

        return FocusUserSpacePage(
            profile: profile,
            videos: videos.items,
            collections: collections,
            articles: articles.items,
            nextVideoPage: videos.nextPage
        )
    }

    private func fetchProfileSeed(mid: Int64) async throws -> ProfileSeed {
        let query = try await signedWbiQuery(
            parameters: [
                "mid": String(mid),
            ],
            referer: "https://space.bilibili.com/\(mid)"
        )
        let root = try await requestObject(
            urlString: "https://api.bilibili.com/x/space/wbi/acc/info?\(query)",
            referer: "https://space.bilibili.com/\(mid)"
        )
        let code = root.intValue(at: "code") ?? 0
        guard code == 0 else {
            throw URLError(.badServerResponse)
        }

        let data = root.dictionaryValue(at: "data") ?? root
        return ProfileSeed(
            mid: data.int64Value(at: "mid") ?? mid,
            name: data.stringValue(at: "name")?.nilIfBlank ?? data.stringValue(at: "uname")?.nilIfBlank ?? "UP主",
            avatarURL: URL(string: Self.normalizedURLString(data.stringValue(at: "face")) ?? ""),
            sign: data.stringValue(at: "sign")?.nilIfBlank ?? "",
            level: data.intValue(at: "level") ?? data.intValue(at: "level_info", "current_level") ?? 0,
            videoCount: data.intValue(at: "archive_count") ?? data.intValue(at: "archive") ?? 0,
            articleCount: data.intValue(at: "article_count") ?? data.intValue(at: "article") ?? 0
        )
    }

    private func fetchRelation(mid: Int64) async throws -> (following: Int64, followers: Int64) {
        let root = try await requestObject(
            urlString: "https://api.bilibili.com/x/relation/stat?vmid=\(mid)",
            referer: "https://space.bilibili.com/\(mid)"
        )
        let data = root.dictionaryValue(at: "data") ?? root
        return (
            following: data.int64Value(at: "following") ?? 0,
            followers: data.int64Value(at: "follower") ?? 0
        )
    }

    func fetchVideoPage(mid: Int64, page: Int, pageSize: Int = 12) async throws -> VideoPayload {
        let query = try await signedWbiQuery(
            parameters: [
                "mid": String(mid),
                "ps": String(pageSize),
                "pn": String(page),
                "tid": "0",
                "keyword": "",
                "order": "pubdate",
                "order_avoided": "true",
                "platform": "web",
            ],
            referer: "https://space.bilibili.com/\(mid)"
        )
        let root = try await requestObject(
            urlString: "https://api.bilibili.com/x/space/wbi/arc/search?\(query)",
            referer: "https://space.bilibili.com/\(mid)"
        )
        let code = root.intValue(at: "code") ?? 0
        guard code == 0 else {
            return VideoPayload(totalCount: 0, items: [], nextPage: nil)
        }

        let data = root.dictionaryValue(at: "data") ?? root
        let list = data.dictionaryValue(at: "list") ?? data
        let items = list.arrayValue(at: "vlist") ?? data.arrayValue(at: "vlist") ?? []
        let totalCount = data.intValue(at: "page", "count")
            ?? data.intValue(at: "page", "total")
            ?? items.count
        let nextPage = items.isEmpty
            ? nil
            : ((page * pageSize) < totalCount || items.count >= pageSize ? page + 1 : nil)

        return VideoPayload(
            totalCount: totalCount,
            items: items.compactMap { item in
                let bvid = item.stringValue(at: "bvid")?.nilIfBlank ?? ""
                guard !bvid.isEmpty else {
                    return nil
                }

                let createdAt = item.int64Value(at: "created") ?? item.int64Value(at: "pubdate") ?? 0
                return FocusUserSpaceVideo(
                    id: bvid,
                    bvid: bvid,
                    title: Self.cleanText(item.stringValue(at: "title")) .nilIfBlank ?? "视频",
                    coverURL: URL(string: Self.normalizedURLString(item.stringValue(at: "pic")) ?? ""),
                    playText: Self.formatCount(item.int64Value(at: "play") ?? 0),
                    durationText: Self.formatVideoLength(
                        item.stringValue(at: "length"),
                        seconds: item.int64Value(at: "duration")
                    ),
                    publishText: Self.formatDate(createdAt)
                )
            },
            nextPage: nextPage
        )
    }

    private func fetchVideos(mid: Int64) async throws -> VideoPayload {
        try await fetchVideoPage(mid: mid, page: 1)
    }

    private func fetchCollections(mid: Int64) async throws -> [FocusUserSpaceCollection] {
        let query = try await signedWbiQuery(
            parameters: [
                "mid": String(mid),
                "page_num": "1",
                "page_size": "10",
            ],
            referer: "https://space.bilibili.com/\(mid)"
        )
        let root = try await requestObject(
            urlString: "https://api.bilibili.com/x/polymer/web-space/seasons_series_list?\(query)",
            referer: "https://space.bilibili.com/\(mid)"
        )
        let code = root.intValue(at: "code") ?? 0
        guard code == 0 else {
            return []
        }

        let data = root.dictionaryValue(at: "data") ?? root
        let itemsLists = data.dictionaryValue(at: "items_lists") ?? data
        let seasons = itemsLists.arrayValue(at: "seasons_list") ?? []
        let series = itemsLists.arrayValue(at: "series_list") ?? []

        let mappedSeasons = seasons.compactMap { item in
            mapCollection(item: item, mid: mid, kind: .season)
        }
        let mappedSeries = series.compactMap { item in
            mapCollection(item: item, mid: mid, kind: .series)
        }

        return mappedSeasons + mappedSeries
    }

    private func fetchArticles(mid: Int64) async throws -> ArticlePayload {
        let query = try await signedWbiQuery(
            parameters: [
                "mid": String(mid),
                "pn": "1",
                "ps": "6",
                "sort": "publish_time",
            ],
            referer: "https://space.bilibili.com/\(mid)"
        )
        let root = try await requestObject(
            urlString: "https://api.bilibili.com/x/space/wbi/article?\(query)",
            referer: "https://space.bilibili.com/\(mid)"
        )
        let code = root.intValue(at: "code") ?? 0
        guard code == 0 else {
            return ArticlePayload(totalCount: 0, items: [])
        }

        let data = root.dictionaryValue(at: "data") ?? root
        let items = data.arrayValue(at: "articles") ?? data.arrayValue(at: "list") ?? []
        let totalCount = data.intValue(at: "count")
            ?? data.intValue(at: "page", "count")
            ?? items.count

        return ArticlePayload(
            totalCount: totalCount,
            items: items.compactMap { item in
                let id = item.int64Value(at: "id")
                    ?? item.int64Value(at: "cvid")
                    ?? item.int64Value(at: "cv")
                guard let id else {
                    return nil
                }

                let fallbackURL = URL(string: "https://www.bilibili.com/read/cv\(id)")!
                let targetURL = URL(string: Self.normalizedURLString(item.stringValue(at: "share_url")) ?? "")
                    ?? fallbackURL
                return FocusUserSpaceArticle(
                    id: String(id),
                    title: Self.cleanText(item.stringValue(at: "title")).nilIfBlank ?? "专栏",
                    summary: Self.cleanText(
                        item.stringValue(at: "summary")
                            ?? item.stringValue(at: "description")
                    ),
                    coverURL: URL(string: Self.normalizedURLString(
                        item.stringValue(at: "banner_url")
                            ?? item.stringValue(at: "image_url")
                            ?? Self.firstString(in: item["image_urls"])
                            ?? Self.firstString(in: item["covers"])
                    ) ?? ""),
                    publishText: Self.formatDate(
                        item.int64Value(at: "publish_time_seconds")
                            ?? item.int64Value(at: "publish_time")
                            ?? item.int64Value(at: "ctime")
                            ?? 0
                    ),
                    viewText: Self.formatCount(
                        item.int64Value(at: "stats", "view")
                            ?? item.int64Value(at: "view")
                            ?? 0
                    ),
                    targetURL: targetURL
                )
            }
        )
    }

    func fetchCollectionPage(
        collection: FocusUserSpaceCollection,
        page: Int,
        pageSize: Int = 20
    ) async throws -> FocusUserCollectionPage {
        switch collection.kind {
        case .season:
            let query = try await signedWbiQuery(
                parameters: [
                    "mid": String(collection.ownerMID),
                    "season_id": String(collection.rawID),
                    "sort_reverse": "false",
                    "page_num": String(page),
                    "page_size": String(pageSize),
                ],
                referer: "https://space.bilibili.com/\(collection.ownerMID)"
            )
            let root = try await requestObject(
                urlString: "https://api.bilibili.com/x/polymer/web-space/seasons_archives_list?\(query)",
                referer: "https://space.bilibili.com/\(collection.ownerMID)"
            )
            return parseCollectionPage(root: root, collection: collection, page: page, pageSize: pageSize)

        case .series:
            let query = try await signedWbiQuery(
                parameters: [
                    "mid": String(collection.ownerMID),
                    "series_id": String(collection.rawID),
                    "pn": String(page),
                    "ps": String(pageSize),
                    "sort": "desc",
                ],
                referer: "https://space.bilibili.com/\(collection.ownerMID)"
            )
            let root = try await requestObject(
                urlString: "https://api.bilibili.com/x/series/archives?\(query)",
                referer: "https://space.bilibili.com/\(collection.ownerMID)"
            )
            return parseCollectionPage(root: root, collection: collection, page: page, pageSize: pageSize)
        }
    }

    private func parseCollectionPage(
        root: [String: Any],
        collection: FocusUserSpaceCollection,
        page: Int,
        pageSize: Int
    ) -> FocusUserCollectionPage {
        let code = root.intValue(at: "code") ?? 0
        guard code == 0 else {
            return FocusUserCollectionPage(collection: collection, videos: [], nextPage: nil)
        }

        let data = root.dictionaryValue(at: "data") ?? root
        let items = data.arrayValue(at: "archives")
            ?? data.dictionaryValue(at: "list")?.arrayValue(at: "archives")
            ?? data.arrayValue(at: "items")
            ?? []
        let videos = items.compactMap(Self.mapUserSpaceVideo(item:))
        let totalCount = data.intValue(at: "page", "total")
            ?? data.intValue(at: "page", "count")
            ?? data.intValue(at: "meta", "total")
            ?? collection.itemCount
        let nextPage = videos.isEmpty
            ? nil
            : ((page * pageSize) < totalCount || videos.count >= pageSize ? page + 1 : nil)

        return FocusUserCollectionPage(
            collection: collection,
            videos: videos,
            nextPage: nextPage
        )
    }

    private func mapCollection(
        item: [String: Any],
        mid: Int64,
        kind: FocusUserSpaceCollection.Kind
    ) -> FocusUserSpaceCollection? {
        let meta = item.dictionaryValue(at: "meta") ?? item
        let rawID = kind == .season
            ? meta.int64Value(at: "season_id")
            : meta.int64Value(at: "series_id")
        guard let rawID else {
            return nil
        }

        let title = meta.stringValue(at: "name")?.nilIfBlank
            ?? meta.stringValue(at: "title")?.nilIfBlank
            ?? kind.title
        let count = meta.intValue(at: "total")
            ?? meta.intValue(at: "archives_count")
            ?? meta.intValue(at: "media_count")
            ?? item.arrayValue(at: "archives")?.count
            ?? 0
        let updateTime = meta.int64Value(at: "mtime")
            ?? meta.int64Value(at: "ctime")
            ?? meta.int64Value(at: "pub_time")
            ?? 0

        return FocusUserSpaceCollection(
            id: "\(kind.rawValue)-\(rawID)",
            ownerMID: mid,
            rawID: rawID,
            kind: kind,
            title: title,
            subtitle: count > 0 ? "\(kind.title) · \(count) 个视频" : kind.title,
            description: meta.stringValue(at: "description")?.nilIfBlank
                ?? meta.stringValue(at: "desc")?.nilIfBlank
                ?? meta.stringValue(at: "intro")?.nilIfBlank
                ?? "",
            badgeText: updateTime > 0 ? "更新于 \(Self.formatDate(updateTime))" : kind.title,
            coverURL: URL(string: Self.normalizedURLString(
                meta.stringValue(at: "cover")
                    ?? meta.stringValue(at: "image")
            ) ?? ""),
            itemCount: count
        )
    }

    private static func mapUserSpaceVideo(item: [String: Any]) -> FocusUserSpaceVideo? {
        let bvid = item.stringValue(at: "bvid")?.nilIfBlank ?? ""
        guard !bvid.isEmpty else {
            return nil
        }

        let createdAt = item.int64Value(at: "created")
            ?? item.int64Value(at: "pubdate")
            ?? item.int64Value(at: "ptime")
            ?? item.int64Value(at: "ctime")
            ?? 0
        let playValue = item.int64Value(at: "play")
            ?? item.int64Value(at: "stat", "view")
            ?? 0

        return FocusUserSpaceVideo(
            id: bvid,
            bvid: bvid,
            title: Self.cleanText(item.stringValue(at: "title")).nilIfBlank ?? "视频",
            coverURL: URL(string: Self.normalizedURLString(
                item.stringValue(at: "pic")
                    ?? item.stringValue(at: "cover")
            ) ?? ""),
            playText: Self.formatCount(playValue),
            durationText: Self.formatVideoLength(
                item.stringValue(at: "length"),
                seconds: item.int64Value(at: "duration")
            ),
            publishText: Self.formatDate(createdAt)
        )
    }

    private func requestObject(urlString: String, referer: String) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let data = try await requestData(url: url, referer: referer)
        let rawObject = try JSONSerialization.jsonObject(with: data)
        guard let object = rawObject as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return object
    }

    private func requestData(url: URL, referer: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 18
        request.setValue(FocusNativePageAugmentService.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(referer, forHTTPHeaderField: "Referer")

        let cookies = await cookieProvider.loadCookies()
        if !cookies.isEmpty {
            let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func signedWbiQuery(parameters: [String: String], referer: String) async throws -> String {
        let key = try await fetchWbiKey(referer: referer)
        var items = parameters
        items["wts"] = String(Int(Date().timeIntervalSince1970))
        let query = items.keys.sorted().map { key in
            let sanitizedValue = Self.sanitizeWBIValue(items[key] ?? "")
            return "\(key)=\(sanitizedValue)"
        }.joined(separator: "&")
        let wrid = Self.md5Hex(query + key)
        return "\(query)&w_rid=\(wrid)"
    }

    private func fetchWbiKey(referer: String) async throws -> String {
        let now = Date()
        if let cachedWbiKey, now < cachedWbiExpiration {
            return cachedWbiKey
        }

        let nav = try await requestObject(
            urlString: "https://api.bilibili.com/x/web-interface/nav",
            referer: referer
        )
        guard
            let imgURL = nav.stringValue(at: "data", "wbi_img", "img_url"),
            let subURL = nav.stringValue(at: "data", "wbi_img", "sub_url")
        else {
            throw URLError(.cannotParseResponse)
        }

        let imgKey = imgURL.substringAfterLast("/").substringBefore(".")
        let subKey = subURL.substringAfterLast("/").substringBefore(".")
        let raw = imgKey + subKey
        let mixed = Self.wbiMixinTable.reduce(into: "") { partialResult, index in
            guard index < raw.count else {
                return
            }
            partialResult.append(raw[raw.index(raw.startIndex, offsetBy: index)])
        }

        let resolved = String(mixed.prefix(32))
        cachedWbiKey = resolved
        cachedWbiExpiration = now.addingTimeInterval(25 * 60)
        return resolved
    }

    private static func cleanText(_ raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return ""
        }

        return raw.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
    }

    private static func formatVideoLength(_ raw: String?, seconds: Int64?) -> String {
        if let raw = raw?.nilIfBlank {
            return raw
        }
        guard let seconds else {
            return ""
        }
        return formatDuration(seconds)
    }

    private static func formatDuration(_ seconds: Int64) -> String {
        guard seconds > 0 else {
            return ""
        }

        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%lld:%02lld:%02lld", hours, minutes, remainingSeconds)
        }
        return String(format: "%02lld:%02lld", minutes, remainingSeconds)
    }

    private static func formatDate(_ seconds: Int64) -> String {
        guard seconds > 0 else {
            return ""
        }

        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func formatCount(_ value: Int64) -> String {
        guard value > 0 else {
            return ""
        }

        switch value {
        case 100_000_000...:
            return String(format: "%.1f亿", Double(value) / 100_000_000).replacingOccurrences(of: ".0", with: "")
        case 10_000...:
            return String(format: "%.1f万", Double(value) / 10_000).replacingOccurrences(of: ".0", with: "")
        default:
            return "\(value)"
        }
    }

    private static func firstString(in rawValue: Any?) -> String? {
        if let string = rawValue as? String, !string.isEmpty {
            return string
        }
        if let array = rawValue as? [Any] {
            for item in array {
                if let string = item as? String, !string.isEmpty {
                    return string
                }
                if let dictionary = item as? [String: Any] {
                    if let string = dictionary.stringValue(at: "url")?.nilIfBlank {
                        return string
                    }
                    if let string = dictionary.stringValue(at: "src")?.nilIfBlank {
                        return string
                    }
                }
            }
        }
        return nil
    }

    private static func normalizedURLString(_ raw: String?) -> String? {
        guard let raw = raw?.nilIfBlank else {
            return nil
        }
        if raw.lowercased().hasPrefix("http://") {
            return "https://" + raw.dropFirst("http://".count)
        }
        if raw.hasPrefix("//") {
            return "https:\(raw)"
        }
        return raw
    }

    private static func sanitizeWBIValue(_ value: String) -> String {
        value.filter { character in
            !"!'()*".contains(character)
        }
    }

    private static func md5Hex(_ value: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static let wbiMixinTable: [Int] = [
        46, 47, 18, 2, 53, 8, 23, 32,
        15, 50, 10, 31, 58, 3, 45, 35,
        27, 43, 5, 49, 33, 9, 42, 19,
        29, 28, 14, 39, 12, 38, 41, 13,
        37, 48, 7, 16, 24, 55, 40, 61,
        26, 17, 0, 1, 60, 51, 30, 4,
        22, 25, 54, 21, 56, 59, 6, 63,
        57, 62, 11, 36, 20, 34, 44, 52,
    ]
}

@MainActor
final class FocusUserCollectionViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case failed(String)
        case loaded(FocusUserCollectionPage)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isLoadingMoreVideos = false

    private let service: FocusUserSpaceService
    private var currentCollection: FocusUserSpaceCollection?
    private var task: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?

    init(service: FocusUserSpaceService) {
        self.service = service
    }

    deinit {
        task?.cancel()
        loadMoreTask?.cancel()
    }

    var navigationTitle: String {
        switch state {
        case let .loaded(page):
            return page.collection.title
        default:
            return currentCollection?.title ?? "合集"
        }
    }

    func open(_ collection: FocusUserSpaceCollection) {
        currentCollection = collection
        if case let .loaded(page) = state, page.collection.id == collection.id {
            return
        }
        reload()
    }

    func loadIfNeeded() {
        guard currentCollection != nil else {
            return
        }
        guard case .idle = state else {
            return
        }
        reload()
    }

    func reload() {
        guard let currentCollection else {
            state = .failed("合集信息无效")
            return
        }

        task?.cancel()
        loadMoreTask?.cancel()
        task = Task { [weak self] in
            await self?.performLoad(collection: currentCollection)
        }
    }

    func loadMoreIfNeeded(currentVideoID: String) {
        guard
            let collection = currentCollection,
            case let .loaded(page) = state,
            shouldLoadMore(after: currentVideoID, in: page.videos),
            !isLoadingMoreVideos,
            let nextPage = page.nextPage
        else {
            return
        }

        isLoadingMoreVideos = true
        let currentPage = page

        loadMoreTask?.cancel()
        loadMoreTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let payload = try await service.fetchCollectionPage(collection: collection, page: nextPage)
                guard !Task.isCancelled else {
                    return
                }

                var seen = Set(currentPage.videos.map(\.id))
                let mergedVideos = currentPage.videos + payload.videos.filter { seen.insert($0.id).inserted }
                state = .loaded(
                    FocusUserCollectionPage(
                        collection: currentPage.collection,
                        videos: mergedVideos,
                        nextPage: payload.nextPage
                    )
                )
            } catch {
                guard !Task.isCancelled else {
                    return
                }
            }

            if !Task.isCancelled {
                isLoadingMoreVideos = false
            }
        }
    }

    private func performLoad(collection: FocusUserSpaceCollection) async {
        isLoadingMoreVideos = false
        state = .loading

        do {
            let page = try await service.fetchCollectionPage(collection: collection, page: 1)
            guard !Task.isCancelled else {
                return
            }
            state = .loaded(page)
        } catch {
            guard !Task.isCancelled else {
                return
            }
            state = .failed(error.localizedDescription)
        }
    }

    private func shouldLoadMore(after currentVideoID: String, in videos: [FocusUserSpaceVideo]) -> Bool {
        guard let currentIndex = videos.firstIndex(where: { $0.id == currentVideoID }) else {
            return false
        }
        return currentIndex >= max(videos.count - 4, 0)
    }
}

@MainActor
final class FocusArticleViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loginRequired
        case failed(String)
        case loaded(FocusArticlePage)
    }

    @Published private(set) var state: State = .idle

    private let service: FocusArticleService
    private var currentURL: URL?
    private var task: Task<Void, Never>?

    init(service: FocusArticleService) {
        self.service = service
    }

    deinit {
        task?.cancel()
    }

    var navigationTitle: String {
        if case let .loaded(page) = state, !page.title.isEmpty {
            return page.title
        }
        return "专栏"
    }

    func open(_ url: URL) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        guard currentURL != canonicalURL || !isContentLoaded else {
            return
        }

        currentURL = canonicalURL
        task?.cancel()
        task = Task { [weak self] in
            await self?.performLoad(url: canonicalURL)
        }
    }

    func loadIfNeeded() {
        guard currentURL != nil else {
            return
        }
        guard case .idle = state else {
            return
        }
        reload()
    }

    func reload() {
        guard let currentURL else {
            state = .idle
            return
        }

        task?.cancel()
        task = Task { [weak self] in
            await self?.performLoad(url: currentURL)
        }
    }

    private var isContentLoaded: Bool {
        if case .loaded = state {
            return true
        }
        return false
    }

    private func performLoad(url: URL) async {
        state = .loading

        do {
            let page = try await service.fetchPage(for: url)
            guard !Task.isCancelled else {
                return
            }
            state = .loaded(page)
        } catch let error as FocusArticleService.ServiceError {
            guard !Task.isCancelled else {
                return
            }
            switch error {
            case .loginRequired:
                state = .loginRequired
            case let .message(message):
                state = .failed(message)
            }
        } catch {
            guard !Task.isCancelled else {
                return
            }
            state = .failed(error.localizedDescription)
        }
    }
}

final class FocusArticleService: @unchecked Sendable {
    enum ServiceError: Error {
        case loginRequired
        case message(String)
    }

    private let cookieProvider: WebViewCookieSnapshotProvider
    private let session: URLSession

    init(cookieProvider: WebViewCookieSnapshotProvider) {
        self.cookieProvider = cookieProvider
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 24
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: configuration)
    }

    func fetchPage(for url: URL) async throws -> FocusArticlePage {
        guard let cvid = Self.extractCVID(from: url) else {
            throw ServiceError.message("专栏地址无效")
        }

        let root = try await requestObject(
            urlString: "https://api.bilibili.com/x/article/viewinfo?id=\(cvid)",
            referer: url.absoluteString
        )
        let code = root.intValue(at: "code") ?? -1
        if code == -101 {
            throw ServiceError.loginRequired
        }
        guard code == 0, let data = root.dictionaryValue(at: "data") else {
            throw ServiceError.message(root.stringValue(at: "message") ?? "专栏加载失败")
        }

        let authorData = data.dictionaryValue(at: "author") ?? [:]
        let statsData = data.dictionaryValue(at: "stats") ?? [:]
        let tags = (data.arrayValue(at: "tags") ?? []).compactMap {
            $0.stringValue(at: "name")?.nilIfBlank
        }
        let bannerURLString = Self.normalizedURLString(
            data.stringValue(at: "banner_url")
                ?? Self.firstString(in: data["origin_image_urls"])
                ?? Self.firstString(in: data["image_urls"])
        )
        let htmlContent = Self.normalizedArticleHTML(data.stringValue(at: "content") ?? "")

        return FocusArticlePage(
            cvid: cvid,
            title: data.stringValue(at: "title")?.nilIfBlank ?? "专栏",
            author: FocusArticleAuthor(
                mid: authorData.int64Value(at: "mid") ?? 0,
                name: authorData.stringValue(at: "name")?.nilIfBlank ?? "作者",
                avatarURL: URL(string: Self.normalizedURLString(authorData.stringValue(at: "face")) ?? "")
            ),
            publishTime: data.int64Value(at: "publish_time") ?? 0,
            stats: FocusArticleStats(
                views: statsData.int64Value(at: "view") ?? 0,
                likes: statsData.int64Value(at: "like") ?? 0,
                coins: statsData.int64Value(at: "coin") ?? 0,
                favorites: statsData.int64Value(at: "favorite") ?? 0,
                comments: statsData.int64Value(at: "reply") ?? 0
            ),
            bannerURL: URL(string: bannerURLString ?? ""),
            tags: tags,
            htmlContent: htmlContent
        )
    }

    private func requestObject(urlString: String, referer: String) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else {
            throw ServiceError.message("请求地址无效")
        }
        let data = try await requestData(url: url, referer: referer)
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let object = raw as? [String: Any] else {
            throw ServiceError.message("接口返回无效数据")
        }
        return object
    }

    private func requestData(url: URL, referer: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 18
        request.httpMethod = "GET"
        request.setValue(FocusNativePageAugmentService.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(referer, forHTTPHeaderField: "Referer")

        let cookies = await cookieProvider.loadCookies()
        if !cookies.isEmpty {
            request.setValue(cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw ServiceError.message("网络请求失败")
        }
        return data
    }

    private static func extractCVID(from url: URL) -> Int64? {
        let absoluteString = url.absoluteString
        if let match = absoluteString.range(of: #"read/cv(\d+)"#, options: .regularExpression) {
            let matched = String(absoluteString[match])
            return Int64(matched.replacingOccurrences(of: "read/cv", with: ""))
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return components.queryItems?
            .first(where: { $0.name.caseInsensitiveCompare("id") == .orderedSame })?
            .value
            .flatMap(Int64.init)
    }

    private static func normalizedArticleHTML(_ html: String) -> String {
        guard !html.isEmpty else {
            return ""
        }
        return html
            .replacingOccurrences(of: #"(?i)src="//"#, with: #"src="https://"#, options: .regularExpression)
            .replacingOccurrences(of: #"(?i)href="//"#, with: #"href="https://"#, options: .regularExpression)
    }

    private static func firstString(in rawValue: Any?) -> String? {
        if let string = rawValue as? String, !string.isEmpty {
            return string
        }
        if let array = rawValue as? [Any] {
            for item in array {
                if let string = item as? String, !string.isEmpty {
                    return string
                }
                if let dictionary = item as? [String: Any] {
                    if let string = dictionary.stringValue(at: "url")?.nilIfBlank {
                        return string
                    }
                    if let string = dictionary.stringValue(at: "src")?.nilIfBlank {
                        return string
                    }
                }
            }
        }
        return nil
    }

    private static func normalizedURLString(_ raw: String?) -> String? {
        guard let raw = raw?.nilIfBlank else {
            return nil
        }
        if raw.lowercased().hasPrefix("http://") {
            return "https://" + raw.dropFirst("http://".count)
        }
        if raw.hasPrefix("//") {
            return "https:\(raw)"
        }
        return raw
    }
}

@MainActor
final class FocusOpusDetailViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loginRequired
        case failed(String)
        case loaded(FocusOpusDetailPage)
    }

    @Published private(set) var state: State = .idle

    private let detailService: FocusOpusDetailService
    private let augmentService: FocusNativePageAugmentService
    private var currentURL: URL?
    private var task: Task<Void, Never>?

    fileprivate init(
        detailService: FocusOpusDetailService,
        augmentService: FocusNativePageAugmentService
    ) {
        self.detailService = detailService
        self.augmentService = augmentService
    }

    deinit {
        task?.cancel()
    }

    var navigationTitle: String {
        "图文动态"
    }

    func open(_ url: URL) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        guard currentURL != canonicalURL || !isContentLoaded else {
            return
        }
        currentURL = canonicalURL
        task?.cancel()
        task = Task { [weak self] in
            await self?.performLoad(url: canonicalURL)
        }
    }

    func reload() {
        guard let currentURL else {
            state = .idle
            return
        }
        task?.cancel()
        task = Task { [weak self] in
            await self?.performLoad(url: currentURL)
        }
    }

    private var isContentLoaded: Bool {
        if case .loaded = state {
            return true
        }
        return false
    }

    private func performLoad(url: URL) async {
        state = .loading

        do {
            async let detail = detailService.fetchDetail(for: url)
            async let commentsPayload = augmentService.loadPayload(for: url, kind: .opus)

            let detailValue = try await detail
            let comments = await Self.extractComments(from: commentsPayload)

            guard !Task.isCancelled else {
                return
            }
            state = .loaded(
                FocusOpusDetailPage(
                    id: detailValue.id,
                    author: detailValue.author,
                    publishTime: detailValue.publishTime,
                    paragraphs: detailValue.paragraphs,
                    comments: comments
                )
            )
        } catch let error as FocusOpusDetailService.ServiceError {
            guard !Task.isCancelled else {
                return
            }
            switch error {
            case .loginRequired:
                state = .loginRequired
            case let .message(message):
                state = .failed(message)
            }
        } catch {
            guard !Task.isCancelled else {
                return
            }
            state = .failed(error.localizedDescription)
        }
    }

    private static func extractComments(
        from payload: FocusNativePageAugmentPayload?
    ) async -> [FocusNativeCommentPayload] {
        guard let payload else {
            return []
        }
        switch payload {
        case let .opus(data):
            return data.comments
        case .video:
            return []
        }
    }
}

final class FocusOpusDetailService: @unchecked Sendable {
    enum ServiceError: Error {
        case loginRequired
        case message(String)
    }

    private let cookieProvider: WebViewCookieSnapshotProvider
    private let session: URLSession

    init(cookieProvider: WebViewCookieSnapshotProvider) {
        self.cookieProvider = cookieProvider
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 16
        configuration.timeoutIntervalForResource = 24
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    func fetchDetail(for url: URL) async throws -> FocusOpusDetailContent {
        guard let opusID = Self.extractOpusID(from: url) else {
            throw ServiceError.message("图文 ID 无效")
        }

        let features = "onlyfansVote,onlyfansAssetsV2,decorationCard,htmlNewStyle,ugcDelete,editable,opusPrivateVisible"
        let detailURL = "https://api.bilibili.com/x/polymer/web-dynamic/v1/opus/detail?id=\(opusID)&timezone_offset=-480&features=\(features)"
        let root = try await requestObject(urlString: detailURL, referer: url.absoluteString)
        let code = root.intValue(at: "code") ?? -1
        if code == -101 {
            throw ServiceError.loginRequired
        }
        guard code == 0 else {
            throw ServiceError.message(root.stringValue(at: "message") ?? "图文详情加载失败")
        }

        if let item = root.dictionaryValue(at: "data", "item") {
            let basic = item.dictionaryValue(at: "basic") ?? [:]
            let modules = item.dictionaryValue(at: "modules") ?? [:]
            let authorModule = modules.dictionaryValue(at: "module_author") ?? [:]
            let paragraphs = parseParagraphs(modules: modules)
            if !paragraphs.isEmpty {
                return FocusOpusDetailContent(
                    id: basic.stringValue(at: "comment_id_str") ?? basic.stringValue(at: "rid_str") ?? opusID,
                    author: FocusOpusAuthor(
                        name: authorModule.stringValue(at: "name") ?? "用户",
                        mid: authorModule.int64Value(at: "mid") ?? 0,
                        avatarURL: URL(string: Self.normalizedURLString(authorModule.stringValue(at: "face")) ?? "")
                    ),
                    publishTime: authorModule.stringValue(at: "pub_time")
                        ?? authorModule.stringValue(at: "pub_time_text")
                        ?? "",
                    paragraphs: paragraphs
                )
            }
        }

        if let fallback = try await fetchFromDynamicDetail(opusID: opusID) {
            return fallback
        }

        throw ServiceError.message("未能解析图文内容")
    }

    private func fetchFromDynamicDetail(opusID: String) async throws -> FocusOpusDetailContent? {
        let urlString = "https://api.bilibili.com/x/polymer/web-dynamic/v1/detail?id=\(opusID)&features=itemOpusStyle&timezone_offset=-480"
        let root = try await requestObject(urlString: urlString, referer: "https://www.bilibili.com/opus/\(opusID)")
        let code = root.intValue(at: "code") ?? -1
        if code == -101 {
            throw ServiceError.loginRequired
        }
        guard code == 0 else {
            return nil
        }

        guard
            let item = root.dictionaryValue(at: "data", "item"),
            let modules = item.dictionaryValue(at: "modules"),
            let dynamic = modules.dictionaryValue(at: "module_dynamic")
        else {
            return nil
        }

        let author = modules.dictionaryValue(at: "module_author") ?? [:]
        let major = dynamic.dictionaryValue(at: "major")

        var blocks: [FocusOpusBlock] = []
        if let text = dynamic.stringValue(at: "desc", "text") ?? major?.stringValue(at: "opus", "summary", "text"),
           let normalizedText = text.nilIfBlank
        {
            blocks.append(.text([FocusOpusTextNode(text: normalizedText, bold: false, linkURL: nil, emojiURL: nil)]))
        }

        var images: [FocusOpusImage] = []
        func appendPictures(from items: [[String: Any]], keys: [String]) {
            for item in items {
                let rawURL = keys.compactMap { item.stringValue(at: $0) }.first
                guard let rawURL else {
                    continue
                }
                let normalized = Self.normalizedURLString(rawURL)
                images.append(
                    FocusOpusImage(
                        id: normalized ?? UUID().uuidString,
                        url: normalized.flatMap(URL.init(string:)),
                        width: item.intValue(at: "width") ?? 0,
                        height: item.intValue(at: "height") ?? 0
                    )
                )
            }
        }

        if let pics = major?.arrayValue(at: "opus", "pics") {
            appendPictures(from: pics, keys: ["url", "src"])
        }
        if let drawItems = major?.arrayValue(at: "draw", "items") {
            appendPictures(from: drawItems, keys: ["src", "url"])
        }
        if !images.isEmpty {
            blocks.append(.image(images))
        }

        guard !blocks.isEmpty else {
            return nil
        }

        return FocusOpusDetailContent(
            id: opusID,
            author: FocusOpusAuthor(
                name: author.stringValue(at: "name") ?? "用户",
                mid: author.int64Value(at: "mid") ?? 0,
                avatarURL: URL(string: Self.normalizedURLString(author.stringValue(at: "face")) ?? "")
            ),
            publishTime: author.stringValue(at: "pub_time")
                ?? author.stringValue(at: "pub_time_text")
                ?? "",
            paragraphs: [FocusOpusParagraph(blocks: blocks)]
        )
    }

    private func parseParagraphs(modules: [String: Any]) -> [FocusOpusParagraph] {
        let contentModule = modules.dictionaryValue(at: "module_content")
            ?? modules.dictionaryValue(at: "content")
        guard let paragraphs = contentModule?.arrayValue(at: "paragraphs")
            ?? contentModule?.arrayValue(at: "items")
        else {
            return []
        }

        return paragraphs.compactMap { paragraph in
            let paragraphType = paragraph.intValue(at: "para_type")
                ?? paragraph.intValue(at: "type")
            guard let paragraphType else {
                return nil
            }
            let blocks = parseBlocks(paragraph: paragraph, paragraphType: paragraphType)
            guard !blocks.isEmpty else {
                return nil
            }
            return FocusOpusParagraph(blocks: blocks)
        }
    }

    private func parseBlocks(paragraph: [String: Any], paragraphType: Int) -> [FocusOpusBlock] {
        switch paragraphType {
        case 1:
            let nodes = paragraph.arrayValue(at: "text", "nodes")
                ?? paragraph.arrayValue(at: "nodes")
                ?? []
            let textNodes = nodes.compactMap { node -> FocusOpusTextNode? in
                let text = node.stringValue(at: "word", "words")
                    ?? node.stringValue(at: "words")
                    ?? node.stringValue(at: "text")
                    ?? ""
                let bold = (node.intValue(at: "word", "style", "bold") ?? 0) == 1
                    || (node.intValue(at: "style", "bold") ?? 0) == 1
                let linkURL = URL(string: Self.normalizedURLString(node.stringValue(at: "rich", "jump_url")
                    ?? node.stringValue(at: "jump_url")) ?? "")
                let emojiURL = URL(string: Self.normalizedURLString(node.stringValue(at: "rich", "emoji", "icon_url")
                    ?? node.stringValue(at: "emoji", "icon_url")
                    ?? node.stringValue(at: "icon_url")) ?? "")

                guard !text.isEmpty || linkURL != nil || emojiURL != nil else {
                    return nil
                }

                return FocusOpusTextNode(
                    text: text,
                    bold: bold,
                    linkURL: linkURL,
                    emojiURL: emojiURL
                )
            }
            return textNodes.isEmpty ? [] : [.text(textNodes)]

        case 2:
            let pictures = paragraph.arrayValue(at: "pic", "pics")
                ?? paragraph.arrayValue(at: "pics")
                ?? paragraph.arrayValue(at: "images")
                ?? []
            let images = pictures.compactMap { picture -> FocusOpusImage? in
                let rawURL = picture.stringValue(at: "url") ?? picture.stringValue(at: "src")
                guard let normalized = Self.normalizedURLString(rawURL) else {
                    return nil
                }
                return FocusOpusImage(
                    id: normalized,
                    url: URL(string: normalized),
                    width: picture.intValue(at: "width") ?? 0,
                    height: picture.intValue(at: "height") ?? 0
                )
            }
            return images.isEmpty ? [] : [.image(images)]

        case 7:
            let content = paragraph.stringValue(at: "code", "content")
                ?? paragraph.stringValue(at: "content")
                ?? ""
            guard let normalized = content.nilIfBlank else {
                return []
            }
            return [.code(lang: paragraph.stringValue(at: "code", "lang") ?? paragraph.stringValue(at: "lang") ?? "", content: normalized)]

        default:
            return []
        }
    }

    private func requestObject(urlString: String, referer: String) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else {
            throw ServiceError.message("请求地址无效")
        }
        let data = try await requestData(url: url, referer: referer)
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let object = raw as? [String: Any] else {
            throw ServiceError.message("接口返回无效数据")
        }
        return object
    }

    private func requestData(url: URL, referer: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 18
        request.httpMethod = "GET"
        request.setValue(FocusNativePageAugmentService.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(referer, forHTTPHeaderField: "Referer")

        let cookies = await cookieProvider.loadCookies()
        if !cookies.isEmpty {
            request.setValue(cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw ServiceError.message("网络请求失败")
        }
        return data
    }

    private static func extractOpusID(from url: URL) -> String? {
        let host = url.host?.lowercased()
        let components = url.path.split(separator: "/")

        if (host == "www.bilibili.com" || host == "bilibili.com" || host == "m.bilibili.com"),
           let opusIndex = components.firstIndex(of: "opus"),
           components.indices.contains(components.index(after: opusIndex))
        {
            return String(components[components.index(after: opusIndex)]).nilIfBlank
        }

        if host == "t.bilibili.com", let first = components.first {
            let candidate = String(first)
            return candidate.allSatisfy(\.isNumber) ? candidate : nil
        }

        return nil
    }

    private static func normalizedURLString(_ raw: String?) -> String? {
        guard let raw = raw?.nilIfBlank else {
            return nil
        }
        if raw.lowercased().hasPrefix("http://") {
            return "https://" + raw.dropFirst("http://".count)
        }
        if raw.hasPrefix("//") {
            return "https:\(raw)"
        }
        return raw
    }

    struct FocusOpusDetailContent {
        let id: String
        let author: FocusOpusAuthor
        let publishTime: String
        let paragraphs: [FocusOpusParagraph]
    }
}

final class WebViewCookieSnapshotProvider: @unchecked Sendable, CookieSnapshotProvider {
    private let cookieStore: WKHTTPCookieStore
    private let lock = NSLock()
    private var snapshot: [HTTPCookie] = []
    private var hasCompletedInitialWarmup = false

    @MainActor
    init(websiteDataStore: WKWebsiteDataStore = .default()) {
        self.cookieStore = websiteDataStore.httpCookieStore
    }

    func loadCookies() async -> [HTTPCookie] {
        let cookies = await refreshSnapshotIfNeeded()

        lock.withLock {
            snapshot = cookies
        }

        return cookies
    }

    func refreshSnapshotIfNeeded() async -> [HTTPCookie] {
        var cookies = await currentCookies()
        let shouldWarmUp = lock.withLock { !hasCompletedInitialWarmup }

        if shouldWarmUp, !containsLikelyLoginCookies(in: cookies) {
            for delay in [180_000_000, 350_000_000, 700_000_000, 1_100_000_000] {
                try? await Task.sleep(nanoseconds: UInt64(delay))
                cookies = await currentCookies()
                if containsLikelyLoginCookies(in: cookies) {
                    break
                }
            }
        }

        lock.withLock {
            snapshot = cookies
            hasCompletedInitialWarmup = true
        }

        return cookies
    }

    @MainActor
    private func currentCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    func attachCookies(to request: URLRequest) -> URLRequest {
        let cookies = lock.withLock {
            snapshot
        }
        return DynamicFeedService.attach(cookies: cookies, to: request)
    }

    private func containsLikelyLoginCookies(in cookies: [HTTPCookie]) -> Bool {
        let names = Set(cookies.map(\.name))
        return names.contains("SESSDATA")
            || names.contains("DedeUserID")
            || names.contains("bili_jct")
    }
}

private extension Encodable {
    var focusJSONString: String {
        let encoder = JSONEncoder()
        guard
            let data = try? encoder.encode(self),
            let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }
}

private extension Dictionary where Key == String, Value == Any {
    func value(at keys: String...) -> Any? {
        value(at: Array(keys))
    }

    func dictionaryValue(at keys: String...) -> [String: Any]? {
        value(at: keys) as? [String: Any]
    }

    func arrayValue(at keys: String...) -> [[String: Any]]? {
        (value(at: keys) as? [Any])?.compactMap { $0 as? [String: Any] }
    }

    func stringValue(at keys: String...) -> String? {
        if let value = value(at: keys) as? String {
            return value
        }
        if let number = value(at: keys) as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    func intValue(at keys: String...) -> Int? {
        if let number = value(at: keys) as? NSNumber {
            return number.intValue
        }
        if let string = value(at: keys) as? String {
            return Int(string)
        }
        return nil
    }

    func int64Value(at keys: String...) -> Int64? {
        if let number = value(at: keys) as? NSNumber {
            return number.int64Value
        }
        if let string = value(at: keys) as? String {
            return Int64(string)
        }
        return nil
    }

    func boolValue(at keys: String...) -> Bool? {
        if let value = value(at: keys) as? Bool {
            return value
        }
        if let number = value(at: keys) as? NSNumber {
            return number.boolValue
        }
        if let string = value(at: keys) as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private func value(at keys: [String]) -> Any? {
        var current: Any = self
        for key in keys {
            guard let dictionary = current as? [String: Any] else {
                return nil
            }
            guard let next = dictionary[key], !(next is NSNull) else {
                return nil
            }
            current = next
        }
        return current
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func substringAfterLast(_ separator: Character) -> String {
        guard let index = lastIndex(of: separator) else {
            return self
        }
        return String(self[self.index(after: index)...])
    }

    func substringBefore(_ separator: Character) -> String {
        guard let index = firstIndex(of: separator) else {
            return self
        }
        return String(self[..<index])
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
#endif
