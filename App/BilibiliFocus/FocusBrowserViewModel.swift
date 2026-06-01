#if canImport(UIKit)
import Combine
import FocusCore
import Foundation
import WebKit

@MainActor
final class FocusAppViewModel: ObservableObject {
    enum PrimaryTab {
        case dynamic
        case search
        case login
    }

    private static let loginURL = URL(string: "https://passport.bilibili.com/login")!

    @Published private(set) var route: AppRoute = .dynamicFeed
    @Published var showSettings = false
    @Published var showSearch = false
    @Published var searchKeyword = ""

    let settingsStore: FocusSettingsStore
    let browserViewModel: FocusBrowserViewModel
    let dynamicFeedViewModel: FocusDynamicFeedViewModel

    private var didHandleLaunchEntry = false
    private var lastNonBrowserRoute: AppRoute = .dynamicFeed
    private var cancellables: Set<AnyCancellable> = []

    init(settingsStore: FocusSettingsStore) {
        self.settingsStore = settingsStore

        let browserViewModel = FocusBrowserViewModel(settingsStore: settingsStore)
        let cookieProvider = WebViewCookieSnapshotProvider()
        let dynamicFeedViewModel = FocusDynamicFeedViewModel(
            service: DynamicFeedService(cookieProvider: cookieProvider)
        )

        self.browserViewModel = browserViewModel
        self.dynamicFeedViewModel = dynamicFeedViewModel

        browserViewModel.onEntryRequest = { [weak self] entry in
            Task { @MainActor [weak self] in
                self?.open(entry)
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
        case .browser:
            return browserViewModel.navigationTitle
        }
    }

    var activePrimaryTab: PrimaryTab {
        guard isBrowserActive else {
            return .dynamic
        }

        switch browserViewModel.entryContext {
        case .dynamic:
            return .dynamic
        case .search:
            return .search
        case .login:
            return .login
        }
    }

    var isBrowserActive: Bool {
        if case .browser = route {
            return true
        }
        return false
    }

    var showsBrowserBackButton: Bool {
        isBrowserActive
    }

    func handleLaunchEntryIfNeeded() {
        guard !didHandleLaunchEntry else {
            return
        }

        didHandleLaunchEntry = true
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
            lastNonBrowserRoute = .dynamicFeed
            dynamicFeedViewModel.loadIfNeeded()
        case .search:
            showSearch = true
        }
    }

    func open(card: DynamicCard) {
        openBrowser(card.videoURL ?? card.targetURL, context: .dynamic)
    }

    func submitSearch() {
        let query = SearchQuery(keyword: searchKeyword)
        guard !query.keyword.isEmpty else {
            return
        }

        showSearch = false
        openBrowser(query.resultURL, context: .search)
    }

    func openLogin() {
        openBrowser(Self.loginURL, context: .login)
    }

    func reloadCurrent() {
        switch route {
        case .dynamicFeed:
            dynamicFeedViewModel.reload()
        case .browser:
            browserViewModel.reload()
        }
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

    func goForward() {
        guard isBrowserActive else {
            return
        }
        browserViewModel.goForward()
    }

    func closeBrowser() {
        browserViewModel.prepareForDismiss()
        switch lastNonBrowserRoute {
        case .dynamicFeed:
            route = .dynamicFeed
            dynamicFeedViewModel.loadIfNeeded()
        case .browser:
            route = .dynamicFeed
            dynamicFeedViewModel.loadIfNeeded()
        }
    }

    private func openBrowser(_ url: URL, context: FocusBrowserViewModel.EntryContext) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        if case .dynamicFeed = route {
            lastNonBrowserRoute = route
        }
        route = .browser(canonicalURL)
        browserViewModel.open(canonicalURL, context: context)
    }
}

@MainActor
final class FocusBrowserViewModel: ObservableObject {
    enum EntryContext {
        case dynamic
        case search
        case login
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
    var reconfigureScripts: ((WKWebView, FocusSettings) -> Void)?
    var prepareForURL: ((WKWebView, URL) -> Void)?
    var onEntryRequest: ((FocusEntry) -> Void)?

    private var pendingURL: URL?
    private var cancellables: Set<AnyCancellable> = []
    private var playerStateObservationTask: Task<Void, Never>?
    private var embeddedPlayerDetectionTask: Task<Void, Never>?
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

    func resolveAppBackAction() -> AppBackAction {
        guard let targetURL = appBackStack.popLast() else {
            return .close
        }

        return .navigate(targetURL)
    }

    func navigateAppBack(to url: URL) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
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

    func prepareForDismiss() {
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
            return .login
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
            case .login:
                return "登录"
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
        case .login:
            return "登录"
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
        case .login:
            return "login"
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

final class WebViewCookieSnapshotProvider: @unchecked Sendable, CookieSnapshotProvider {
    private let cookieStore: WKHTTPCookieStore
    private let lock = NSLock()
    private var snapshot: [HTTPCookie] = []

    @MainActor
    init(websiteDataStore: WKWebsiteDataStore = .default()) {
        self.cookieStore = websiteDataStore.httpCookieStore
    }

    func loadCookies() async -> [HTTPCookie] {
        let cookies = await currentCookies()

        lock.withLock {
            snapshot = cookies
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
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
#endif
